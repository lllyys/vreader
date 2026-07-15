package com.vreader.app.reader.paged

import androidx.compose.ui.text.TextStyle
import com.vreader.app.reader.TxtDocument
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.Test

/**
 * Feature #138 WI-4 — [TxtPageNavigator] DELEGATES its pagination LIFECYCLE to [PaginationSession].
 *
 * The navigator stays the Compose-free pager-position seam (offset↔page, currentPage/pendingScrollTarget),
 * but the SESSION now owns the cursor + sealed list + token/generation + publication. This suite proves:
 *   • a first-window publish sets a PARTIAL index + currentPage == pageContaining(captured);
 *   • a background append does NOT move currentPage (append-only, doc-start numbering);
 *   • async jumpToOffset(beyondFrontier, session) extends-then-resolves to the exact page (EVENTUAL);
 *   • reflow mid-background delegates to session.openFromStart + clamps to the captured offset;
 *   • real-count-only convergence: currentPage never chases a shrinking count on append (no shrink).
 *
 * All JVM: a deterministic fake measurer + a StandardTestDispatcher passed as BOTH the paginator's
 * index dispatcher AND the session worker so timing is deterministic.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class TxtPageNavigatorWindowedTest {

    private val style = TextStyle()

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

    /** A measurer that PARKS its worker thread on a latch after [gateAfterCalls] calls (mirrors the
     *  session-suite gate) so a test can observe a genuinely PARTIAL sealed frontier. */
    private class GatingMeasurer(
        private val charsPerLine: Int,
        private val gateAfterCalls: Int,
        private val lineHeightPx: Float = 10f,
    ) : LineMeasurer {
        val reachedGate = CountDownLatch(1)
        private val release = CountDownLatch(1)
        private var calls = 0
        override fun measure(text: CharSequence, style: TextStyle, maxWidthPx: Float): List<LineMetric> {
            if (++calls == gateAfterCalls) { reachedGate.countDown(); release.await(5, TimeUnit.SECONDS) }
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
        fun release() = release.countDown()
    }

    private val big = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
    private fun box(heightPx: Float, widthPx: Float = 1000f) = PageContentBox(widthPx, heightPx)
    private fun rowsDoc(rows: Int) = TxtDocument.of((0 until rows).joinToString("") { "row$it\n" })

    // === first-window publish: partial index + currentPage == pageContaining(captured) ===

    @Test fun firstWindowPublish_setsPartialIndex_currentPageIsPageContainingCaptured() = runTest {
        // Capture the navigator state at the moment of the FIRST published snapshot (which is PARTIAL
        // for a multi-page doc) — deterministic on the test dispatcher, no thread parking needed.
        val doc = rowsDoc(80)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val nav = TxtPageNavigator(paginator)
        val session = PaginationSession(paginator, worker = worker)

        val capturedOffset = 0
        val firstWasPartial = CompletableDeferred<Boolean>()
        val firstCurrentPage = CompletableDeferred<Int>()
        val firstPageContaining = CompletableDeferred<Int>()
        nav.reconcileAfterReflow(
            doc, style, boxPx, m, isMarkdown = false, scope = this, session = session,
            onSnapshot = { snapshot ->
                if (!firstWasPartial.isCompleted) {
                    // Observed AFTER the navigator installed the snapshot (installReflowSnapshot ran first).
                    firstWasPartial.complete(!snapshot.isComplete)
                    firstCurrentPage.complete(nav.currentPage)
                    firstPageContaining.complete(snapshot.pageContaining(capturedOffset))
                }
            },
        )
        advanceUntilIdle()

        assertTrue("first publish is a PARTIAL index", firstWasPartial.await())
        assertEquals("currentPage clamps to pageContaining(captured)", firstPageContaining.await(), firstCurrentPage.await())
        assertEquals(0, firstCurrentPage.await())
        // The whole book ultimately completes.
        assertTrue("navigator eventually complete", nav.isComplete)
    }

    // === a background append does NOT move currentPage ===

    @Test fun backgroundAppend_doesNotMoveCurrentPage() = runTest {
        val doc = rowsDoc(80)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val nav = TxtPageNavigator(paginator)
        val session = PaginationSession(paginator, worker = worker)

        nav.reconcileAfterReflow(doc, style, boxPx, m, isMarkdown = false, scope = this, session = session)
        runCurrent()
        // The user is on page 0. Record it.
        val pageBeforeAppend = nav.currentPage
        assertEquals(0, pageBeforeAppend)

        // Drain the background completion — the count GROWS (append-only) but currentPage must not move.
        advanceUntilIdle()
        assertTrue("index completed (grew) via background append", nav.index!!.isComplete)
        assertTrue("count grew on append", nav.index!!.pageCount > 1)
        assertEquals("currentPage unchanged by a background append", pageBeforeAppend, nav.currentPage)
    }

    // === async jumpToOffset(beyondFrontier, session) extends-then-resolves to the exact page ===

    @Test fun asyncJumpToOffset_beyondFrontier_extendsThenResolvesExact_eventual() = runTest {
        // The navigator is single-writer by design (main thread). We PARK the background loop mid-book
        // (real worker thread) so the session holds a genuinely PARTIAL frontier, install that partial
        // snapshot into the navigator, then issue the async jump. The jump extends the frontier via the
        // session and resolves to the exact page (EVENTUAL). No competing reflow-observer mutates the
        // navigator (the jump is the sole writer) — mirroring the main-thread serialization.
        val doc = rowsDoc(80)
        val worker = Dispatchers.IO
        val paginator = TxtPaginator(worker)
        val fullMeasurer = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = paginator.index(doc, style, boxPx, fullMeasurer, PaginationToken())
        assertTrue(full.pageCount >= 10)
        val nav = TxtPageNavigator(paginator)
        val session = PaginationSession(paginator, worker = worker)
        val m = GatingMeasurer(charsPerLine = 7, gateAfterCalls = doc.chunkCount / 3)

        // Open (background loop parks mid-book). onSnapshot only mirrors the snapshot into the navigator
        // — no re-clamp; we take the FIRST partial snapshot and stop touching the navigator from here.
        val firstPartial = CompletableDeferred<TxtPageIndex>()
        launch {
            session.openFromStart(doc, style, boxPx, m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { if (!firstPartial.isCompleted) firstPartial.complete(it) }, onReveal = { })
        }
        withContext(Dispatchers.IO) { m.reachedGate.await(5, TimeUnit.SECONDS) }
        val partial = firstPartial.await()
        assertFalse("frontier is partial (short of doc end)", partial.isComplete)
        nav.setIndex(partial)   // install the partial index (single-writer, on the test thread)
        val frontier = partial.frontierSourceOffset

        val targetPage = full.pageCount - 2
        val targetOffset = full.pageStart(targetPage)
        assertTrue("target is beyond the current frontier", targetOffset >= frontier)

        // Async jump — EVENTUAL: extends the sealed frontier through the target, installs the extended
        // snapshot, then resolves currentPage + pendingScrollTarget. Release the gate so the extend can
        // proceed (it coalesces with / follows the background loop through the target).
        m.release()
        nav.jumpToOffset(targetOffset, session)
        advanceUntilIdle()

        assertEquals("jump landed on the exact page", full.pageContaining(targetOffset), nav.currentPage)
        assertEquals("pendingScrollTarget set to the landing page", full.pageContaining(targetOffset), nav.pendingScrollTarget)
        assertTrue("the installed snapshot covers the target", nav.index!!.pageContaining(targetOffset) == full.pageContaining(targetOffset))
    }

    @Test fun asyncJumpToOffset_withinSealedRegion_isSynchronousExact() = runTest {
        // Within the sealed region the async jump takes the synchronous path — no extra measuring.
        val doc = rowsDoc(80)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = paginator.index(doc, style, boxPx, m, PaginationToken())
        val nav = TxtPageNavigator(paginator)
        val session = PaginationSession(paginator, worker = worker)

        nav.reconcileAfterReflow(doc, style, boxPx, m, isMarkdown = false, scope = this, session = session)
        advanceUntilIdle()   // fully complete → the whole doc is sealed
        assertTrue(nav.isComplete)

        val within = full.pageStart(3)
        launch { nav.jumpToOffset(within, session) }
        advanceUntilIdle()
        assertEquals(3, nav.currentPage)
        assertEquals(3, nav.pendingScrollTarget)
    }

    // === reflow mid-background delegates to openFromStart + clamps to the captured offset ===

    @Test fun reflowMidBackground_delegatesToOpenFromStart_clampsToCaptured() = runTest {
        val doc = rowsDoc(80)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val boxTight = box(10f)   // 1 line/page (with the `big` measurer) → many pages
        val boxWide = box(30f)    // 3 lines/page → fewer pages
        val fullTight = paginator.index(doc, style, boxTight, big, PaginationToken())
        val fullWide = paginator.index(doc, style, boxWide, big, PaginationToken())
        assertTrue("distinct counts", fullTight.pageCount != fullWide.pageCount)
        val nav = TxtPageNavigator(paginator)
        val session = PaginationSession(paginator, worker = worker)

        // Open A (tight) and complete so we can land on a real page.
        nav.reconcileAfterReflow(doc, style, boxTight, big, isMarkdown = false, scope = this, session = session)
        advanceUntilIdle()
        assertEquals(fullTight.pageCount, nav.index!!.pageCount)
        nav.onPagerPageChanged(4)
        val capturedOffset = nav.currentSourceOffset()

        // Reflow B (wide) — mid-flow. Delegates to session.openFromStart from the captured offset; the
        // new index clamps to pageContaining(captured).
        nav.reconcileAfterReflow(doc, style, boxWide, big, isMarkdown = false, scope = this, session = session)
        advanceUntilIdle()

        assertEquals("reflow re-paginated to the wide index", fullWide.pageCount, nav.index!!.pageCount)
        assertEquals("clamped to the captured offset's page", fullWide.pageContaining(capturedOffset), nav.currentPage)
        assertEquals(fullWide.pageContaining(capturedOffset), nav.pendingScrollTarget)
    }

    // === real-count-only convergence: no shrink on append ===

    @Test fun realCountOnly_noShrinkOnAppend_countGrowsMonotonically() = runTest {
        val doc = rowsDoc(120)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = FixedLineMeasurer(charsPerLine = 6, lineHeightPx = 10f)
        val boxPx = box(20f)
        val full = paginator.index(doc, style, boxPx, m, PaginationToken())
        val nav = TxtPageNavigator(paginator)
        val session = PaginationSession(paginator, worker = worker)

        val counts = ArrayList<Int>()
        // The session's onSnapshot mirrors into the navigator; we observe the growing count.
        nav.reconcileAfterReflow(
            doc, style, boxPx, m, isMarkdown = false, scope = this, session = session,
            onSnapshot = { counts.add(it.pageCount) },
        )
        advanceUntilIdle()

        assertTrue("published at least the first window then completions", counts.size >= 1)
        // The count is monotonically non-decreasing across every republish (append-only, never shrinks).
        for (i in 1 until counts.size) {
            assertTrue("count never shrinks on append (was ${counts[i - 1]} then ${counts[i]})", counts[i] >= counts[i - 1])
        }
        assertEquals("final count == the full deterministic index", full.pageCount, nav.index!!.pageCount)
    }
}
