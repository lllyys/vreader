// Purpose: feature #137 WI-4 (#110 Phase 3, box E) — the two-phase, memory-bounded, cancellable
// pagination engine for the paged TXT/MD renderer.
//
//  Phase 1 (index): measures the whole document ONCE against a chrome-aware content box (via an
//  injected LineMeasurer — the JVM-testable seam abstracting Compose TextMeasurer/MultiParagraph) and
//  cuts a page at the last rendered LINE that fits. It retains ONLY the page-start source-UTF-16
//  offsets (a TxtPageIndex — KB, not MB); it never keeps page AnnotatedStrings or maps. Invariants:
//    • measured-line pagination — an oversized chunk (a runaway line ≥ DEFAULT_MAX_CHUNK_CHARS) SPLITS
//      MID-CHUNK at a measured line boundary; the split line-start maps back to a source offset via the
//      chunk map (Gate-2 R2 Crit-2).
//    • min-one-line — a page ALWAYS holds ≥1 line even if it overflows vertically (forward progress —
//      no zero-advance page / infinite loop; Gate-2 R3 Critical).
//    • degenerate box (≤0 usable width/height) → returns TxtPageIndex.degenerate() so the host degrades
//      to scroll (bounded, no crash/loop).
//    • paginator-LOCAL mapper — phase-1 builds its OWN MarkdownChunkTextMapper; it NEVER touches the
//      shared UI-thread mapper (Gate-2 R3 High — no cross-thread mutable-LRU access).
//    • generation-token cancellable — a stale token aborts and never publishes.
//
//  Phase 2 (renderPage): lazily renders ONE page's source range through the (UI-thread) mapper into an
//  AnnotatedString + a composed span-preserving PageOffsetMap. NO synthetic separators — TxtDocument
//  chunks already retain their line terminators, so a page render is exactly the covered source
//  sub-range rendered through the same mapper the scroll body uses.
//
// @coordinates-with: TxtPageIndex.kt (the boundary index it produces), PageOffsetMap.kt (the composed
//   page map renderPage builds), ChunkTextMapper.kt / MarkdownChunkTextMapper (the render+cache seam),
//   TxtDocument.kt (the chunk source), TxtPageNavigator.kt (WI-5 consumer).
package com.vreader.app.reader.paged

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.TextStyle
import com.vreader.app.reader.ChunkTextMapper
import com.vreader.app.reader.IdentityChunkTextMapper
import com.vreader.app.reader.MarkdownChunkTextMapper
import com.vreader.app.reader.MarkdownOffsetMap
import com.vreader.app.reader.MarkdownRenderer
import com.vreader.app.reader.TxtDocument
import com.vreader.app.reader.Utf16Range
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicBoolean

/** The chrome-aware content box a page's lines are measured against (px). */
data class PageContentBox(val widthPx: Float, val heightPx: Float) {
    /** No usable area to lay out even a single line — pagination must degrade to scroll. */
    val isDegenerate: Boolean get() = widthPx <= 0f || heightPx <= 0f
}

/** One measured (wrapped) line: its char range within the measured text + its laid-out height (px). */
data class LineMetric(val startInclusive: Int, val endExclusive: Int, val heightPx: Float)

/**
 * The line-measurement seam. The real (WI-6a) impl wraps Compose `TextMeasurer`/`MultiParagraph`; JVM
 * tests inject a deterministic fake. Measures [text] wrapped at [maxWidthPx] under [style] → its lines.
 */
fun interface LineMeasurer {
    fun measure(text: CharSequence, style: TextStyle, maxWidthPx: Float): List<LineMetric>
}

/**
 * A monotonic generation token. A settings/rotation change constructs a NEW token and `cancel()`s the
 * old one; phase-1 checks it and aborts (throws [CancellationException]) so a stale pass never publishes.
 */
class PaginationToken {
    private val cancelled = AtomicBoolean(false)
    val isCancelled: Boolean get() = cancelled.get()
    fun cancel() { cancelled.set(true) }
}

