package com.vreader.app.annotations

import com.vreader.app.imports.IncomingImportCoordinator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.junit.After
import org.junit.AfterClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.backup.BackupJson
import java.util.concurrent.atomic.AtomicReference

/**
 * Feature #165 WI-4b — **A-12**: a hostile provider cannot wedge the reader, in BOTH directions.
 *
 * Five parked call sites, one case each (§8.1 / §9.1 A-12):
 *  1. import `ContentResolver.query`      3. import `InputStream.read`     5. export `OutputStream.write`
 *  2. import `openInputStream`            4. export `openOutputStream`
 * plus a sixth this implementation adds beyond the plan's five — a destination that parks on
 * `close()` — because an unbounded `close` in the one file whose job is "no unbounded provider
 * call" would be the same defect wearing a different name.
 *
 * Each case asserts THREE separable things, because any one of them alone passes on a broken build:
 *  * the caller **advanced** with a typed failure inside its budget — the GUARANTEE;
 *  * the provider is **still parked** when it did — which is what makes the previous line mean
 *    anything (a fake that returned would prove only that we can await a cooperative provider);
 *  * `abandonedCalls` on the **injected** gate incremented, and self-heals once the provider
 *    finally returns.
 *
 * These run on [runBlocking] + [Dispatchers.Default], NOT `runTest`: the whole point is a real
 * wall-clock deadline, and `runTest`'s virtual time would skip it and make the timing assertions
 * vacuous.
 */
@RunWith(RobolectricTestRunner::class)
class AnnotationsIoControllerTest {

    private val rig = ControllerRig()

    /** Held for the whole test by the budget-exhaustion cases; see [exhaustTheInjectedBudget]. */
    private val budgetLatch = ParkLatch()

    @After
    fun tearDown() {
        budgetLatch.release()
        rig.close()
    }

    // ---- 1. import: the metadata query parks ----------------------------------------------------

    @Test
    fun importMetadataQueryParkedForever_callerAdvancesWithTimeout() = runBlocking {
        rig.port.parkAt = FakeSafPort.Site.METADATA

        val elapsed = timed { assertParseFailure(ImportFailure.Timeout, previewOnce()) }

        assertAdvancedWhileParked(elapsed)
        assertEquals("no stream may be opened after a parked query", 0, rig.port.openInputCallCount)
        assertSelfHeals()
    }

    // ---- 2. import: openInputStream parks -------------------------------------------------------

    @Test
    fun importOpenInputStreamParkedForever_callerAdvancesWithTimeout() = runBlocking {
        rig.port.parkAt = FakeSafPort.Site.OPEN_INPUT

        val elapsed = timed { assertParseFailure(ImportFailure.Timeout, previewOnce()) }

        assertAdvancedWhileParked(elapsed)
        assertSelfHeals()
    }

    // ---- 3. import: the returned stream's read parks --------------------------------------------

    @Test
    fun importStreamReadParkedForever_callerAdvancesWithTimeout() = runBlocking {
        val parking = ParkingInputStream(rig.port.latch)
        rig.port.inputFactory = { parking }

        val elapsed = timed { assertParseFailure(ImportFailure.Timeout, previewOnce()) }

        assertAdvancedWhileParked(elapsed)
        // Best-effort ONLY, and now DISPATCHED rather than inline, so it is observed with a wait
        // rather than read straight after the call. Correctness never depends on it, which is why
        // this stream's close() does not unpark the latch.
        assertTrue("onExpiry should attempt the best-effort close", rig.awaitUntil { parking.closeCount >= 1 })
        assertSelfHeals()
    }

    // ---- 4. export: openOutputStream parks ------------------------------------------------------

    @Test
    fun exportOpenOutputStreamParkedForever_callerAdvancesWithTimeout() = runBlocking {
        rig.port.parkAt = FakeSafPort.Site.OPEN_OUTPUT

        val elapsed = timed { assertExportFailure(ImportFailure.Timeout, exportOnce()) }

        assertAdvancedWhileParked(elapsed)
        assertSelfHeals()
    }

    // ---- 5. export: the open returns promptly and the WRITE parks -------------------------------

