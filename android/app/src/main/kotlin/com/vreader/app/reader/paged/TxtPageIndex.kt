// Purpose: feature #137 WI-4 (#110 Phase 3, box E) — the immutable page-boundary index for the
// paged TXT/MD renderer. Holds ONLY the page-start source-UTF-16 offsets (one int per page —
// thousands of ints = KB, not MB; the ONE full-book structure phase-1 pagination retains) plus the
// document end. It is source-UTF-16-anchored and layout-independent, so a saved charOffsetUTF16
// resume position maps to a page via `pageContaining` regardless of font/rotation reflow.
//
// A `degenerate()` instance is the signal phase-1 returns when the content box has no usable area
// (≤0 width/height before layout settles) — the host degrades to scroll rendering rather than
// looping/crashing (Gate-2 R3 Critical). It is distinct from an EMPTY doc (chunkCount 0 → 0 pages,
// NOT degenerate).
//
// @coordinates-with: TxtPaginator.kt (phase-1 builds it; phase-2 renderPage reads pageStart/End),
//   TxtPageNavigator.kt (WI-5 — offset↔page + reflow reconciliation).
package com.vreader.app.reader.paged

/**
 * An immutable page-boundary index. [pageStartsUtf16] holds each page's START source-UTF-16 offset
 * (strictly increasing, `[0]` == the document start); [docEndExclusive] is the source-UTF-16 length
 * of the document (the last page's exclusive end).
 */
class TxtPageIndex(
    pageStartsUtf16: IntArray,
    val docEndExclusive: Int,
    /** True ONLY for the degenerate-content-box signal — NOT for an empty document. */
    val isDegenerate: Boolean = false,
) {
    // Defensive copy so the immutable index cannot be mutated through the caller's array (Gate-4 Low-1);
    // reads go through pageStart/pageEndExclusive/pageContaining, never the raw backing store.
    private val starts: IntArray = pageStartsUtf16.copyOf()

    /** A DEFENSIVE COPY of the page-start offsets (never the backing store) for consumers that need it. */
    val pageStartsUtf16: IntArray get() = starts.copyOf()

    /** Number of pages (0 for an empty document or the degenerate signal). */
    val pageCount: Int get() = starts.size

    /** True when there are no pages (empty document, or the degenerate signal). */
    val isEmpty: Boolean get() = starts.isEmpty()

    /** The source-UTF-16 start offset of [page] (page arg clamped to a valid page; 0 if empty). */
    fun pageStart(page: Int): Int {
        if (starts.isEmpty()) return 0
        return starts[page.coerceIn(0, starts.size - 1)]
    }

    /** The exclusive source-UTF-16 end of [page] = the next page's start, or [docEndExclusive]. */
    fun pageEndExclusive(page: Int): Int {
        if (starts.isEmpty()) return docEndExclusive
        val p = page.coerceIn(0, starts.size - 1)
        return if (p + 1 < starts.size) starts[p + 1] else docEndExclusive
    }

    /**
     * The page whose `[pageStart, pageEndExclusive)` contains [sourceOffsetUtf16] — the largest page
     * whose start is `<= offset` (binary search). Clamps: a negative offset → page 0; an offset at/past
     * [docEndExclusive] → the last page. Returns 0 for an empty index (never throws).
     */
    fun pageContaining(sourceOffsetUtf16: Int): Int {
        if (starts.isEmpty()) return 0
        val offset = sourceOffsetUtf16.coerceIn(0, docEndExclusive)
        var lo = 0; var hi = starts.size - 1; var ans = 0
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            if (starts[mid] <= offset) { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }

    companion object {
        /** The degrade-to-scroll signal for a content box with no usable area. Zero pages. */
        fun degenerate(): TxtPageIndex = TxtPageIndex(IntArray(0), docEndExclusive = 0, isDegenerate = true)
    }
}