/**
 * @param indexDispatcher the dispatcher phase-1 ([index]) runs its whole-doc measure pass on — default
 *   `Dispatchers.Default` (off-main enforced, NOT just by-contract; Gate-4 High-2). Tests inject a test
 *   dispatcher.
 */
class TxtPaginator(private val indexDispatcher: CoroutineDispatcher = Dispatchers.Default) {

    /**
     * PHASE 1 — measure the whole document against [contentBox] and return the page-boundary index.
     * Runs on [indexDispatcher] (off-main, enforced). Constructs its OWN paginator-local chunk mapper
     * ([isMarkdown] picks Markdown vs Identity — so a TXT `*`/`#` is NOT stripped as a marker) — NEVER
     * the shared UI mapper. Honors both [token] and coroutine cancellation. A degenerate box returns
     * [TxtPageIndex.degenerate]; an empty doc returns 0 pages.
     */
    suspend fun index(
        document: TxtDocument,
        style: TextStyle,
        contentBox: PageContentBox,
        measurer: LineMeasurer,
        token: PaginationToken,
        isMarkdown: Boolean = false,
    ): TxtPageIndex = withContext(indexDispatcher) {
        // Cancellation is checked FIRST — a stale token aborts even the degenerate/empty early returns
        // (Gate-4 Medium-1).
        checkCancelled(token)
        if (contentBox.isDegenerate) return@withContext TxtPageIndex.degenerate()
        val docEnd = document.text.length
        if (document.chunkCount == 0) return@withContext TxtPageIndex(IntArray(0), docEndExclusive = docEnd)

        // Paginator-LOCAL mapper (its OWN LRU) — NEVER the shared UI-thread mapper (no cross-thread
        // mutable-LRU access; Gate-2 R3 High). Format-correct: Markdown strips markers, Identity does
        // not — the ONLY thing phase-1 needs is each rendered-line-start's source offset.
        val localMapper = LocalChunkOffsetMapper(document, isMarkdown)

        val starts = GrowableIntArray()
        var currentPageHeight = 0f
        var pageHasLine = false

        // Central page-start push with a STRICT-ADVANCE guard: a candidate start that does NOT advance past
        // the last page start (e.g. two narrow measured lines both mapping to the same source offset — an MD
        // inserted-glyph bullet maps `•` and its space to source [0,2)) is REJECTED and the line stays on
        // the current page. This preserves the forward-progress invariant — no zero-advance page (Gate-4 High-1).
        fun tryStartPage(candidate: Int): Boolean {
            if (starts.size == 0 || candidate > starts.last()) { starts.push(candidate); return true }
            return false
        }

        for (chunkIndex in 0 until document.chunkCount) {
            checkCancelled(token)
            val chunkDocStart = document.offsetForChunk(chunkIndex)
            val rendered = localMapper.renderedText(chunkIndex)
            val lines = measurer.measure(rendered, style, contentBox.widthPx)
            for (line in lines) {
                val candidate = sourceOffsetForLineStart(localMapper, chunkIndex, chunkDocStart, line)
                val fits = currentPageHeight + line.heightPx <= contentBox.heightPx
                if (!pageHasLine) {
                    // The whole doc's first line: starts.size is 0 here, so tryStartPage always pushes
                    // page 0 at document offset 0. min-one-line forward progress.
                    tryStartPage(candidate)
                    currentPageHeight = line.heightPx
                    pageHasLine = true
                } else if (fits) {
                    currentPageHeight += line.heightPx
                } else {
                    // Cut a NEW page at this line's source start — but only if it strictly advances; a
                    // non-advancing candidate keeps the line on the current page (may overflow — that's the
                    // min-one-line trade the invariant accepts) so we never emit a zero-advance page.
                    if (tryStartPage(candidate)) {
                        currentPageHeight = line.heightPx
                    } else {
                        currentPageHeight += line.heightPx
                    }
                }
            }
        }
        checkCancelled(token)
        // No page was ever started (all chunks measured to zero lines) → whole doc is one page.
        if (starts.size == 0) starts.push(0)
        TxtPageIndex(starts.toIntArray(), docEndExclusive = docEnd)
    }