    @Test
    fun exportStreamWriteParkedForever_callerAdvancesWithTimeout() = runBlocking {
        val parking = ParkingOutputStream(rig.port.latch)
        rig.port.outputFactory = { parking }
        seedOneHighlight()

        val elapsed = timed { assertExportFailure(ImportFailure.Timeout, exportOnce()) }

        assertAdvancedWhileParked(elapsed)
        assertEquals("the open itself succeeded", 1, rig.port.openOutputCallCount)
        assertTrue("onExpiry should attempt the best-effort close", rig.awaitUntil { parking.closeCount >= 1 })
        assertSelfHeals()
    }

    // ---- 6. export: the destination parks on close() (beyond the plan's five) -------------------

    @Test
    fun exportStreamCloseParkedForever_callerAdvancesWithTimeout() = runBlocking {
        val sink = TrackingOutputStream(closeLatch = rig.port.latch)
        rig.port.outputFactory = { sink }
        seedOneHighlight()

        val elapsed = timed { assertExportFailure(ImportFailure.Timeout, exportOnce()) }

        assertAdvancedWhileParked(elapsed)
        assertTrue("the bytes were written before the close parked", sink.text().contains("schemaVersion"))
        assertSelfHeals()
    }

    // ---- the rescue itself parks (Gate-4 round 1, Critical) -------------------------------------

    /**
     * The gate runs `onExpiry` SYNCHRONOUSLY on the caller's coroutine, just before returning
     * `TimedOut`. So a best-effort close that itself parks wedges the caller it was meant to
     * rescue — the whole defect, reintroduced through the cleanup path. The audit found this while
     * every park case above was green, because their fakes all close promptly.
     */
    @Test
    fun importReadAndItsRescueCloseBothParkForever_callerStillAdvances() = runBlocking {
        val closeLatch = ParkLatch()
        rig.port.inputFactory = { ParkingInputStream(rig.port.latch, closeLatch = closeLatch) }

        val elapsed = timed { assertParseFailure(ImportFailure.Timeout, previewOnce()) }

        assertAdvancedWhileParked(elapsed)
        // The rescue is DISPATCHED, so it is observed with a wait — reading `isParked` straight
        // after the call raced it and failed intermittently.
        assertTrue(
            "the rescue close was attempted and is itself stuck",
            rig.awaitUntil { closeLatch.isParked },
        )
        closeLatch.release()
        assertSelfHeals()
    }

    @Test
    fun exportWriteAndItsRescueCloseBothParkForever_callerStillAdvances() = runBlocking {
        val closeLatch = ParkLatch()
        rig.port.outputFactory = { ParkingOutputStream(rig.port.latch, closeLatch = closeLatch) }
        seedOneHighlight()

        val elapsed = timed { assertExportFailure(ImportFailure.Timeout, exportOnce()) }

        assertAdvancedWhileParked(elapsed)
        // The rescue is DISPATCHED, so it is observed with a wait — reading `isParked` straight
        // after the call raced it and failed intermittently.
        assertTrue(
            "the rescue close was attempted and is itself stuck",
            rig.awaitUntil { closeLatch.isParked },
        )
        closeLatch.release()
        assertSelfHeals()
    }

    /** The import direction's own close, which the round-1 suite left untested entirely. */
    @Test
    fun importCloseParkedForever_previewStillReturnsItsAnswer() = runBlocking {
        rig.port.inputFactory = {
            TrackingInputStream(EMPTY_ENVELOPE.toByteArray(), closeLatch = rig.port.latch)
        }

        var parsed: ImportParseResult? = null
        val elapsed = timed { parsed = previewOnce() }

        assertTrue("the bytes were read, so the answer stands: $parsed", parsed is ImportParseResult.Ok)
        assertAdvancedWhileParked(elapsed)
        assertSelfHeals()
    }

