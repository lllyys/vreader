// Purpose: feature #131 WI-4a — the TXT/MD ChapterTextProvider. A .txt/.md is one
// flat translation document with NO chapter model; this provider segments
// `document.text` ONCE (paragraph granularity in v1 — H1/H3) into half-open
// UTF-16 `Utf16Span`s via ChapterSegmenter.paragraphRanges, groups the contiguous
// segments into fixed-size UNIT WINDOWS (a document-global `TranslationUnitId`
// index — NOT a TxtDocument chunk index), and resolves the reader's saved
// UTF-16 offset to the window it falls in via a segment-start binary search.
//
// The single segment span array is the source of truth for both the translate side
// (sourceSegments) and — in later WIs — the render side, so the two segment
// identically by construction. Spans are half-open `[start, endExclusive)` against
// the SAME backing string, so a segment ending in the document's final line never
// clamp-collapses to empty (H1: this provider reads `paragraphRanges` spans, never
// `TxtDocument.offsetForChunk(last+1)`, so the clamp footgun cannot bite).
//
// MD source = raw markdown segment text (paragraph-split over the raw markdown
// string; markers are ordinary characters to the blank-line splitter), distinguished
// only by the unit `Kind` (mdDocSegmentWindow vs txtDocSegmentWindow) so a TXT and MD
// with identical text still get distinct cache rows.
//
// @coordinates-with: ChapterTextProvider.kt, ChapterSegmenter.kt, Utf16Span.kt,
//   TranslationUnitId.kt, com.vreader.app.reader.TxtDocument,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-4a)
package com.vreader.app.bilingual

import com.vreader.app.reader.TxtDocument

/**
 * A [ChapterTextProvider] over a decoded [TxtDocument]. Segments the whole document
 * ONCE into paragraph [Utf16Span]s and groups them into fixed-size [windowSize]
 * unit windows. [kind] is `txtDocSegmentWindow` for `.txt` or `mdDocSegmentWindow`
 * for `.md`; each window's [TranslationUnitId.value] is its document-global window
 * index as a decimal string.
 */
class TxtChapterTextProvider(
    private val document: TxtDocument,
    kind: TranslationUnitId.Kind = TranslationUnitId.Kind.txtDocSegmentWindow,
    windowSize: Int = DEFAULT_WINDOW_SIZE,
) : ChapterTextProvider {

    init {
        require(
            kind == TranslationUnitId.Kind.txtDocSegmentWindow ||
                kind == TranslationUnitId.Kind.mdDocSegmentWindow,
        ) { "TxtChapterTextProvider only addresses txt/md segment-window kinds, got $kind" }
    }

    private val kind: TranslationUnitId.Kind = kind
    private val windowSize: Int = maxOf(1, windowSize)

    /** The document-global paragraph segment spans, produced ONCE (half-open, source-coordinate). */
    private val segmentSpans: List<Utf16Span> = ChapterSegmenter.paragraphRanges(document.text)

    /** How many unit windows the segments group into (0 when there are no segments). */
    private val windowCount: Int =
        // Ceiling division without the `(size + windowSize - 1)` overflow footgun for a
        // very large injected windowSize (segmentSpans is non-empty here).
        if (segmentSpans.isEmpty()) 0
        else ((segmentSpans.size - 1) / this.windowSize) + 1

    override fun units(): List<TranslationUnitId> =
        (0 until windowCount).map { unitFor(it) }

    override fun sourceSegments(unit: TranslationUnitId): List<String> =
        spansForWindow(windowIndexOf(unit)).map { document.text.substring(it.start, it.endExclusive) }

    override fun sourceText(unit: TranslationUnitId): String =
        sourceSegments(unit).joinToString("\n\n")

    override fun unitContaining(charOffsetUtf16: Int): TranslationUnitId? {
        if (segmentSpans.isEmpty()) return null
        val segmentIndex = segmentIndexContaining(charOffsetUtf16)
        return unitFor(segmentIndex / windowSize)
    }

    override fun unitAfter(unit: TranslationUnitId): TranslationUnitId? {
        val next = windowIndexOf(unit) + 1
        return if (next < windowCount) unitFor(next) else null
    }

    // ── internals ─────────────────────────────────────────────

    private fun unitFor(windowIndex: Int): TranslationUnitId =
        TranslationUnitId(kind, windowIndex.toString())

    /** Parses a unit's window index; a foreign/malformed unit resolves to window 0. */
    private fun windowIndexOf(unit: TranslationUnitId): Int =
        unit.value.toIntOrNull()?.coerceIn(0, maxOf(0, windowCount - 1)) ?: 0

    /** The segment spans owned by [windowIndex] (a contiguous [windowSize]-slice). */
    private fun spansForWindow(windowIndex: Int): List<Utf16Span> {
        if (segmentSpans.isEmpty()) return emptyList()
        val start = windowIndex * windowSize
        if (start >= segmentSpans.size) return emptyList()
        val end = minOf(start + windowSize, segmentSpans.size)
        return segmentSpans.subList(start, end)
    }

    /**
     * The index of the segment whose half-open span contains [offset], or — when the
     * offset falls in a between-segment gap or past EOF — the last segment that STARTS
     * at or before it (EOF-clamped to the final segment; an offset before the first
     * segment resolves to segment 0). Binary search over segment START offsets, the
     * same shape as [TxtDocument.chunkForOffset], so it never clamp-collapses on the
     * final segment.
     */
    private fun segmentIndexContaining(offset: Int): Int {
        val clamped = offset.coerceIn(0, document.text.length)
        // Largest segment whose start <= clamped.
        var lo = 0
        var hi = segmentSpans.size - 1
        var ans = 0
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            if (segmentSpans[mid].start <= clamped) {
                ans = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return ans
    }

    companion object {
        /**
         * Segments per unit window — a translation batch. Bounds cache rows + the
         * per-prefetch provider request without changing the 1:1 segment↔translation
         * contract (a window is just a contiguous slice of the same span array).
         */
        const val DEFAULT_WINDOW_SIZE = 8
    }
}
