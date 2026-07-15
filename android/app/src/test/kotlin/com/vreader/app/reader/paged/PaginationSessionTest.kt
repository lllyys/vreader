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
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Test

/**
 * Feature #138 WI-4 — [PaginationSession]: the single Mutex/worker OWNER of the windowed pagination
 * lifecycle. It drives WI-1/2/3's resumable core ([TxtPaginator.freshCursor]/[measurePages]/
 * [measureThroughOffset]) under ONE mutex + one worker so:
 *   • a fast first sealed window publishes, then a coalesced background loop completes to the full
 *     index (byte-identical to [TxtPaginator.index]);
 *   • [PaginationSession.ensureMeasuredThrough] extends past the frontier + returns an exact snapshot;
 *   • PAGE/WINDOW-sized critical sections — the mutex is NEVER held across a full-book run, so an
 *     on-demand [ensureMeasuredThrough] interleaves at a window boundary (single-writer, coalesced);
 *   • a generation check IMMEDIATELY before every publish drops a superseded pass (reflow/dispose);
 *   • main-thread callbacks ([onSnapshot]/[onReveal]) fire ONLY after the mutation lock is released;
 *   • [onReveal] fires exactly once with the resume source offset when the anchor page first seals.
 *
 * All JVM: a deterministic fake measurer + a test dispatcher passed as the session `worker` so timing
 * is deterministic. An INSTRUMENTED measurer proves the single-writer + lock-released invariants.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class PaginationSessionTest {

    private val style = TextStyle()

    /** Same deterministic fixed-width line breaker the sibling suites use. */
    private open class FixedLineMeasurer(
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

    /**
     * Records whether [measure] is ever entered RE-ENTRANTLY (a concurrent call) — the single-writer
     * proof (invariant 4). One [LineMeasurer] used only under the mutex means measure is never called
     * concurrently. Also counts total calls.
     */
    private class CountingMeasurer(
        charsPerLine: Int,
        lineHeightPx: Float = 10f,
    ) : FixedLineMeasurer(charsPerLine, lineHeightPx) {
        private val inFlight = AtomicInteger(0)
        val everReentrant = AtomicBoolean(false)
        val calls = AtomicInteger(0)
        override fun measure(text: CharSequence, style: TextStyle, maxWidthPx: Float): List<LineMetric> {
            calls.incrementAndGet()
            if (inFlight.incrementAndGet() > 1) everReentrant.set(true)
            try {
                return super.measure(text, style, maxWidthPx)
            } finally {
                inFlight.decrementAndGet()
            }
        }
    }

    /**
     * A measurer that BLOCKS its thread on a latch once [gateAfterCalls] measure calls have run — used
     * to PARK the background completion loop mid-book on a REAL background dispatcher, so a test can
     * prove (a) the mutex is released between windows (an ensureMeasuredThrough still can't proceed if
     * the loop parked mid-critical-section, so parking BETWEEN windows is what lets it interleave), and
     * (b) a supersede issued while the loop is parked drops the stale publish. The gate blocks a REAL
     * worker thread (never the test scheduler), so the test coroutine keeps running.
     */
    private class GatingMeasurer(
        charsPerLine: Int,
        private val gateAfterCalls: Int,
        lineHeightPx: Float = 10f,
    ) : FixedLineMeasurer(charsPerLine, lineHeightPx) {
        val calls = AtomicInteger(0)
        val reachedGate = CountDownLatch(1)
        private val release = CountDownLatch(1)
        private val inFlight = AtomicInteger(0)
        val everReentrant = AtomicBoolean(false)
        override fun measure(text: CharSequence, style: TextStyle, maxWidthPx: Float): List<LineMetric> {
            if (inFlight.incrementAndGet() > 1) everReentrant.set(true)
            try {
                val n = calls.incrementAndGet()
                if (n == gateAfterCalls) {
                    reachedGate.countDown()
                    release.await(5, TimeUnit.SECONDS)   // park this worker thread at the gate
                }
                return super.measure(text, style, maxWidthPx)
            } finally {
                inFlight.decrementAndGet()
            }
        }
        fun release() = release.countDown()
    }

    private fun box(heightPx: Float, widthPx: Float = 1000f) = PageContentBox(widthPx, heightPx)

    /** A multi-page doc: N one-line "rowK\n" chunks. */
    private fun rowsDoc(rows: Int) = TxtDocument.of((0 until rows).joinToString("") { "row$it\n" })

    // === (1) openFromStart publishes the first sealed window, then background-completes to full ===

    @Test fun openFromStart_publishesFirstWindow_thenCompletesToFullIndex() = runTest {
        val doc = rowsDoc(80)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = paginator.index(doc, style, boxPx, m, PaginationToken())
        assertTrue("precondition: many pages", full.pageCount >= 10)

        val session = PaginationSession(paginator, worker = worker)
        val snapshots = ArrayList<TxtPageIndex>()
        launch {
            session.openFromStart(
                document = doc, style = style, contentBox = boxPx, measurer = m, isMarkdown = false,
                resumeAnchorOffset = 0,
                onSnapshot = { snapshots.add(it) }, onReveal = { },
            )
        }
        // Let the first window publish.
        runCurrent()
        assertTrue("first window published quickly", snapshots.isNotEmpty())
        val first = snapshots.first()
        assertFalse("first snapshot is a PARTIAL index", first.isComplete)
        assertTrue("first window seals >= 1 page", first.pageCount >= 1)
        assertEquals("page 0 is doc start", 0, first.pageStart(0))

        // Drain the background completion loop.
        advanceUntilIdle()
        val last = snapshots.last()
        assertTrue("final snapshot is complete", last.isComplete)
        // The final sealed list is byte-identical to the deterministic full index().
        assertEquals(full.pageStartsUtf16.toList(), last.pageStartsUtf16.toList())
        assertEquals(full.docEndExclusive, last.docEndExclusive)
        // snapshot() exposes the latest published immutable snapshot.
        assertEquals(full.pageStartsUtf16.toList(), session.snapshot()!!.pageStartsUtf16.toList())
    }

    // === (2) ensureMeasuredThrough(beyondFrontier) extends + returns an exact snapshot ===

    @Test fun ensureMeasuredThrough_beyondFrontier_extendsAndResolvesExact() = runTest {
        // Park the background loop mid-book (real worker thread) so the sealed frontier is genuinely
        // SHORT of the target; then ensureMeasuredThrough extends past it and resolves exactly.
        val doc = rowsDoc(60)
        val worker = Dispatchers.IO
        val paginator = TxtPaginator(worker)
        val fullMeasurer = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = paginator.index(doc, style, boxPx, fullMeasurer, PaginationToken())
        assertTrue(full.pageCount >= 8)

        // Gate roughly mid-book (well after the first window has published, before completion) so a far
        // offset is beyond the sealed frontier when the extend runs.
        val m = GatingMeasurer(charsPerLine = 7, gateAfterCalls = doc.chunkCount / 2)
        val session = PaginationSession(paginator, worker = worker)
        launch {
            session.openFromStart(doc, style, boxPx, m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { }, onReveal = { })
        }
        // Wait (real) for the loop to park mid-book, then confirm the frontier is short of doc end.
        withContext(Dispatchers.IO) { m.reachedGate.await(5, TimeUnit.SECONDS) }
        val frontierAfterPark = session.snapshot()!!.frontierSourceOffset
        assertTrue("frontier parked short of doc end", frontierAfterPark < doc.text.length)

        // Target a page beyond the parked frontier.
        val targetPage = full.pageCount - 2
        val targetOffset = (full.pageStart(targetPage) + full.pageEndExclusive(targetPage)) / 2
        assertTrue("target is beyond the parked frontier", targetOffset >= frontierAfterPark)

        m.release()
        val snap = session.ensureMeasuredThrough(targetOffset)
        advanceUntilIdle()
        // The returned snapshot resolves pageContaining(target) exactly to index()'s page.
        assertEquals(full.pageContaining(targetOffset), snap.pageContaining(targetOffset))
        assertEquals(full.pageStart(targetPage), snap.pageStart(targetPage))
        assertEquals(full.pageEndExclusive(targetPage), snap.pageEndExclusive(targetPage))
    }

    @Test fun ensureMeasuredThrough_alreadySealedOffset_doesNotMeasureMore() = runTest {
        val doc = rowsDoc(80)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = CountingMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = paginator.index(doc, style, boxPx, m, PaginationToken())

        val session = PaginationSession(paginator, worker = worker)
        launch {
            session.openFromStart(doc, style, boxPx, m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { }, onReveal = { })
        }
        advanceUntilIdle()   // fully complete
        assertTrue(session.snapshot()!!.isComplete)
        val callsAfterComplete = m.calls.get()

        // Ask for an offset WELL within the already-sealed (complete) region → no extra measuring.
        val within = full.pageStart(2)
        val snap = CompletableDeferred<TxtPageIndex>()
        launch { snap.complete(session.ensureMeasuredThrough(within)) }
        advanceUntilIdle()
        assertEquals("no additional measure calls for a sealed offset", callsAfterComplete, m.calls.get())
        assertEquals(full.pageContaining(within), snap.await().pageContaining(within))
    }

    // === (3) single-writer serialization + bounded critical sections (invariant 4) ===

    @Test fun singleWriter_measurerNeverReentrant_finalListMatchesFull() = runTest {
        // A background loop + a concurrent ensureMeasuredThrough MUST NOT interleave a lost update:
        // (a) the ONE measurer is never entered re-entrantly (single-writer proof), AND
        // (b) the final sealed list == the deterministic full list (no dropped/duplicated page).
        val doc = rowsDoc(100)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = CountingMeasurer(charsPerLine = 6, lineHeightPx = 10f)
        val boxPx = box(20f)
        val full = paginator.index(doc, style, boxPx, m, PaginationToken())
        assertTrue(full.pageCount >= 12)

        val session = PaginationSession(paginator, worker = worker)
        launch {
            session.openFromStart(doc, style, boxPx, m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { }, onReveal = { })
        }
        runCurrent()   // first window only — background still pending
        // Fire an on-demand extend that overlaps the still-running background loop.
        val mid = full.pageStart(full.pageCount / 2)
        launch { session.ensureMeasuredThrough(mid) }
        advanceUntilIdle()

        assertFalse("the ONE measurer was never entered re-entrantly", m.everReentrant.get())
        val finalSnap = session.snapshot()!!
        assertTrue(finalSnap.isComplete)
        assertEquals(
            "final sealed list == deterministic full list (no lost update)",
            full.pageStartsUtf16.toList(), finalSnap.pageStartsUtf16.toList(),
        )
    }

    @Test fun mutexNotHeldAcrossFullBookRun_ensureInterleavesAtWindowBoundary() = runTest {
        // PARK the background loop mid-book (real worker thread, mutex held for that ONE window). Fire
        // an ensureMeasuredThrough — it blocks on the mutex. RELEASE the gate: the parked window
        // finishes and RELEASES the mutex at the window boundary, so the extend can now interleave. If
        // the mutex were held across the WHOLE book, the extend would only resolve after completion; the
        // ONE measurer is also never entered re-entrantly (single-writer). We prove the extend resolves
        // AND covers mid AND the measurer never overlapped.
        val doc = rowsDoc(120)
        val worker = Dispatchers.IO
        val paginator = TxtPaginator(worker)
        val fullMeasurer = FixedLineMeasurer(charsPerLine = 6, lineHeightPx = 10f)
        val boxPx = box(20f)
        val full = paginator.index(doc, style, boxPx, fullMeasurer, PaginationToken())
        assertTrue(full.pageCount >= 15)

        val m = GatingMeasurer(charsPerLine = 6, gateAfterCalls = doc.chunkCount / 3)
        val session = PaginationSession(paginator, worker = worker)
        launch {
            session.openFromStart(doc, style, boxPx, m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { }, onReveal = { })
        }
        withContext(Dispatchers.IO) { m.reachedGate.await(5, TimeUnit.SECONDS) }
        // Parked mid-book → the frontier is short of doc end (a window boundary WILL exist to interleave at).
        assertTrue("frontier parked short of doc end", session.snapshot()!!.frontierSourceOffset < doc.text.length)

        val mid = full.pageStart(full.pageCount / 2)
        m.release()   // let the parked window finish + release the mutex at the boundary
        val snap = session.ensureMeasuredThrough(mid)
        advanceUntilIdle()

        assertFalse("the ONE measurer was never entered re-entrantly (single writer)", m.everReentrant.get())
        // The extend RESOLVED (did not deadlock waiting for the whole book) → the mutex was released
        // between windows, not held across the full run. The returned snapshot covers mid exactly.
        assertEquals("extend covered the mid offset exactly", full.pageContaining(mid), snap.pageContaining(mid))
        assertEquals("extend's snapshot pages the mid offset exactly", full.pageStart(full.pageCount / 2), snap.pageStart(snap.pageContaining(mid)))
        // Whatever pages the extend sealed match index()'s prefix byte-for-byte (no lost update from
        // interleaving with the background loop). Full-completion convergence is proven by
        // singleWriter_measurerNeverReentrant_finalListMatchesFull.
        val prefix = snap.pageStartsUtf16.toList()
        assertEquals("extend's sealed prefix == index()'s prefix", full.pageStartsUtf16.toList().take(prefix.size), prefix)
    }

    // === (4) stale-generation publish dropped after supersede ===

    @Test fun supersede_dropsInFlightWindowPublish_noSnapshotAfterSupersede() = runTest {
        // PARK the loop mid-book (real thread). Supersede while parked. Release: the parked window's
        // publish must be DROPPED by the generation re-check (no onSnapshot after supersede), and no
        // subsequent window publishes either — the loop is dead.
        val doc = rowsDoc(120)
        val worker = Dispatchers.IO
        val paginator = TxtPaginator(worker)
        val m = GatingMeasurer(charsPerLine = 6, gateAfterCalls = doc.chunkCount / 3)
        val boxPx = box(20f)

        val session = PaginationSession(paginator, worker = worker)
        val snapshotsAfterSupersede = AtomicInteger(0)
        val superseded = AtomicBoolean(false)
        launch {
            session.openFromStart(doc, style, boxPx, m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { if (superseded.get()) snapshotsAfterSupersede.incrementAndGet() },
                onReveal = { })
        }
        withContext(Dispatchers.IO) { m.reachedGate.await(5, TimeUnit.SECONDS) }
        superseded.set(true)
        session.supersede()   // supersede while the window is parked mid-measure
        m.release()
        advanceUntilIdle()
        // Give the real worker thread time to unwind past the release.
        withContext(Dispatchers.IO) { Thread.sleep(50) }

        assertEquals("no onSnapshot fires after supersede", 0, snapshotsAfterSupersede.get())
    }

    // === (5) no main callback under the lock (onSnapshot / onReveal observed lock-released) ===

    @Test fun noMainCallbackUnderLock_onSnapshotAndOnRevealObserveReleasedLock() = runTest {
        // The session must expose a testable "is the mutation lock currently held?" probe. Every
        // onSnapshot / onReveal callback asserts the lock is RELEASED at callback time — no main-thread
        // work runs under the lock (no lock-order inversion).
        val doc = rowsDoc(80)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = paginator.index(doc, style, boxPx, m, PaginationToken())
        val anchor = full.pageStart(full.pageCount / 2)   // a deep anchor → onReveal fires

        val session = PaginationSession(paginator, worker = worker)
        val lockHeldAtSnapshot = AtomicBoolean(false)
        val lockHeldAtReveal = AtomicBoolean(false)
        launch {
            session.openFromStart(doc, style, boxPx, m, isMarkdown = false, resumeAnchorOffset = anchor,
                onSnapshot = { if (session.isMutationLockHeldForTest()) lockHeldAtSnapshot.set(true) },
                onReveal = { if (session.isMutationLockHeldForTest()) lockHeldAtReveal.set(true) })
        }
        advanceUntilIdle()
        assertFalse("onSnapshot never runs under the mutation lock", lockHeldAtSnapshot.get())
        assertFalse("onReveal never runs under the mutation lock", lockHeldAtReveal.get())
    }

    // === (6) onReveal fires exactly once with the resume offset when the anchor page seals ===

    @Test fun onReveal_firesExactlyOnce_withResumeOffset_whenAnchorSeals() = runTest {
        val doc = rowsDoc(80)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)
        val full = paginator.index(doc, style, boxPx, m, PaginationToken())
        // A DEEP anchor — its page seals only well into the background completion.
        val anchorPage = full.pageCount - 3
        val anchor = full.pageStart(anchorPage)

        val session = PaginationSession(paginator, worker = worker)
        val reveals = ArrayList<Int>()
        launch {
            session.openFromStart(doc, style, boxPx, m, isMarkdown = false, resumeAnchorOffset = anchor,
                onSnapshot = { }, onReveal = { reveals.add(it) })
        }
        advanceUntilIdle()

        assertEquals("onReveal fires exactly once", 1, reveals.size)
        assertEquals("onReveal carries the resume source offset", anchor, reveals.first())
    }

    @Test fun onReveal_absentWhenAnchorZero_firstSnapshotContainsIt() = runTest {
        // anchor == 0 (or near start): the FIRST snapshot already contains the resume page, so NO
        // onReveal fires (the body needs no deep-resume auto-scroll).
        val doc = rowsDoc(80)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)
        val boxPx = box(25f)

        val session = PaginationSession(paginator, worker = worker)
        val reveals = ArrayList<Int>()
        val firstSnapshot = CompletableDeferred<TxtPageIndex>()
        launch {
            session.openFromStart(doc, style, boxPx, m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { if (!firstSnapshot.isCompleted) firstSnapshot.complete(it) },
                onReveal = { reveals.add(it) })
        }
        advanceUntilIdle()
        assertTrue("no onReveal for anchor 0", reveals.isEmpty())
        assertEquals("first snapshot already contains page 0 (the anchor)", 0, firstSnapshot.await().pageContaining(0))
    }

    // === (7) edge cases: empty doc, one-page doc, degenerate box, cancellation ===

    @Test fun emptyDoc_completesImmediately_zeroPages_noReveal() = runTest {
        val doc = TxtDocument.of("")
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)

        val session = PaginationSession(paginator, worker = worker)
        val snapshots = ArrayList<TxtPageIndex>()
        val reveals = ArrayList<Int>()
        launch {
            session.openFromStart(doc, style, box(25f), m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { snapshots.add(it) }, onReveal = { reveals.add(it) })
        }
        advanceUntilIdle()
        assertNotNull(session.snapshot())
        assertTrue("empty doc is complete", session.snapshot()!!.isComplete)
        assertEquals(0, session.snapshot()!!.pageCount)
        assertTrue("no reveal for empty doc", reveals.isEmpty())
    }

    @Test fun onePageDoc_completesImmediately_noBackgroundLoopNeeded() = runTest {
        // A doc that fits in one page seals its single page at doc end in the first pass → complete
        // immediately with page 0 == doc start, no background completion beyond that.
        val doc = TxtDocument.of("hello world\n")
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
        val boxPx = box(100f)   // plenty of height for the single line
        val full = paginator.index(doc, style, boxPx, m, PaginationToken())
        assertEquals("precondition: exactly one page", 1, full.pageCount)

        val session = PaginationSession(paginator, worker = worker)
        launch {
            session.openFromStart(doc, style, boxPx, m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { }, onReveal = { })
        }
        advanceUntilIdle()
        val snap = session.snapshot()!!
        assertTrue("one-page doc is complete", snap.isComplete)
        assertEquals(1, snap.pageCount)
        assertEquals(0, snap.pageStart(0))
        assertEquals(doc.text.length, snap.pageEndExclusive(0))
    }

    @Test fun degenerateBox_degradesBeforeWindowing_returnsDegenerateSnapshot() = runTest {
        val doc = rowsDoc(40)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val m = FixedLineMeasurer(charsPerLine = 7, lineHeightPx = 10f)

        val session = PaginationSession(paginator, worker = worker)
        launch {
            session.openFromStart(doc, style, box(0f), m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { }, onReveal = { })
        }
        advanceUntilIdle()
        val snap = session.snapshot()!!
        assertTrue("degenerate box degrades to the degrade signal", snap.isDegenerate)
        assertEquals(0, snap.pageCount)
    }

    @Test fun cancellation_ofBackgroundLoop_stopsPublishing_viaSupersede() = runTest {
        // supersede() cancels the active generation's token → the background loop aborts and stops
        // publishing. PARKED mid-book (real thread), a supersede must ensure NO complete snapshot is
        // ever published (the loop is dead after release).
        val doc = rowsDoc(200)
        val worker = Dispatchers.IO
        val paginator = TxtPaginator(worker)
        val m = GatingMeasurer(charsPerLine = 6, gateAfterCalls = doc.chunkCount / 3)
        val boxPx = box(20f)

        val session = PaginationSession(paginator, worker = worker)
        val completeEverPublished = AtomicBoolean(false)
        launch {
            session.openFromStart(doc, style, boxPx, m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { if (it.isComplete) completeEverPublished.set(true) }, onReveal = { })
        }
        withContext(Dispatchers.IO) { m.reachedGate.await(5, TimeUnit.SECONDS) }
        session.supersede()   // supersede while the loop is parked mid-book (not yet complete)
        m.release()
        advanceUntilIdle()
        withContext(Dispatchers.IO) { Thread.sleep(50) }
        assertFalse("a superseded background loop never publishes a complete index", completeEverPublished.get())
    }

    // === (8) a fresh openFromStart supersedes a prior generation (reflow reuse) ===

    @Test fun openFromStart_supersedesPriorGeneration_onlyNewestCompletes() = runTest {
        val doc = rowsDoc(80)
        val worker = StandardTestDispatcher(testScheduler)
        val paginator = TxtPaginator(worker)
        val boxTight = box(10f)     // 1 line/page → many pages
        val boxWide = box(30f)      // 3 lines/page → fewer pages
        val m = FixedLineMeasurer(charsPerLine = 100, lineHeightPx = 10f)
        val fullTight = paginator.index(doc, style, boxTight, m, PaginationToken())
        val fullWide = paginator.index(doc, style, boxWide, m, PaginationToken())
        assertTrue("distinct page counts", fullTight.pageCount != fullWide.pageCount)

        val session = PaginationSession(paginator, worker = worker)
        // Open A (tight), then immediately re-open B (wide) BEFORE A's background drains — B supersedes A.
        launch {
            session.openFromStart(doc, style, boxTight, m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { }, onReveal = { })
        }
        runCurrent()
        launch {
            session.openFromStart(doc, style, boxWide, m, isMarkdown = false, resumeAnchorOffset = 0,
                onSnapshot = { }, onReveal = { })
        }
        advanceUntilIdle()
        // Only B's (wide) index completes and is the final snapshot.
        val snap = session.snapshot()!!
        assertTrue(snap.isComplete)
        assertEquals("newest openFromStart wins", fullWide.pageStartsUtf16.toList(), snap.pageStartsUtf16.toList())
    }
}