    /**
     * PHASE 2 — lazily render ONE page's source range `[pageStart, pageEnd)` through [mapper] into an
     * AnnotatedString + composed [PageOffsetMap]. Concatenates the covered chunks' rendered outputs
     * with NO synthetic separators (chunks retain their EOLs); mid-chunk boundaries carry the chunk
     * map's sub-range so offsets stay exact across a split.
     *
     * [isMarkdown] selects the segment shape EXPLICITLY (Gate-4 Medium-2 — never an `is` downcast, so a
     * mapper wrapper/decorator around a Markdown mapper can't fall into the TXT identity branch): true →
     * MD segments backed by the chunk's real [MarkdownOffsetMap]; false → TXT identity segments. It MUST
     * match the [mapper]'s format (the host picks both from `book.originalFormat`).
     */
    fun renderPage(
        document: TxtDocument,
        index: TxtPageIndex,
        page: Int,
        mapper: ChunkTextMapper,
        @Suppress("UNUSED_PARAMETER") style: TextStyle,
        isMarkdown: Boolean = false,
    ): Pair<AnnotatedString, PageOffsetMap> {
        if (index.isEmpty) return AnnotatedString("") to PageOffsetMap(emptyList())
        val p = page.coerceIn(0, index.pageCount - 1)
        val pageStart = index.pageStart(p)
        val pageEnd = index.pageEndExclusive(p)

        val builder = AnnotatedString.Builder()
        val segments = ArrayList<PageSegment>()
        var renderedBase = 0

        val firstChunk = document.chunkForOffset(pageStart)
        val lastChunk = document.chunkForOffset((pageEnd - 1).coerceAtLeast(pageStart))
        for (chunkIndex in firstChunk..lastChunk) {
            val chunkDocStart = document.offsetForChunk(chunkIndex)
            val chunkText = document.textForChunk(chunkIndex).toString()
            val chunkDocEnd = chunkDocStart + chunkText.length
            // The source sub-range of THIS chunk covered by the page (mid-chunk splits at both ends).
            val subStart = maxOf(pageStart, chunkDocStart) - chunkDocStart          // chunk-local
            val subEnd = minOf(pageEnd, chunkDocEnd) - chunkDocStart                 // chunk-local
            if (subEnd <= subStart) continue

            // The chunk's FULL rendered text + a chunk-local map (identity for TXT, MarkdownOffsetMap for MD).
            val chunkRendered = mapper.renderedText(chunkIndex)
            // The rendered range covering the source sub-range (start-affinity start, end-affinity end).
            val renderedSub = mapper.sourceRangeToRendered(chunkIndex, Utf16Range(subStart, subEnd))
            val rs = renderedSub.startInclusive.coerceIn(0, chunkRendered.length)
            val re = renderedSub.endExclusive.coerceIn(rs, chunkRendered.length)
            if (re <= rs && !(subStart == 0 && subEnd == chunkText.length)) {
                // Marker-only source sub-range with nothing rendered — still advance the source, no glyphs.
                continue
            }

            val slice = chunkRendered.subSequence(rs, re)
            builder.append(slice)
            segments.add(pageSegmentFor(mapper, document, isMarkdown, chunkIndex, chunkDocStart, renderedBase, rs, re))
            renderedBase += slice.length
        }
        return builder.toAnnotatedString() to PageOffsetMap(segments)
    }

    // --- helpers -------------------------------------------------------------------------------

