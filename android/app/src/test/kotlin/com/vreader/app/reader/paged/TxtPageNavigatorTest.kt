package com.vreader.app.reader.paged

import androidx.compose.ui.text.TextStyle
import com.vreader.app.reader.TxtDocument
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #137 WI-5 — [TxtPageNavigator]: offset↔page state + reflow count-change reconciliation.
 *
 * The navigator sits between [TxtPaginator]/[TxtPageIndex] and the (WI-6a) HorizontalPager. It holds
 * the current immutable index + the current page as PLAIN state (no Compose), so the offset↔page
 * convenience and the reflow-reconciliation logic are fully JVM-testable.
 *
 * Reflow: on a settings/rotation change [TxtPageNavigator.reconcileAfterReflow] (1) captures the
 * current source offset, (2) awaits a NEW immutable index via [TxtPaginator.index] (cancellable via
 * a monotonic generation token — a superseded reflow never publishes), (3) clamps the pager to
 * `newIndex.pageContaining(capturedOffset)`. Tests inject a deterministic fake measurer + a test
 * dispatcher (StandardTestDispatcher / UnconfinedTestDispatcher, NO Turbine).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TxtPageNavigatorTest {

    private val style = TextStyle()

    /** Fixed-width line breaker (mirrors WI-4's FixedLineMeasurer). */
    private class FixedLineMeasurer(
        private val charsPerLine: Int,
        private val lineHeightPx: Float = 10f,
    ) : LineMeasurer {
        override fun measure(text: CharSequence, style: TextStyle, maxWidthPx: Float): List<LineMetric> {
            if (text.isEmpty()) return listOf(LineMetric(0, 0, lineHeightPx))
            val lines = ArrayList<LineMetric>()
            var start = 0
            val n = text.length
            while (start < n) {
                var end = (start + charsPerLine).coerceAtMost(n)
                if (end < n && Character.isHighSurrogate(text[end - 1]) && Character.isLowSurrogate(text[end])) end++
                lines.add(LineMetric(start, end, lineHeightPx))
                start = end
            }
            return lines
        }
    }

    private val big = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)

    private fun box(heightPx: Float, widthPx: Float = 1000f) = PageContentBox(widthPx, heightPx)

    /** 6 one-line chunks "line0\n".."line5\n" — doc offsets 0,6,12,18,24,30 (each "lineN\n" = 6 chars). */
    private fun sixLineDoc() = TxtDocument.of((0 until 6).joinToString("") { "line$it\n" })

    // --- offset↔page convenience over the current index ----------------------------------------

    @Test fun currentPage_defaultsToZero_beforeAnyIndex() {
        val nav = TxtPageNavigator(TxtPaginator(UnconfinedTestDispatcher()))
        assertEquals(0, nav.currentPage)
        assertNull(nav.index)
    }

    @Test fun offsetToPage_roundTrips_overCurrentIndex() {
        val nav = TxtPageNavigator(TxtPaginator(UnconfinedTestDispatcher()))
        nav.setIndex(TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120))
        // offset → page
        assertEquals(0, nav.pageContaining(10))
        assertEquals(1, nav.pageContaining(40))
        assertEquals(2, nav.pageContaining(95))
        // page → start offset
        assertEquals(0, nav.pageStart(0))
        assertEquals(40, nav.pageStart(1))
        assertEquals(90, nav.pageStart(2))
    }

    @Test fun currentSourceOffset_isCurrentPageStart() {
        val nav = TxtPageNavigator(TxtPaginator(UnconfinedTestDispatcher()))
        nav.setIndex(TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120))
        nav.onPagerPageChanged(2)
        assertEquals(2, nav.currentPage)
        assertEquals(90, nav.currentSourceOffset())
    }

    @Test fun jumpToOffset_setsCurrentPageAndScrollTarget() {
        val nav = TxtPageNavigator(TxtPaginator(UnconfinedTestDispatcher()))
        nav.setIndex(TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120))
        nav.jumpToOffset(85)   // in page 1 [40,90)
        assertEquals(1, nav.currentPage)
        assertEquals(1, nav.pendingScrollTarget)
    }

    // --- reflow count-change reconciliation: count GREW ----------------------------------------

    @Test fun reflow_countGrew_clampsToPageContainingCapturedOffset() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val doc = sixLineDoc()
        val nav = TxtPageNavigator(TxtPaginator(dispatcher))
        // bootstrap: box holds 3 lines/page → 2 pages (0..2, 3..5).
        nav.reconcileAfterReflow(doc, style, box(30f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()
        assertEquals(2, nav.index!!.pageCount)
        // land on page 1 (source offset 18).
        nav.onPagerPageChanged(1)
        val capturedOffset = nav.currentSourceOffset()
        assertEquals(18, capturedOffset)

        // reflow: SHRINK box to 1 line/page → 6 pages (count GREW from 2 → 6).
        nav.reconcileAfterReflow(doc, style, box(10f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()

        assertEquals(6, nav.index!!.pageCount)
        // captured source offset 18 → page 3 in the new 1-line-per-page index.
        assertEquals(3, nav.index!!.pageContaining(18))
        assertEquals(3, nav.currentPage)
        assertEquals(3, nav.pendingScrollTarget)
    }

    // --- reflow count-change reconciliation: count SHRANK ---------------------------------------

    @Test fun reflow_countShrank_clampsToPageContainingCapturedOffset() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val doc = sixLineDoc()
        val nav = TxtPageNavigator(TxtPaginator(dispatcher))
        // bootstrap: 1 line/page → 6 pages.
        nav.reconcileAfterReflow(doc, style, box(10f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()
        assertEquals(6, nav.index!!.pageCount)
        // land on page 4 (source offset 24).
        nav.onPagerPageChanged(4)
        assertEquals(24, nav.currentSourceOffset())

        // reflow: GROW box to 3 lines/page → 2 pages (count SHRANK from 6 → 2).
        nav.reconcileAfterReflow(doc, style, box(30f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()

        assertEquals(2, nav.index!!.pageCount)
        // captured source offset 24 → page 1 in the new 3-lines-per-page index (page 1 = [18,36)).
        assertEquals(1, nav.index!!.pageContaining(24))
        assertEquals(1, nav.currentPage)
    }

    // --- a superseded reflow (stale generation) does NOT publish --------------------------------

    @Test fun supersededReflow_staleGeneration_doesNotPublish() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val doc = sixLineDoc()
        val nav = TxtPageNavigator(TxtPaginator(dispatcher))
        nav.reconcileAfterReflow(doc, style, box(30f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()
        nav.onPagerPageChanged(1)

        // Reflow A → target 6-page index; Reflow B (superseding, launched before A runs) → 2-page index.
        // With StandardTestDispatcher both are queued; B supersedes A so only B publishes.
        nav.reconcileAfterReflow(doc, style, box(10f), big, isMarkdown = false, scope = this)   // A: 6 pages
        nav.reconcileAfterReflow(doc, style, box(30f), big, isMarkdown = false, scope = this)   // B: 2 pages
        advanceUntilIdle()

        // Only B publishes: the final index is the 2-page one, NOT A's 6-page one.
        assertEquals(2, nav.index!!.pageCount)
    }

    @Test fun supersededReflow_tokenIsCancelled_forTheOlderPass() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val doc = sixLineDoc()
        val nav = TxtPageNavigator(TxtPaginator(dispatcher))
        nav.reconcileAfterReflow(doc, style, box(30f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()

        nav.reconcileAfterReflow(doc, style, box(10f), big, isMarkdown = false, scope = this)
        val firstToken = nav.activeToken
        nav.reconcileAfterReflow(doc, style, box(30f), big, isMarkdown = false, scope = this)
        // starting the second reflow must cancel the first's token.
        assertTrue("older reflow token must be cancelled", firstToken!!.isCancelled)
        assertNotEquals(firstToken, nav.activeToken)
        advanceUntilIdle()
    }

    // --- degenerate / empty new index handled (degrade signal, no crash) ------------------------

    @Test fun reflow_degenerateNewIndex_degradesSafely_noCrashNoBadPage() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val doc = sixLineDoc()
        val nav = TxtPageNavigator(TxtPaginator(dispatcher))
        nav.reconcileAfterReflow(doc, style, box(30f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()
        nav.onPagerPageChanged(1)

        // reflow with a DEGENERATE box (0 height) → paginator returns the degrade signal.
        nav.reconcileAfterReflow(doc, style, box(0f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()

        assertTrue("navigator surfaces the degrade signal", nav.isDegenerate)
        assertTrue(nav.index!!.isDegenerate)
        // no crash; current page clamps to 0 for a zero-page index (pageContaining returns 0).
        assertEquals(0, nav.currentPage)
    }

    @Test fun reflow_emptyDoc_zeroPages_currentPageZero() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val doc = TxtDocument.of("")
        val nav = TxtPageNavigator(TxtPaginator(dispatcher))
        // empty doc → 0 pages, not degenerate.
        nav.reconcileAfterReflow(doc, style, box(30f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()
        assertEquals(0, nav.index!!.pageCount)
        assertFalse("empty doc is not the degenerate signal", nav.isDegenerate)
        assertEquals(0, nav.currentPage)
    }

    // --- boundary pages: first & last clamp correctly on reflow ---------------------------------

    @Test fun reflow_fromFirstPage_staysOnFirstPage() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val doc = sixLineDoc()
        val nav = TxtPageNavigator(TxtPaginator(dispatcher))
        nav.reconcileAfterReflow(doc, style, box(30f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()
        nav.onPagerPageChanged(0)   // first page, source offset 0
        nav.reconcileAfterReflow(doc, style, box(10f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()
        assertEquals(0, nav.currentPage)   // source offset 0 → page 0 in any index
    }

    @Test fun reflow_fromLastPage_landsOnLastPageOfNewIndex() = runTest {
        val dispatcher = StandardTestDispatcher(testScheduler)
        val doc = sixLineDoc()
        val nav = TxtPageNavigator(TxtPaginator(dispatcher))
        // 1 line/page → 6 pages.
        nav.reconcileAfterReflow(doc, style, box(10f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()
        nav.onPagerPageChanged(5)
        assertEquals(30, nav.currentSourceOffset())
        // reflow to 3 lines/page → 2 pages; source 30 is in page 1 [18,36).
        nav.reconcileAfterReflow(doc, style, box(30f), big, isMarkdown = false, scope = this)
        advanceUntilIdle()
        assertEquals(2, nav.index!!.pageCount)
        assertEquals(1, nav.currentPage)   // last page of the new index
    }

    // --- pager seam: consumePendingScrollTarget clears after read -------------------------------

    @Test fun pendingScrollTarget_isConsumedOnce() {
        val nav = TxtPageNavigator(TxtPaginator(UnconfinedTestDispatcher()))
        nav.setIndex(TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120))
        nav.jumpToOffset(85)
        assertEquals(1, nav.consumePendingScrollTarget())
        assertNull("target cleared after consumption", nav.consumePendingScrollTarget())
    }

    @Test fun onPagerPageChanged_updatesCurrentPage_doesNotSetScrollTarget() {
        val nav = TxtPageNavigator(TxtPaginator(UnconfinedTestDispatcher()))
        nav.setIndex(TxtPageIndex(intArrayOf(0, 40, 90), docEndExclusive = 120))
        nav.onPagerPageChanged(2)
        assertEquals(2, nav.currentPage)
        // a user swipe (pager-driven) must NOT re-issue a scroll target (would fight the pager).
        assertNull(nav.consumePendingScrollTarget())
    }
}