    /**
     * The rescue itself must not become the exhaustion surface it was added to avoid (Gate-4
     * round 2, High). A rescue close that parks holds a thread the gate's ledger does NOT charge —
     * the ledger self-heals when the original call returns, while the rescue stays parked — so an
     * unbounded lane would accumulate threads forever.
     *
     * Each round below parks a read, lets it expire, then releases ONLY the read so the ledger
     * self-heals while that round's rescue close stays parked for good. After more rounds than the
     * cap, both properties must still hold: every caller advanced, and the live rescue threads are
     * capped.
     */
    @Test
    fun theBestEffortCloseLaneIsBoundedAndNeverBlocksTheCaller() = runBlocking {
        val closeLatch = ParkLatch()
        val rounds = rig.cleanup.maxExpiryCloses + 5
        try {
            repeat(rounds) {
                val readLatch = ParkLatch()
                rig.port.inputFactory = { ParkingInputStream(readLatch, closeLatch = closeLatch) }

                // The caller advances every single round — that is the invariant under test. The
                // LEDGER deliberately is NOT asserted per round: past the cap a rescue is dropped
                // and `dispose` closes on the abandoned job's own thread, so a close that parks
                // legitimately keeps its charge (the fd really is still held).
                val outcome = previewOnce()
                assertTrue(
                    "round $it did not return a typed failure: $outcome",
                    outcome == ImportParseResult.Failed(ImportFailure.Timeout) ||
                        outcome == ImportParseResult.Failed(ImportFailure.Busy),
                )
                readLatch.release()
            }

            assertTrue("the rescues really are stuck, so the cap was under pressure", closeLatch.isParked)
            assertTrue(
                "the rescue lane grew past its cap: ${liveExpiryThreads()} threads for $rounds rounds",
                liveExpiryThreads() <= rig.cleanup.maxExpiryCloses,
            )
        } finally {
            drain(closeLatch)
        }
    }

    /** THIS rig's lane only — a process-wide thread scan would count other tests' rescues too. */
    private fun liveExpiryThreads(): Int = rig.cleanup.laneThreadCount

    /**
     * Capping the rescue lane bought liveness at the price of a new hole: once a rescue close is
     * DISCARDED, the best-effort path has released nothing, and a transfer's stream is not the
     * bounded call's return value, so nothing else owns it — the reader and the writer both
     * deliberately leave the stream to their caller. If the parked transfer later returns, that
     * descriptor has no owner at all (Gate-4 round 3, High).
     *
     * Both cases below saturate the lane FIRST, so the rescue for the stream under test is
     * guaranteed to be dropped, and then assert the descriptor is still closed once its transfer
     * comes back — which only the `dispose` hook can do.
     */
    @Test
    fun anImportStreamIsClosedByDisposeEvenWhenItsRescueWasDiscarded() = runBlocking {
        val saturation = saturateTheRescueLane()
        try {
            val readLatch = ParkLatch()
            val stranded = ParkingInputStream(readLatch)
            rig.port.inputFactory = { stranded }

            assertParseFailure(ImportFailure.Timeout, previewOnce())
            readLatch.release()

            assertTrue(
                "the descriptor has no other owner once the rescue is dropped",
                rig.awaitUntil { stranded.closeCount >= 1 },
            )
        } finally {
            drain(saturation)
        }
    }

    @Test
    fun anExportSinkIsClosedByDisposeEvenWhenItsRescueWasDiscarded() = runBlocking {
        val saturation = saturateTheRescueLane()
        try {
            seedOneHighlight()
            val writeLatch = ParkLatch()
            val stranded = ParkingOutputStream(writeLatch)
            rig.port.outputFactory = { stranded }

            assertExportFailure(ImportFailure.Timeout, exportOnce())
            writeLatch.release()

            assertTrue(
                "the sink has no other owner once the rescue is dropped",
                rig.awaitUntil { stranded.closeCount >= 1 },
            )
            assertEquals("close-once still holds across dispose and cleanup", 1, stranded.closeCount)
        } finally {
            drain(saturation)
        }
    }

    /**
     * The same hole as the two cases above, at the OPEN step rather than the transfer — and the
     * one that survived a mutation until it was written. A late-arriving stream's only owner is
     * `dispose`, so if `dispose` merely DISPATCHES the close it inherits the discard, and the
     * plain late-dispose tests never notice because they run against an idle rescue lane.
     */
    @Test
    fun aLateOpenedInputStreamIsDisposedEvenWhenTheRescueLaneIsSaturated() = runBlocking {
        val saturation = saturateTheRescueLane()
        try {
            val late = TrackingInputStream(EMPTY_ENVELOPE.toByteArray())
            rig.port.parkAt = FakeSafPort.Site.OPEN_INPUT
            rig.port.inputFactory = { late }

            assertParseFailure(ImportFailure.Timeout, previewOnce())
            rig.port.latch.release()

            assertTrue("a late stream may not depend on a droppable close", rig.awaitUntil { late.closeCount >= 1 })
        } finally {
            drain(saturation)
        }
    }

