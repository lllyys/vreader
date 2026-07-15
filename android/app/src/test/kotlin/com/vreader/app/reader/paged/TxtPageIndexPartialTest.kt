package com.vreader.app.reader.paged

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #138 WI-2 — [TxtPageIndex] sealed-partial support. A windowed pass publishes a NEW
 * immutable PARTIAL index each republish (exactly as a reflow does): [TxtPageIndex.isComplete]
 * = false and [TxtPageIndex.frontierSourceOffset] is the FRONTIER MARKER (the source offset up
 * to which pages are SEALED — NOT a page start; == `docEndExclusive` when complete). For a
 * partial index the LAST published page's exclusive end is the frontier (the next sealed page's
 * start); for a complete index the last page ends at `docEndExclusive` (unchanged). Page 0 is
 * always document start (doc-start-forward pagination), so `pageContaining(0) == 0` always holds.
 */
class TxtPageIndexPartialTest {

    // --- isComplete defaults to true for EVERY existing construction (no regression) ---

    @Test fun isComplete_defaultsTrue_forStandardCtor() {
        val idx = TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120)
        assertTrue(idx.isComplete)
    }

    @Test fun isComplete_defaultsTrue_forEmptyDoc() {
        val idx = TxtPageIndex(IntArray(0), docEndExclusive = 0)
        assertTrue(idx.isComplete)
    }

    @Test fun isComplete_defaultsTrue_forSinglePageDoc() {
        val idx = TxtPageIndex(intArrayOf(0), docEndExclusive = 50)
        assertTrue(idx.isComplete)
    }

    @Test fun degenerate_isComplete() {
        val idx = TxtPageIndex.degenerate()
        assertTrue(idx.isComplete)
        assertTrue(idx.isDegenerate)
    }

    // --- frontierSourceOffset == docEndExclusive for a COMPLETE index (default) ---

    @Test fun frontier_equalsDocEnd_whenComplete() {
        val idx = TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120)
        assertEquals(120, idx.frontierSourceOffset)
    }

    @Test fun frontier_equalsDocEnd_forSinglePageDoc() {
        val idx = TxtPageIndex(intArrayOf(0), docEndExclusive = 50)
        assertEquals(50, idx.frontierSourceOffset)
    }

    @Test fun frontier_equalsDocEnd_forDegenerate() {
        val idx = TxtPageIndex.degenerate()
        assertEquals(0, idx.frontierSourceOffset)
    }

    // --- a PARTIAL index: isComplete=false + a frontier that is NOT a page start ---

    @Test fun partialIndex_reportsNotComplete() {
        // Sealed pages start at 0, 40, 90; the cursor has measured up to 130 (the next sealed
        // page's start, not yet published) — 130 is the frontier, NOT in pageStartsUtf16.
        val idx = TxtPageIndex(
            intArrayOf(0, 40, 90),
            docEndExclusive = 500,
            isComplete = false,
            frontierSourceOffset = 130,
        )
        assertFalse(idx.isComplete)
        assertEquals(130, idx.frontierSourceOffset)
    }

    @Test fun partialIndex_frontier_isNotAPageStart() {
        val starts = intArrayOf(0, 40, 90)
        val idx = TxtPageIndex(
            starts, docEndExclusive = 500, isComplete = false, frontierSourceOffset = 130,
        )
        assertFalse(idx.pageStartsUtf16.contains(idx.frontierSourceOffset))
    }

    // --- pageEndExclusive(lastPage): PARTIAL -> frontier; COMPLETE -> docEndExclusive ---

    @Test fun pageEndExclusive_lastPage_partial_returnsFrontier() {
        val idx = TxtPageIndex(
            intArrayOf(0, 40, 90),
            docEndExclusive = 500,
            isComplete = false,
            frontierSourceOffset = 130,
        )
        // The last SEALED page (index 2) ends at the next sealed page's start = the frontier (130),
        // NOT at docEndExclusive (500).
        assertEquals(130, idx.pageEndExclusive(2))
    }

    @Test fun pageEndExclusive_lastPage_complete_returnsDocEnd_unchanged() {
        val idx = TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120)
        assertEquals(120, idx.pageEndExclusive(2))
    }

    @Test fun pageEndExclusive_interiorPages_unaffectedByPartial() {
        // Interior pages' ends are the next START in either case — only the LAST page differs.
        val partial = TxtPageIndex(
            intArrayOf(0, 40, 90), docEndExclusive = 500, isComplete = false, frontierSourceOffset = 130,
        )
        assertEquals(40, partial.pageEndExclusive(0))
        assertEquals(90, partial.pageEndExclusive(1))
    }

    // --- the FINAL page sealed at doc end (a complete index's frontier == docEndExclusive) ---

    @Test fun finalPage_sealedAtDocEnd_frontierEqualsDocEnd() {
        val complete = TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120)
        assertEquals(complete.docEndExclusive, complete.frontierSourceOffset)
        assertEquals(complete.docEndExclusive, complete.pageEndExclusive(complete.pageCount - 1))
    }

    // --- pageContaining within the sealed region is exact; beyond-frontier clamps (fallback) ---

    @Test fun pageContaining_withinSealedRegion_isExact() {
        val idx = TxtPageIndex(
            intArrayOf(0, 40, 90), docEndExclusive = 500, isComplete = false, frontierSourceOffset = 130,
        )
        assertEquals(0, idx.pageContaining(0))
        assertEquals(0, idx.pageContaining(39))
        assertEquals(1, idx.pageContaining(40))
        assertEquals(2, idx.pageContaining(90))
        assertEquals(2, idx.pageContaining(129))  // still within the last sealed page
    }

    @Test fun pageContaining_beyondFrontier_clampsToLastSealedPage_fallback() {
        // The session is responsible for ensureMeasuredThrough(offset) BEFORE querying beyond the
        // frontier; absent that, pageContaining clamps to the last SEALED page (the documented
        // fallback). 300 is beyond the frontier (130) but within docEndExclusive (500).
        val idx = TxtPageIndex(
            intArrayOf(0, 40, 90), docEndExclusive = 500, isComplete = false, frontierSourceOffset = 130,
        )
        assertEquals(2, idx.pageContaining(300))
        assertEquals(2, idx.pageContaining(500))
        assertEquals(2, idx.pageContaining(9999))
    }

    // --- pageContaining(0) == 0 for any non-degenerate index (partial or complete) ---

    @Test fun pageContaining_zero_isPageZero_forPartial() {
        val idx = TxtPageIndex(
            intArrayOf(0, 40, 90), docEndExclusive = 500, isComplete = false, frontierSourceOffset = 130,
        )
        assertEquals(0, idx.pageContaining(0))
    }

    @Test fun pageContaining_zero_isPageZero_forComplete() {
        val idx = TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120)
        assertEquals(0, idx.pageContaining(0))
    }

    // --- immutability: mutating the caller's array does not change the index (still holds) ---

    @Test fun partialIndex_isImmutable_defensiveCopyOfStarts() {
        val starts = intArrayOf(0, 40, 90)
        val idx = TxtPageIndex(
            starts, docEndExclusive = 500, isComplete = false, frontierSourceOffset = 130,
        )
        starts[1] = 999
        assertEquals(40, idx.pageStart(1))
    }

    // --- a single-page partial doc: sealed at doc end -> complete, frontier == docEnd ---

    @Test fun onePageDoc_sealedAtDocEnd_isCompleteEquivalent() {
        // A one-page doc seals at DOC END (no next start), so it publishes complete immediately.
        val idx = TxtPageIndex(intArrayOf(0), docEndExclusive = 50)
        assertTrue(idx.isComplete)
        assertEquals(50, idx.frontierSourceOffset)
        assertEquals(50, idx.pageEndExclusive(0))
    }

    // --- Gate-4 invariant: a COMPLETE index's frontier is ALWAYS docEndExclusive, even if a caller
    //     contradictorily passes an explicit frontier — complete-index behavior can never change ---

    @Test fun completeIndex_ignoresExplicitFrontier_frontierIsDocEnd() {
        // Contradictory construction: isComplete=true but an explicit frontier != docEnd. The
        // complete-index invariant wins — frontier resolves to docEndExclusive.
        val idx = TxtPageIndex(
            intArrayOf(0, 40),
            docEndExclusive = 100,
            isComplete = true,
            frontierSourceOffset = 70,
        )
        assertEquals(100, idx.frontierSourceOffset)
    }

    @Test fun completeIndex_ignoresExplicitFrontier_lastPageEndsAtDocEnd() {
        val idx = TxtPageIndex(
            intArrayOf(0, 40),
            docEndExclusive = 100,
            isComplete = true,
            frontierSourceOffset = 70,
        )
        // Last page still ends at docEnd (100), NOT the bogus 70 — no complete-index behavior change.
        assertEquals(100, idx.pageEndExclusive(1))
    }
}
