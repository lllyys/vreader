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
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
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

    companion object {
        /**
         * Feature #138 WI-3 — the number of pages the SESSION (WI-4) seals in the FIRST windowed pass
         * from a fresh doc-start cursor before publishing (and launching background completion). Sized
         * to fill the first screen plus a small forward buffer so a page-turn near the frontier already
         * has its successor sealed (the +1-page lookahead is inherent in the seal discipline).
         */
        const val DEFAULT_INITIAL_WINDOW_PAGES = 3

        /**
         * Feature #138 WI-3 — the number of ADDITIONAL pages the session seals per on-demand forward
         * extension (`measurePages(cursor, DEFAULT_EXTEND_PAGES)`) when the reader nears the sealed
         * frontier. Smaller than the initial window: an extension is an incremental top-up, not a
         * first-fill.
         */
        const val DEFAULT_EXTEND_PAGES = 2
    }

    /**
     * PHASE 1 — measure the whole document against [contentBox] and return the page-boundary index.
     * Runs on [indexDispatcher] (off-main, enforced). Constructs its OWN paginator-local chunk mapper
     * ([isMarkdown] picks Markdown vs Identity — so a TXT `*`/`#` is NOT stripped as a marker) — NEVER
     * the shared UI mapper. Honors both [token] and coroutine cancellation. A degenerate box returns
     * [TxtPageIndex.degenerate]; an empty doc returns 0 pages.
     *
     * Re-implemented on the RESUMABLE CORE (feature #138 WI-1): a fresh doc-start cursor is driven to
     * completion with an unbounded stop condition, collecting every sealed start. Behavior is
     * byte-identical to the pre-#138 whole-document loop for every document — the same tiling logic
     * (min-one-line, oversized mid-chunk split, strict-advance) lives in ONE place ([measureFrom]).
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
        // (Gate-4 Medium-1). freshCursor mirrors that (degenerate/empty → an already-complete cursor).
        checkCancelled(token)
        if (contentBox.isDegenerate) return@withContext TxtPageIndex.degenerate()

        val starts = GrowableIntArray()
        var cursor = freshCursor(document, style, contentBox, measurer, isMarkdown)
        // Drive to completion with NO page/offset bound. Chunk-by-chunk under checkCancelled — the SAME
        // sequential carry the whole-doc loop used, now factored into the resumable core.
        while (!cursor.isComplete) {
            cursor = measureFrom(cursor, StopCondition.None, token) { starts.push(it) }
        }
        TxtPageIndex(starts.toIntArray(), docEndExclusive = cursor.run.docEndExclusive)
    }

    // --- resumable measure core (feature #138 WI-1) --------------------------------------------

    /**
     * The stop condition a bounded resumable measure step honors. The core still processes whole
     * CHUNKS (the natural resumable boundary — the sequential carry is captured there), so the step
     * seals AT LEAST enough to satisfy the bound and stops at the next chunk boundary; it never
     * over-seals in a way that changes the page-start SEQUENCE (only where a window happens to end).
     */
    private sealed interface StopCondition {
        /** Drive to doc end (the `index(...)` completion path). */
        data object None : StopCondition
        /** Stop once [count] more page starts have been emitted THIS step (or doc end). */
        data class Pages(val count: Int) : StopCondition
        /** Stop once the sealed frontier covers [offset] — a sealed page whose start is `<= offset`
         *  AND whose successor start is `> offset` exists (or doc end). */
        data class ThroughOffset(val offset: Int) : StopCondition
    }

    /**
     * Start a fresh doc-start-forward pass at chunk 0. Constructs the ONE paginator-local mapper for
     * the whole pass (never the shared UI mapper). A degenerate box or empty doc yields an
     * already-[MeasureCursor.isComplete] cursor that seals no pages — the `index(...)` early returns,
     * expressed as a completed cursor so the core has ONE completion path.
     *
     * `internal` — consumed by [index] (WI-1) and PaginationSession (WI-4); NEVER exposed publicly.
     */
    internal fun freshCursor(
        document: TxtDocument,
        style: TextStyle,
        contentBox: PageContentBox,
        measurer: LineMeasurer,
        isMarkdown: Boolean,
    ): MeasureCursor {
        val docEnd = document.text.length
        val run = MeasureRun(
            document = document, style = style, contentBox = contentBox, measurer = measurer,
            mapper = LocalChunkOffsetMapper(document, isMarkdown), docEndExclusive = docEnd,
        )
        // Degenerate box / empty doc → a completed cursor with zero starts (matches index's early
        // returns; a degenerate box's index becomes TxtPageIndex.degenerate() at the index() layer).
        val complete = contentBox.isDegenerate || document.chunkCount == 0
        return MeasureCursor(
            run = run, nextChunk = 0, carryHeight = 0f, carryHasLine = false,
            currentPageStart = -1, lastSealedStart = -1,
            frontierSourceOffset = if (complete) docEnd else 0,
            isComplete = complete, emittedAnyStart = false,
        )
    }

    /**
     * Seal at least [additionalPages] more page starts (or reach doc end), emitting each newly-SEALED
     * page START via [emit], and return the advanced cursor. A completed cursor — or a non-positive
     * [additionalPages] — is a no-op (returns [cursor] unchanged, emits nothing). `internal`.
     */
    internal suspend fun measurePages(
        cursor: MeasureCursor, additionalPages: Int, token: PaginationToken, emit: (Int) -> Unit,
    ): MeasureCursor {
        if (additionalPages < 1) return cursor
        return withContext(indexDispatcher) { measureFrom(cursor, StopCondition.Pages(additionalPages), token, emit) }
    }

    /**
     * Seal contiguous pages forward until the sealed frontier covers [targetOffset] (a SEALED page
     * whose `[start, end)` contains it exists) or doc end, emitting each newly-SEALED page START via
     * [emit], and return the advanced cursor. A negative [targetOffset] is clamped to 0. A completed
     * cursor is a no-op. `internal`.
     */
    internal suspend fun measureThroughOffset(
        cursor: MeasureCursor, targetOffset: Int, token: PaginationToken, emit: (Int) -> Unit,
    ): MeasureCursor = withContext(indexDispatcher) {
        measureFrom(cursor, StopCondition.ThroughOffset(targetOffset.coerceAtLeast(0)), token, emit)
    }

    /**
     * THE ONE place the tiling logic lives (min-one-line, oversized mid-chunk split, strict-advance)
     * AND the sealed-page emission rule (Gate-2 R2 Medium 1). Resumes from [cursor] (its saved
     * sequential carry is the exact whole-doc-loop boundary state), measures whole chunks forward, and
     * SEALS a page — emitting its start via [emit] — only once the NEXT page's start is discovered (so
     * the sealed page's exclusive end is final); the FINAL page seals at doc end. Discovering the first
     * page start does NOT seal it (a +1-page lookahead); only its successor seals it. If no page was
     * ever started on a non-empty doc, page 0 seals at doc end at offset 0. Stops at the next chunk
     * boundary once [stop] is satisfied, or at doc end. The returned cursor is the advanced immutable
     * copy. Honors [token] AND coroutine cancellation ([ensureActive]).
     */
    private suspend fun measureFrom(
        cursor: MeasureCursor, stop: StopCondition, token: PaginationToken, emit: (Int) -> Unit,
    ): MeasureCursor {
        checkCancelled(token)
        if (cursor.isComplete) return cursor

        val run = cursor.run
        val document = run.document
        var nextChunk = cursor.nextChunk
        var carryHeight = cursor.carryHeight
        var carryHasLine = cursor.carryHasLine
        var currentPageStart = cursor.currentPageStart      // the in-progress, NOT-yet-sealed page start
        var lastSealedStart = cursor.lastSealedStart        // the most recently emitted (sealed) start
        var emittedAny = cursor.emittedAnyStart
        var sealedThisStep = 0

        // Begin a NEW page at [candidate] with a STRICT-ADVANCE guard against the CURRENT (pending)
        // page start: a candidate that does NOT advance past it (e.g. two narrow measured lines both
        // mapping to the same source offset — an MD inserted-glyph bullet maps `•` and its space to
        // source [0,2)) is REJECTED, keeping the line on the current page (no zero-advance page). When
        // it DOES advance, the PREVIOUS page is now SEALED (its successor's start is known) → emit it,
        // and this candidate becomes the new pending page start.
        fun tryStartPage(candidate: Int): Boolean {
            if (currentPageStart < 0 || candidate > currentPageStart) {
                if (currentPageStart >= 0) { emit(currentPageStart); lastSealedStart = currentPageStart; sealedThisStep++ }
                currentPageStart = candidate
                emittedAny = true
                return true
            }
            return false
        }

        // The frontier marker = the pending page start when a page is in progress, else the source
        // offset consumed so far. It is the exclusive end of the last sealed page.
        fun frontierNow(): Int =
            if (currentPageStart >= 0) currentPageStart
            else if (nextChunk < document.chunkCount) document.offsetForChunk(nextChunk) else run.docEndExclusive

        fun bound(): Boolean = when (stop) {
            StopCondition.None -> false
            is StopCondition.Pages -> sealedThisStep >= stop.count
            // Covered once a SEALED page whose [start, end) contains offset exists: a sealed start
            // `<= offset` AND the successor (pending) start `> offset` (== that sealed page's end).
            is StopCondition.ThroughOffset ->
                lastSealedStart in 0..stop.offset && currentPageStart > stop.offset
        }

        while (nextChunk < document.chunkCount) {
            checkCancelled(token)
            currentCoroutineContext().ensureActive()   // cooperative coroutine cancellation per chunk
            val chunkDocStart = document.offsetForChunk(nextChunk)
            val rendered = run.mapper.renderedText(nextChunk)
            val lines = run.measurer.measure(rendered, run.style, run.contentBox.widthPx)
            for (line in lines) {
                val candidate = sourceOffsetForLineStart(run.mapper, nextChunk, chunkDocStart, line)
                val fits = carryHeight + line.heightPx <= run.contentBox.heightPx
                if (!carryHasLine) {
                    // The whole doc's first line: currentPageStart is -1 here, so tryStartPage always
                    // begins page 0 at document offset 0 (it seals later, at its successor or doc end).
                    tryStartPage(candidate)
                    carryHeight = line.heightPx
                    carryHasLine = true
                } else if (fits) {
                    carryHeight += line.heightPx
                } else {
                    // Cut a NEW page at this line's source start — but only if it strictly advances; a
                    // non-advancing candidate keeps the line on the current page (may overflow — the
                    // min-one-line trade) so we never emit a zero-advance page.
                    if (tryStartPage(candidate)) carryHeight = line.heightPx else carryHeight += line.heightPx
                }
            }
            nextChunk++
            if (bound()) break
        }

        val complete = nextChunk >= document.chunkCount
        if (complete) {
            checkCancelled(token)
            // No page was ever started (all chunks measured to zero lines) → whole doc is one page at 0.
            if (!emittedAny) { currentPageStart = 0; emittedAny = true }
            // The final in-progress page seals at doc end (its exclusive end == docEndExclusive).
            if (currentPageStart >= 0) { emit(currentPageStart); lastSealedStart = currentPageStart; sealedThisStep++ }
            currentPageStart = -1   // nothing pending once complete
        }
        val frontier = if (complete) run.docEndExclusive else frontierNow()
        return cursor.copy(
            nextChunk = nextChunk, carryHeight = carryHeight, carryHasLine = carryHasLine,
            currentPageStart = currentPageStart, lastSealedStart = lastSealedStart,
            frontierSourceOffset = frontier, isComplete = complete, emittedAnyStart = emittedAny,
        )
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
internal class LocalChunkOffsetMapper(doc: TxtDocument, isMarkdown: Boolean) {
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