    @Test
    fun aLateOpenedOutputStreamIsDisposedEvenWhenTheRescueLaneIsSaturated() = runBlocking {
        val saturation = saturateTheRescueLane()
        try {
            val late = TrackingOutputStream()
            rig.port.parkAt = FakeSafPort.Site.OPEN_OUTPUT
            rig.port.outputFactory = { late }

            assertExportFailure(ImportFailure.Timeout, exportOnce())
            rig.port.latch.release()

            assertTrue("a late sink may not depend on a droppable close", rig.awaitUntil { late.closeCount >= 1 })
        } finally {
            drain(saturation)
        }
    }

    /**
     * Releases a saturating latch AND waits for the parked rescue closes to actually return.
     * The lane is process-wide, so a test that leaves it saturated makes the NEXT test's rescue be
     * discarded — which is how one broken expectation cascaded into three failures once.
     */
    private fun drain(latch: ParkLatch) {
        latch.release()
        assertTrue("the rescue lane never drained", rig.awaitUntil { !latch.isParked })
    }

    /**
     * Fills every rescue slot with a close that never returns, so the NEXT submission is rejected
     * and discarded. Each round frees the ledger (release the read) while leaving its rescue stuck,
     * which is the only way to park more rescues than the ledger permits abandoned calls.
     */
    private suspend fun saturateTheRescueLane(): ParkLatch {
        val closeLatch = ParkLatch()
        // Every round has to LAND a rescue in the lane, and two paths race for the descriptor: the
        // dispatched rescue and the `dispose` that fires when the read returns. Waiting for the
        // rescue to be inside `close()` BEFORE releasing the read removes the race — without it a
        // round where `dispose` won closed on the job thread instead, occupying no lane slot and
        // leaving a saturation that never arrived.
        repeat(rig.cleanup.maxExpiryCloses) {
            val readLatch = ParkLatch()
            rig.port.inputFactory = { ParkingInputStream(readLatch, closeLatch = closeLatch) }
            assertParseFailure(ImportFailure.Timeout, previewOnce())
            assertTrue(
                "round $it never dispatched its rescue close",
                rig.awaitUntil { closeLatch.enteredCount >= it + 1 },
            )
            readLatch.release()
        }
        assertTrue("the lane is not actually saturated", closeLatch.isParked)
        return closeLatch
    }

    // ---- the budget can go WHILE we hold the descriptor -----------------------------------------

    @Test
    fun aBudgetSpentBetweenOpenAndReadRefusesBeforeReading() = runBlocking {
        exhaustTheInjectedBudget(IncomingImportCoordinator.MAX_ABANDONED_CALLS - 1)
        val closed = TrackingInputStream(EMPTY_ENVELOPE.toByteArray())
        rig.port.inputFactory = { closed }
        rig.port.onCall = { site -> if (site == FakeSafPort.Site.OPEN_INPUT) parkOneMoreCall() }

        assertParseFailure(ImportFailure.Busy, previewOnce())

        assertTrue("the descriptor we already held must not leak", rig.awaitUntil { closed.closeCount >= 1 })
    }

    // ---- late results own an fd nobody else will close ------------------------------------------

    @Test
    fun inputStreamProducedAfterTheDeadlineIsDisposed() = runBlocking {
        rig.port.parkAt = FakeSafPort.Site.OPEN_INPUT
        val late = TrackingInputStream("{}".toByteArray())
        rig.port.inputFactory = { late }

        assertParseFailure(ImportFailure.Timeout, previewOnce())
        assertEquals("nothing may be produced before the deadline", 0, rig.port.produced.size)

        // Only NOW does the provider hand back the stream — after the caller has walked away.
        rig.port.latch.release()
        assertTrue(
            "the late stream must be closed by the gate's dispose hook, not leaked",
            rig.awaitUntil { late.closeCount >= 1 },
        )
        assertTrue("the late stream was produced", rig.port.produced.contains(late))
        assertEquals("close-once: an attacker stream need not tolerate a second close", 1, late.closeCount)
    }

