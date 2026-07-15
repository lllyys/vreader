// Purpose: feature #137 WI-4 (#110 Phase 3, box E) — the immutable page-boundary index for the
// paged TXT/MD renderer. Holds ONLY the page-start source-UTF-16 offsets (one int per page —
// thousands of ints = KB, not MB; the ONE full-book structure phase-1 pagination retains) plus the
// document end. It is source-UTF-16-anchored and layout-independent, so a saved charOffsetUTF16
// resume position maps to a page via `pageContaining` regardless of font/rotation reflow.
//
// Feature #138 WI-2 adds SEALED-PARTIAL support: a windowed pass (PaginationSession) can publish a
// PARTIAL index — the pages SEALED so far — before the whole book is measured, and republish a NEW
// immutable index as the sealed frontier advances (exactly as a reflow republishes today). The type
// stays a PURE, IMMUTABLE data structure: it holds NO measuring logic. `isComplete=false` +
// `frontierSourceOffset` (the source offset up to which pages are sealed — a FRONTIER MARKER, NOT a
// page start; not in `pageStartsUtf16`) mark a partial index. The subtle correctness point (Gate-2
// R1 High 3 / R2 Medium 1): a page is SEALED only once its exclusive end is FINAL — for every page
// but the last that means the NEXT page's start is known (a +1-page lookahead), so a partial index
// publishes SEALED pages ONLY and `pageEndExclusive(lastSealedPage)` == the frontier (the
// known-but-unpublished next sealed start). The FINAL page is sealed by DOC END, so a COMPLETE
// index's frontier == `docEndExclusive` and its last page ends at `docEndExclusive` (unchanged
// behavior). For a beyond-frontier offset `pageContaining` keeps the clamp as a FALLBACK; the
// SESSION must `ensureMeasuredThrough(offset)` (WI-4) BEFORE querying beyond the frontier — this
// data structure never measures.
//
// A `degenerate()` instance is the signal phase-1 returns when the content box has no usable area
// (≤0 width/height before layout settles) — the host degrades to scroll rendering rather than
// looping/crashing (Gate-2 R3 Critical). It is distinct from an EMPTY doc (chunkCount 0 → 0 pages,
// NOT degenerate).
//
// @coordinates-with: TxtPaginator.kt (phase-1 builds it; phase-2 renderPage reads pageStart/End),
//   TxtPageNavigator.kt (WI-5 — offset↔page + reflow reconciliation),
//   PaginationSession.kt (WI-4 — publishes partial snapshots; owns ensureMeasuredThrough).
package com.vreader.app.reader.paged

/**
 * An immutable page-boundary index. [pageStartsUtf16] holds each page's START source-UTF-16 offset
 * (strictly increasing, `[0]` == the document start); [docEndExclusive] is the source-UTF-16 length
 * of the document.
 *
 * When [isComplete] is true (the default — every whole-book construction) the index covers the whole
 * document and the last page ends at [docEndExclusive]. A PARTIAL index ([isComplete] = false) holds
 * only the pages SEALED so far; [frontierSourceOffset] is the source offset up to which pages are
 * sealed — a FRONTIER MARKER, NOT a page start (it is not in [pageStartsUtf16]) — and the last
 * published page's exclusive end is that frontier (the next sealed page's start). For a complete
 * index [frontierSourceOffset] == [docEndExclusive].
 */
class TxtPageIndex(
    pageStartsUtf16: IntArray,
    val docEndExclusive: Int,
    /** True ONLY for the degenerate-content-box signal — NOT for an empty document. */
    val isDegenerate: Boolean = false,
    /**
     * True when this index covers the WHOLE document (every whole-book construction — the default,
     * so existing call sites are unchanged/complete). False for a windowed PARTIAL index that has
     * sealed only some leading pages.
     */
    val isComplete: Boolean = true,
    /**
     * The source offset up to which pages are SEALED — a FRONTIER MARKER, not a page start. For a
     * PARTIAL index it is the next (known-but-unpublished) sealed page's start, i.e. the exclusive
     * end of the last published page. Defaults (via an [Int.MIN_VALUE] sentinel) to
     * [docEndExclusive], so every existing/complete construction reports a frontier at doc end with
     * no call-site change. Measuring lives in the SESSION, never here.
     */
    frontierSourceOffset: Int = Int.MIN_VALUE,
) {
    /**
     * The frontier marker (see the ctor param). Resolves the [Int.MIN_VALUE] sentinel to
     * [docEndExclusive] so a complete/existing construction's frontier is doc end by default.
     */
    val frontierSourceOffset: Int =
        if (frontierSourceOffset == Int.MIN_VALUE) docEndExclusive else frontierSourceOffset

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

    /**
     * The exclusive source-UTF-16 end of [page] = the next page's start; for the LAST published page
     * it is [frontierSourceOffset] (the next sealed page's start for a PARTIAL index; == [docEndExclusive]
     * for a COMPLETE index, so complete-index behavior is unchanged). Interior pages are unaffected.
     */
    fun pageEndExclusive(page: Int): Int {
        if (starts.isEmpty()) return frontierSourceOffset
        val p = page.coerceIn(0, starts.size - 1)
        return if (p + 1 < starts.size) starts[p + 1] else frontierSourceOffset
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
