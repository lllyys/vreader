package com.vreader.app.reader.paged

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Feature #137 WI-4 — [TxtPageIndex]: the immutable boundary index. Holds ONLY the page-start
 * source-UTF-16 offsets (KB, not MB — the one full-book structure) + the document end.
 * `pageContaining` binary-searches; `pageStart`/`pageEndExclusive` bound each page.
 */
class TxtPageIndexTest {

    @Test fun pageCount_matchesStartsLength() {
        val idx = TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120)
        assertEquals(3, idx.pageCount)
    }

    @Test fun pageStart_returnsBoundaryOffset() {
        val idx = TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120)
        assertEquals(0, idx.pageStart(0))
        assertEquals(40, idx.pageStart(1))
        assertEquals(90, idx.pageStart(2))
    }

    @Test fun pageEndExclusive_isNextStart_orDocEnd() {
        val idx = TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120)
        assertEquals(40, idx.pageEndExclusive(0))
        assertEquals(90, idx.pageEndExclusive(1))
        assertEquals(120, idx.pageEndExclusive(2))   // last page → doc end
    }

    @Test fun pageContaining_binarySearch_landsInRightPage() {
        val idx = TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120)
        assertEquals(0, idx.pageContaining(0))
        assertEquals(0, idx.pageContaining(39))
        assertEquals(1, idx.pageContaining(40))     // exactly on a boundary → that page
        assertEquals(1, idx.pageContaining(89))
        assertEquals(2, idx.pageContaining(90))
        assertEquals(2, idx.pageContaining(119))
    }

    @Test fun pageContaining_pastDocEnd_clampsToLastPage() {
        val idx = TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120)
        assertEquals(2, idx.pageContaining(500))
        assertEquals(2, idx.pageContaining(120))
    }

    @Test fun pageContaining_negative_clampsToFirstPage() {
        val idx = TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120)
        assertEquals(0, idx.pageContaining(-10))
    }

    @Test fun singlePage_doc() {
        val idx = TxtPageIndex(intArrayOf(0), docEndExclusive = 50)
        assertEquals(1, idx.pageCount)
        assertEquals(0, idx.pageStart(0))
        assertEquals(50, idx.pageEndExclusive(0))
        assertEquals(0, idx.pageContaining(25))
        assertEquals(0, idx.pageContaining(50))
    }

    @Test fun emptyDoc_zeroPages() {
        val idx = TxtPageIndex(IntArray(0), docEndExclusive = 0)
        assertEquals(0, idx.pageCount)
        assertEquals(true, idx.isEmpty)
        // a query on an empty index never throws.
        assertEquals(0, idx.pageContaining(0))
    }

    @Test fun clampedPageArgs_neverThrow() {
        val idx = TxtPageIndex(intArrayOf(0, 40), docEndExclusive = 80)
        assertEquals(0, idx.pageStart(-5))
        assertEquals(40, idx.pageStart(99))
        assertEquals(80, idx.pageEndExclusive(99))
    }
}
