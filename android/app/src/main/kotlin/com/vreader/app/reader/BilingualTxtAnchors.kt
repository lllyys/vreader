// Purpose: feature #131 WI-8 — the pure TXT/MD interlinear ANCHOR map. Given a decoded
// TxtDocument and the addressing Kind, it computes — ONCE — which translation unit window
// (the same document-global segment window TxtChapterTextProvider addresses) is anchored to
// each source chunk, so the host's `items(count = chunkCount, key = { it })` loop can render
// a unit's ONE translation inside its LAST chunk's wrapping Column (round-4 H2 render
// contract). A paragraph (segment) spanning chunks j..i anchors to chunk i =
// chunkForOffset(span.endExclusive - 1); a unit window anchors to the LAST segment of the
// window's anchor chunk. Two paragraphs ending in the same chunk yield a LIST for that chunk
// (segment order preserved), so nothing is dropped (round-3 H1 / round-4 Low-2).
//
// This mirrors TxtChapterTextProvider's windowing (ChapterSegmenter.paragraphRanges +
// DEFAULT_WINDOW_SIZE) EXACTLY so the render anchor for a window == the unit the provider's
// unitContaining/unitAfter resolves for that window — the two segment identically by
// construction (a connected test asserts this parity against the provider). Pure/JVM.
//
// @coordinates-with: com.vreader.app.bilingual.TxtChapterTextProvider,
//   com.vreader.app.bilingual.ChapterSegmenter, com.vreader.app.bilingual.TranslationUnitId,
//   reader/TxtReaderActivity.kt (WI-8),
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-8 §2 H2)
package com.vreader.app.reader

import com.vreader.app.bilingual.ChapterSegmenter
import com.vreader.app.bilingual.TranslationUnitId
import com.vreader.app.bilingual.TxtChapterTextProvider

/**
 * Precomputes the source-chunk → translation-unit(s) anchor map for a decoded [document].
 * [kind] must be [TranslationUnitId.Kind.txtDocSegmentWindow] (`.txt`) or
 * [TranslationUnitId.Kind.mdDocSegmentWindow] (`.md`) — the same kinds
 * [TxtChapterTextProvider] addresses; [windowSize] must match the provider's window size so
 * the render anchors line up with the unit the provider resolves.
 */
class BilingualTxtAnchors(
    private val document: TxtDocument,
    private val kind: TranslationUnitId.Kind,
    windowSize: Int = TxtChapterTextProvider.DEFAULT_WINDOW_SIZE,
) {
    init {
        require(
            kind == TranslationUnitId.Kind.txtDocSegmentWindow ||
                kind == TranslationUnitId.Kind.mdDocSegmentWindow,
        ) { "BilingualTxtAnchors only addresses txt/md segment-window kinds, got $kind" }
    }

    private val effectiveWindow = maxOf(1, windowSize)

    /**
     * anchor chunk index → the unit(s) whose paragraph ENDS in that chunk (segment order). LAZY: the
     * whole-document paragraph scan runs on FIRST access (only while bilingual is enabled + rendering),
     * NOT on reader open — so a disabled TXT/MD reader (or any non-bilingual open) pays nothing for
     * segmentation (round-4 audit High-3). Computed once, then memoized.
     */
    private val byChunk: Map<Int, List<TranslationUnitId>> by lazy(LazyThreadSafetyMode.NONE) {
        val spans = ChapterSegmenter.paragraphRanges(document.text)
        val out = LinkedHashMap<Int, MutableList<TranslationUnitId>>()
        if (spans.isNotEmpty()) {
            // The window count matches the provider's ceiling division exactly.
            val windowCount = ((spans.size - 1) / effectiveWindow) + 1
            for (w in 0 until windowCount) {
                val lastSegIndex = minOf((w + 1) * effectiveWindow, spans.size) - 1
                val span = spans[lastSegIndex]
                // Anchor to the chunk containing the window's LAST paragraph's last code unit.
                // A zero-length trailing span (endExclusive == start) still anchors sensibly:
                // its start clamps into the document, so no anchor is dropped (round-3 H1).
                val anchorOffset = (span.endExclusive - 1).coerceAtLeast(span.start)
                val chunk = document.chunkForOffset(anchorOffset)
                out.getOrPut(chunk) { mutableListOf() }.add(TranslationUnitId(kind, w.toString()))
            }
        }
        out
    }

    /** The translation unit(s) anchored to source chunk [chunkIndex], in segment order (empty
     *  when no paragraph ends in this chunk). Forces the lazy scan on first call. */
    fun unitsForChunk(chunkIndex: Int): List<TranslationUnitId> = byChunk[chunkIndex] ?: emptyList()

    /** All (chunk → units) anchor entries — for parity assertions against the provider. */
    fun anchorEntries(): Map<Int, List<TranslationUnitId>> = byChunk
}