    /**
     * GLOBAL source offset a page beginning at this measured line should START at — chosen so pages
     * TILE the source contiguously (no dropped source, no gap for a resume):
     *  • a line at the chunk's rendered index 0 → the chunk's document start (leading stripped markers
     *    belong to THIS page, and the first page starts at document offset 0).
     *  • a mid-chunk split (rendered index > 0) → the END-affinity source of everything rendered BEFORE
     *    this line (`srcEnd[lineStart-1]`), so any stripped marker between the two lines is attributed to
     *    the earlier page and no source char is skipped.
     */
    private fun sourceOffsetForLineStart(
        mapper: LocalChunkOffsetMapper,
        chunkIndex: Int,
        chunkDocStart: Int,
        line: LineMetric,
    ): Int {
        val lineStart = line.startInclusive
        if (lineStart <= 0) return chunkDocStart
        val before = mapper.renderedRangeToSource(chunkIndex, Utf16Range(0, lineStart))
        return chunkDocStart + before.endExclusive
    }

    /**
     * Build a [PageSegment] for a chunk's rendered sub-range `[renderedStart, renderedEnd)`, keyed on the
     * EXPLICIT [isMarkdown] flag (never an `is` downcast — Gate-4 Medium-2):
     *  • MD → a segment backed by the chunk's real [MarkdownOffsetMap] (rebuilt from the chunk SOURCE text
     *    so dual-affinity is preserved), whole-chunk OR mid-chunk-sliced.
     *  • TXT → an identity segment; rendered == source, `srcBase` is the slice's global source start
     *    (exact for a mid-chunk split because rendered/source advance 1:1).
     */
    private fun pageSegmentFor(
        mapper: ChunkTextMapper,
        document: TxtDocument,
        isMarkdown: Boolean,
        chunkIndex: Int,
        chunkDocStart: Int,
        renderedBase: Int,
        renderedStart: Int,
        renderedEnd: Int,
    ): PageSegment {
        val len = renderedEnd - renderedStart
        return if (isMarkdown) {
            val chunkMap = MarkdownOffsetMap(MarkdownRenderer.renderWithMap(document.textForChunk(chunkIndex).toString()))
            if (renderedStart == 0 && renderedEnd == chunkMap.renderedText.length) {
                PageSegment.markdown(chunkMap, renderedBase = renderedBase, srcBase = chunkDocStart)
            } else {
                PageSegment.markdownSlice(
                    chunkMap, renderedBase = renderedBase, srcBase = chunkDocStart,
                    renderedStartInChunk = renderedStart, renderedLen = len,
                )
            }
        } else {
            // TXT identity: the slice's global source start is start-affinity of its rendered start.
            val sliceSrcStart = chunkDocStart +
                mapper.renderedRangeToSource(chunkIndex, Utf16Range(renderedStart, renderedStart)).startInclusive
            PageSegment.identity(renderedBase = renderedBase, srcBase = sliceSrcStart, renderedLen = len)
        }
    }

    private fun checkCancelled(token: PaginationToken) {
        if (token.isCancelled) throw CancellationException("pagination token cancelled")
    }
}

/**
 * Phase-1's OWN chunk offset mapper (paginator-local) — gives (a) each chunk's rendered text and
 * (b) rendered→source for a line start. It NEVER shares the UI-thread mapper. Format-correct: a
 * Markdown mapper for .md (markers stripped), an Identity mapper for .txt (raw, so `*`/`#` stay).
 */
private class LocalChunkOffsetMapper(doc: TxtDocument, isMarkdown: Boolean) {
    private val inner: ChunkTextMapper =
        if (isMarkdown) MarkdownChunkTextMapper(doc) else IdentityChunkTextMapper(doc)
    fun renderedText(chunkIndex: Int): AnnotatedString = inner.renderedText(chunkIndex)
    fun renderedRangeToSource(chunkIndex: Int, rendered: Utf16Range): Utf16Range =
        inner.renderedRangeToSource(chunkIndex, rendered)
}

/** A primitive growable IntArray (no Int boxing) for the page-start offsets. */
private class GrowableIntArray {
    private var buf = IntArray(64)
    var size = 0; private set
    fun push(v: Int) {
        if (size == buf.size) buf = buf.copyOf(buf.size * 2)
        buf[size++] = v
    }
    /** The last pushed value (caller guarantees size > 0). */
    fun last(): Int = buf[size - 1]
    fun toIntArray(): IntArray = buf.copyOf(size)
}