    @Test
    fun outputStreamProducedAfterTheDeadlineIsDisposed() = runBlocking {
        rig.port.parkAt = FakeSafPort.Site.OPEN_OUTPUT
        val late = TrackingOutputStream()
        rig.port.outputFactory = { late }

        assertExportFailure(ImportFailure.Timeout, exportOnce())
        assertEquals("nothing may be produced before the deadline", 0, rig.port.produced.size)

        rig.port.latch.release()
        assertTrue(
            "the late sink must be closed by the gate's dispose hook, not leaked",
            rig.awaitUntil { late.closeCount >= 1 },
        )
        assertEquals("close-once", 1, late.closeCount)
    }

    // ---- the budget is ONE app-wide ledger, injected --------------------------------------------

    @Test
    fun anExhaustedAbandonedBudgetRefusesImportBeforeTouchingTheProvider() = runBlocking {
        exhaustTheInjectedBudget()

        assertParseFailure(ImportFailure.Busy, previewOnce())
        assertEquals("admission precedes the provider call", 0, rig.port.metadataCallCount)
        assertEquals(0, rig.port.openInputCallCount)
    }

    @Test
    fun anExhaustedAbandonedBudgetRefusesExportBeforeTouchingTheProvider() = runBlocking {
        exhaustTheInjectedBudget()

        assertExportFailure(ImportFailure.Busy, exportOnce())
        assertEquals("admission precedes the provider call", 0, rig.port.openOutputCallCount)
    }

    @Test
    fun abandonmentIsCountedOnTheInjectedGateNotAPrivateOne() = runBlocking {
        rig.port.parkAt = FakeSafPort.Site.METADATA

        assertParseFailure(ImportFailure.Timeout, previewOnce())

        // Read from the instance the TEST owns and handed in. A controller that built its own gate
        // would leave this at zero while happily bounding itself against a second budget — which is
        // exactly the doubled parked-thread ceiling §8.5 forbids.
        assertTrue(
            "the injected gate must be the ledger the controller charges",
            rig.gate.abandonedCalls >= 1,
        )
    }

    // ---- helpers --------------------------------------------------------------------------------

    private fun previewOnce(): ImportParseResult = withoutWedging {
        rig.controller.preview(rig.uri, Fx.BOOK_A, BOOK_TITLE)
    }

    private fun exportOnce(): Result<Int> = withoutWedging {
        rig.controller.export(rig.uri, Fx.BOOK_A)
    }

    /**
     * Runs [body] on a DAEMON thread and refuses to wait for it past [WEDGE_TIMEOUT_MILLIS], so a
     * boundary that lost a bound reads as ONE failing assertion rather than as a hung suite.
     *
     * Neither obvious alternative works here, and both were measured:
     *  * `@Test(timeout = …)` is decoration under Robolectric — its runner builds its own statement
     *    and does not apply JUnit's timeout. With the annotation in place the unbounded-`query`
     *    mutant still ran to the 900s watchdog, leaving stale result XML that read like a pass.
     *  * `withTimeout` cannot express it either: a blocking provider call is immune to coroutine
     *    cancellation by construction — that IS the defect — so the enclosing coroutine cannot
     *    return until the call does.
     * A joined daemon thread survives both, and being a daemon it also cannot keep the test JVM
     * alive after the suite has reported.
     */
    private fun <T> withoutWedging(body: suspend () -> T): T {
        val outcome = AtomicReference<Result<T>>()
        val worker = Thread({ outcome.set(runCatching { runBlocking { body() } }) }, "wedge-guard")
        worker.isDaemon = true
        worker.start()
        worker.join(WEDGE_TIMEOUT_MILLIS)
        val result = outcome.get()
        assertNotNull(
            "the caller never returned within ${WEDGE_TIMEOUT_MILLIS}ms — the boundary is unbounded",
            result,
        )
        return result.getOrThrow()
    }

    private suspend fun seedOneHighlight() {
        rig.store.seedBook()
        rig.store.repo.restoreAnnotations(
            ApplierHarness.env(highlights = listOf(Fx.highlight(Fx.uuid(1)))),
            setOf(Fx.BOOK_A),
        )
    }

    /**
     * Fills the INJECTED gate's ledger with parked calls made directly on it, not via the
     * controller. The latch is released only in [tearDown] — releasing it here would self-heal the
     * budget before the controller ever sees it, and the assertion would pass for the wrong reason
     * (measured: it did, on the first run).
     */
    private suspend fun exhaustTheInjectedBudget(
        count: Int = IncomingImportCoordinator.MAX_ABANDONED_CALLS,
    ) = withContext(Dispatchers.Default) {
        repeat(count) {
            rig.gate.call(timeoutMillis = 1L, name = "test-park") { budgetLatch.park() }
        }
        assertTrue(
            "precondition: the ledger holds $count abandoned calls",
            rig.gate.abandonedCalls >= count,
        )
    }

    /**
     * Spends the LAST ledger slot from another thread, the way a second reader activity would —
     * this is the only way to reach a re-check that sits BETWEEN two of the controller's own
     * provider calls. Blocks until the count is visible, so the controller cannot race past it.
     */
    private fun parkOneMoreCall() {
        // A 1ms deadline: the call is charged to the ledger before `call` returns, so this is
        // synchronous and race-free rather than a hopeful poll.
        runBlocking { rig.gate.call(timeoutMillis = 1L, name = "test-park") { budgetLatch.park() } }
        assertTrue(
            "the ledger did not fill",
            rig.gate.abandonedCalls >= IncomingImportCoordinator.MAX_ABANDONED_CALLS,
        )
    }

    private inline fun timed(body: () -> Unit): Long {
        val start = System.nanoTime()
        body()
        return (System.nanoTime() - start) / 1_000_000L
    }

    /**
     * The GUARANTEE, stated as three facts: the caller waited its budget, it came back well inside
     * a human timescale, and the provider had still not returned when it did.
     */
    private fun assertAdvancedWhileParked(elapsedMillis: Long) {
        assertTrue(
            "must actually wait its budget, not short-circuit (was ${elapsedMillis}ms)",
            elapsedMillis >= ControllerRig.TIMEOUT_MILLIS,
        )
        assertTrue(
            "must return long before a user gives up (was ${elapsedMillis}ms)",
            elapsedMillis < LIVENESS_CEILING_MILLIS,
        )
        assertTrue(
            "the provider must STILL be parked — otherwise this proves nothing",
            rig.port.latch.isParked,
        )
        assertTrue("the abandoned call is on the ledger", rig.gate.abandonedCalls >= 1)
    }

    /** The budget is a ceiling, not a leak: it comes back when the provider finally returns. */
    private fun assertSelfHeals() {
        rig.port.latch.release()
        assertTrue(
            "abandonedCalls must return to 0 once the parked call completes " +
                "(stuck at ${rig.gate.abandonedCalls})",
            rig.awaitUntil { rig.gate.abandonedCalls == 0 },
        )
    }

    private fun assertParseFailure(expected: ImportFailure, actual: ImportParseResult) {
        assertEquals(ImportParseResult.Failed(expected), actual)
    }

    private fun assertExportFailure(expected: ImportFailure, actual: Result<Int>) {
        val error = actual.exceptionOrNull()
        assertTrue("expected a typed failure, got $actual", error is AnnotationImportFailedException)
        assertEquals(expected, (error as AnnotationImportFailedException).reason)
    }

    companion object {
        /** See [ParkLatch.releaseAll] — a timed-out test abandons its thread, latch and all. */
        @JvmStatic
        @AfterClass
        fun releaseAbandonedParks() = ParkLatch.releaseAll()

        const val BOOK_TITLE = "A Book"

        /** A well-formed, empty annotations envelope at the shipped schema version. */
        val EMPTY_ENVELOPE: String = BackupJson.encode(ApplierHarness.env())

        /** Generous: this bounds "the UI never wedges", not the deadline itself. */
        const val LIVENESS_CEILING_MILLIS = 10_000L

        /** How long [withoutWedging] waits before calling the boundary unbounded. */
        const val WEDGE_TIMEOUT_MILLIS = 20_000L
    }
}
