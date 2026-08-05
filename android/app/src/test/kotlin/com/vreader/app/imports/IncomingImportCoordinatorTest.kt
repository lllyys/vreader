// Purpose: feature #155 WI-4 — `IncomingImportCoordinator` (plan D6/D8/D9) and the
// `BoundedCallGate` primitive that closes D8's OPEN GAP for WI-5.
//
// The entry point this feeds is EXPORTED, so the load-bearing assertions are structural:
//
//   * QUEUE LIVENESS IS A GUARANTEE, NOT A HOPE. `livenessIsGuaranteed…` uses a stream whose
//     `read()` blocks forever and DELIBERATELY IGNORES `close()`, and asserts the worker
//     recorded Failed, released the slot and imported the NEXT item **while that read is still
//     parked** (`readReturned == false`). A test that only passed once `close()` unblocked the
//     read would be testing D8's *best-effort* tier and would go green on an implementation
//     that can wedge — so the blocked-ness is asserted explicitly, on a real daemon thread.
//   * TWO DISTINCT SCOPES, NEVER ONE. A single TestScope passes whether or not the caller's
//     cancellation leaks into the copy, so the caller scope (ImportActivity's lifecycleScope)
//     and `appScope` are separate objects and are cancelled separately.
//   * THE CAP IS PROCESS-WIDE. Slots are driven from two different caller scopes, not from one
//     `enqueue` call — a per-call cap would pass the latter and still let two concurrent
//     ImportActivity instances blow past it.
//   * ONE OUTCOME PER INPUT URI, IN ORDER — asserted on a mixed Ready/PreResolved batch by
//     count AND by position, and separately past the old 64-element buffer, because a dropping
//     buffer breaks the contract silently (Gate-4 round 1, High).
//   * OWNERSHIP — a recording stream asserts `closed` on every terminal path, including the
//     ones nobody thinks about: refused past the cap, timed out, and STILL QUEUED when the app
//     scope dies (Gate-4 round 1, High).
//   * THE WORKER IS UNKILLABLE. There is only one; an attacker-supplied stream that throws an
//     `Error` from `close()` must not take the queue with it.
//
// Virtual time is what makes the 5-minute/60-second bounds testable in milliseconds: the worker
// and the watchdog run on a `StandardTestDispatcher`, so their timeouts fire on the scheduler
// while a genuinely blocking read sits on a real thread. `advanceTimeBy` (not `advanceUntilIdle`)
// is used where a test must fire the STALL deadline WITHOUT also firing the total-import
// deadline — otherwise the stall tests would pass for the wrong reason.
//
// Fixtures are synthetic: a CI JVM unit test cannot read the gitignored `test-books/` tree, and
// every case here needs byte-exact or pathological stream behaviour no real book can provide (a
// read that never returns, an endless stream, a revoked grant, a `close()` that throws).
package com.vreader.app.imports

import android.net.Uri
import com.vreader.app.data.Book
import com.vreader.app.data.ImportException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.cancellation.CancellationException

@RunWith(RobolectricTestRunner::class)
class IncomingImportCoordinatorTest {

    @get:Rule
    val temp = TemporaryFolder()

    private val importer = FakeImporter()

    // ── ordering, relay, delivery ────────────────────────────────────────────────

    @Test
    fun `items import sequentially and every outcome reaches a LATE collector`() = runTest {
        val fixture = fixture()
        val items = listOf(
            fixture.readyItem("a.epub"),
            fixture.readyItem("b.epub"),
            fixture.readyItem("c.epub"),
        )
        fixture.coordinator.enqueue(items)
        testScheduler.runCurrent()

        // The collector starts only NOW — after every import already finished. A non-replaying
        // SharedFlow would have dropped all three.
        val outcomes = fixture.collectOutcomes()
        assertEquals(3, outcomes.size)
        assertTrue(outcomes.all { it is IncomingImportOutcome.Imported })
        assertEquals(listOf("a.epub", "b.epub", "c.epub"), importer.calls.map { it.displayName })
        assertEquals(0, fixture.coordinator.outstandingSlots)
    }

    @Test
    fun `a mixed Ready and PreResolved batch yields one outcome per input in input order`() = runTest {
        val fixture = fixture()
        val items = listOf(
            IncomingItem.PreResolved(IncomingImportOutcome.Unsupported("a.xyz")),
            fixture.readyItem("b.epub"),
            IncomingItem.PreResolved(IncomingImportOutcome.TooLarge),
            IncomingItem.PreResolved(IncomingImportOutcome.Unreadable),
            fixture.readyItem("e.epub"),
            IncomingItem.PreResolved(IncomingImportOutcome.Failed),
        )
        fixture.coordinator.enqueue(items)
        testScheduler.runCurrent()

        val outcomes = fixture.collectOutcomes()
        assertEquals(items.size, outcomes.size)
        assertEquals(IncomingImportOutcome.Unsupported("a.xyz"), outcomes[0])
        assertTrue(outcomes[1] is IncomingImportOutcome.Imported)
        assertEquals(IncomingImportOutcome.TooLarge, outcomes[2])
        assertEquals(IncomingImportOutcome.Unreadable, outcomes[3])
        assertTrue(outcomes[4] is IncomingImportOutcome.Imported)
        assertEquals(IncomingImportOutcome.Failed, outcomes[5])
    }

    @Test
    fun `more outcomes than any fixed buffer are all delivered, none dropped`() = runTest {
        val fixture = fixture()
        // Well past the 64-element default buffer. A DROP_OLDEST policy would silently destroy
        // the earliest outcomes and still report a successful send.
        val items = (1..OVERFLOW_BATCH).map {
            IncomingItem.PreResolved(IncomingImportOutcome.Unsupported("f$it.xyz"))
        }
        fixture.coordinator.enqueue(items)
        testScheduler.runCurrent()

        val outcomes = fixture.collectOutcomes()
        assertEquals(OVERFLOW_BATCH, outcomes.size)
        assertEquals(IncomingImportOutcome.Unsupported("f1.xyz"), outcomes.first())
        assertEquals(IncomingImportOutcome.Unsupported("f$OVERFLOW_BATCH.xyz"), outcomes.last())
    }

    @Test
    fun `undelivered outcomes are BOUNDED, keeping the oldest, and never stall the worker`() = runTest {
        val fixture = fixture()
        val ceiling = IncomingImportCoordinator.MAX_PENDING_OUTCOMES
        // An exported entry point can be launched in a loop; with no collector this must not grow
        // without limit. Past the bound the contract degrades EXPLICITLY, and only that far.
        fixture.coordinator.enqueue(
            (1..ceiling + 100).map { IncomingItem.PreResolved(IncomingImportOutcome.Unsupported("f$it.xyz")) },
        )
        testScheduler.runCurrent()
        // ... and the worker is still alive behind all of that.
        fixture.coordinator.enqueue(listOf(fixture.readyItem("after.epub")))
        testScheduler.runCurrent()

        val outcomes = fixture.collectOutcomes()
        assertEquals(ceiling, outcomes.size)
        assertEquals("the OLDEST are kept", IncomingImportOutcome.Unsupported("f1.xyz"), outcomes.first())
        assertEquals("the import still ran", 1, importer.calls.size)
        assertEquals(0, fixture.coordinator.outstandingSlots)
    }

    @Test
    fun `concurrent callers can never hold more than MAX_IN_FLIGHT slots at once`() = runTest {
        // The other admission tests are single-threaded; production `appScope` is
        // Dispatchers.Default and ImportActivity instances are genuinely concurrent.
        val coordinator = fixture().coordinator
        val peak = AtomicInteger(0)
        val held = AtomicInteger(0)
        val start = CountDownLatch(1)
        val threads = (1..8).map {
            Thread {
                start.await()
                repeat(200) {
                    val slot = coordinator.acquireSlot()
                    if (slot != null) {
                        // The increment stays OUTSIDE updateAndGet: that lambda re-runs on CAS
                        // contention, so a side effect inside it would count the same slot twice.
                        val depth = held.incrementAndGet()
                        peak.updateAndGet { p -> maxOf(p, depth) }
                        held.decrementAndGet()
                        slot.release()
                        slot.release()          // the idempotent double release, under contention
                    }
                }
            }.apply { isDaemon = true; start() }
        }
        start.countDown()
        threads.forEach { it.join(30_000) }

        assertTrue("the cap held under contention: peak=${peak.get()}", peak.get() <= IncomingImportCoordinator.MAX_IN_FLIGHT)
        assertEquals("and every slot came back", 0, coordinator.outstandingSlots)
    }

    @Test
    fun `re-importing the same book reports wasAlreadyPresent and adds no second row`() = runTest {
        val fixture = fixture()
        fixture.coordinator.enqueue(listOf(fixture.readyItem("dup.epub")))
        testScheduler.runCurrent()
        fixture.coordinator.enqueue(listOf(fixture.readyItem("dup.epub")))
        testScheduler.runCurrent()

        val outcomes = fixture.collectOutcomes().filterIsInstance<IncomingImportOutcome.Imported>()
        assertEquals(2, outcomes.size)
        assertFalse("first import is not a duplicate", outcomes[0].wasAlreadyPresent)
        assertTrue("second import IS a duplicate", outcomes[1].wasAlreadyPresent)
        assertEquals(outcomes[0].key, outcomes[1].key)
        assertEquals("one library row for one key", 1, importer.library.size)
    }

    @Test
    fun `the pre-capped sourceUri is passed to the importer VERBATIM`() = runTest {
        val fixture = fixture()
        // A hostile provider's URI, longer than the cap. `PendingImport` carries the
        // already-capped value; re-deriving it from `uri.toString()` would silently discard the
        // cap and persist the unbounded string (r4 M1).
        val uri = Uri.parse("content://provider/" + "a".repeat(4000))
        val capped = uri.toString().take(IncomingBookResolver.MAX_SOURCE_URI_CHARS)
        fixture.coordinator.enqueue(listOf(fixture.readyItem("long.epub", uri = uri, sourceUri = capped)))
        testScheduler.runCurrent()

        assertEquals(capped, importer.calls.single().sourceUri)
        assertEquals(IncomingBookResolver.MAX_SOURCE_URI_CHARS, importer.calls.single().sourceUri.length)
        assertNotEquals(uri.toString(), importer.calls.single().sourceUri)
    }

    // ── scopes: two of them, never conflated ─────────────────────────────────────

    @Test
    fun `cancelling the CALLER scope does not cancel an in-flight copy`() = runTest {
        val fixture = fixture()
        val callerScope = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        val gate = CompletableDeferred<Unit>()
        importer.gate = gate
        val item = fixture.readyItem("survives.epub")

        callerScope.launch { fixture.coordinator.enqueue(listOf(item)) }
        testScheduler.runCurrent()
        assertEquals("the copy must be in flight before we cancel", 1, importer.calls.size)

        callerScope.cancel()          // ImportActivity finished / was destroyed
        gate.complete(Unit)
        testScheduler.runCurrent()

        val outcomes = fixture.collectOutcomes()
        assertEquals(1, outcomes.size)
        assertTrue(outcomes.single() is IncomingImportOutcome.Imported)
        assertEquals(0, fixture.coordinator.outstandingSlots)
    }

    @Test
    fun `cancelling appScope DOES cancel an in-flight copy`() = runTest {
        val fixture = fixture()
        val gate = CompletableDeferred<Unit>()
        importer.gate = gate
        val stream = RecordingStream(bytes(64))

        fixture.coordinator.enqueue(listOf(fixture.readyItem("cancelled.epub", stream = stream)))
        testScheduler.runCurrent()
        assertEquals(1, importer.calls.size)

        fixture.appScope.cancel()
        gate.complete(Unit)
        testScheduler.runCurrent()

        assertTrue("the stream is still released", stream.closed)
        assertEquals("the slot still comes back", 0, fixture.coordinator.outstandingSlots)
    }

    @Test
    fun `cancelling appScope also releases the items still QUEUED behind the running one`() = runTest {
        val fixture = fixture()
        importer.gate = CompletableDeferred()          // item 1 never finishes
        val streams = List(3) { RecordingStream(bytes(32)) }
        fixture.coordinator.enqueue(streams.mapIndexed { i, s -> fixture.readyItem("q$i.epub", stream = s) })
        testScheduler.runCurrent()
        assertEquals("only the first is running; two are queued", 1, importer.calls.size)
        assertEquals(3, fixture.coordinator.outstandingSlots)

        fixture.appScope.cancel()
        testScheduler.runCurrent()

        assertTrue("a queued item's fd is not the app's to strand", streams.all { it.closed })
        assertEquals("and its slot is not held forever", 0, fixture.coordinator.outstandingSlots)
    }

    @Test
    fun `enqueueing after appScope died closes the stream instead of stranding it`() = runTest {
        val fixture = fixture()
        fixture.appScope.cancel()
        testScheduler.runCurrent()

        val stream = RecordingStream(bytes(32))
        val late = fixture.readyItem("late.epub", stream = stream)
        fixture.coordinator.enqueue(listOf(late))

        assertTrue("no worker will ever see it", stream.closed)
        assertEquals(0, fixture.coordinator.outstandingSlots)
    }

    // ── process-wide sequencing and admission ────────────────────────────────────

    @Test
    fun `sequencing holds ACROSS concurrent callers, not merely within one enqueue`() = runTest {
        val fixture = fixture()
        val callerA = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        val callerB = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        val batchA = listOf(fixture.readyItem("a1.epub"), fixture.readyItem("a2.epub"))
        val batchB = listOf(fixture.readyItem("b1.epub"), fixture.readyItem("b2.epub"))

        callerA.launch { fixture.coordinator.enqueue(batchA) }
        callerB.launch { fixture.coordinator.enqueue(batchB) }
        testScheduler.runCurrent()

        assertFalse("two imports must never overlap", importer.overlapped.get())
        assertEquals(4, fixture.collectOutcomes().size)
        assertEquals(4, importer.calls.size)
    }

    @Test
    fun `MAX_IN_FLIGHT slots are process-wide and every terminal outcome returns exactly one`() = runTest {
        val fixture = fixture()
        val coordinator = fixture.coordinator
        val half = IncomingImportCoordinator.MAX_IN_FLIGHT / 2
        // Two "ImportActivity instances" competing for the ONE process-wide pool.
        val callerA = (1..half).map { fixture.readyItem("a$it.epub") }
        val callerB = (1..half).map { fixture.readyItem("b$it.epub") }
        assertEquals(IncomingImportCoordinator.MAX_IN_FLIGHT, coordinator.outstandingSlots)
        assertNull("the 21st concurrent open is refused", coordinator.acquireSlot())

        coordinator.enqueue(callerA)
        coordinator.enqueue(callerB)
        testScheduler.runCurrent()

        assertEquals(IncomingImportCoordinator.MAX_IN_FLIGHT, fixture.collectOutcomes().size)
        assertEquals("every terminal outcome released its slot", 0, coordinator.outstandingSlots)
        assertNotNull("the pool is usable again", coordinator.acquireSlot())
    }

    @Test
    fun `releasing a slot twice returns ONE permit, not two`() = runTest {
        val coordinator = fixture().coordinator
        val first = checkNotNull(coordinator.acquireSlot())
        checkNotNull(coordinator.acquireSlot())
        assertEquals(2, coordinator.outstandingSlots)

        first.release()
        first.release()          // the `finally` of a caller that also transferred ownership

        assertEquals("a double release must not raise the cap for everyone else", 1, coordinator.outstandingSlots)
    }

    @Test
    fun `an item beyond MAX_IN_FLIGHT is closed, relayed as Failed, and gives its slot back`() = runTest {
        val fixture = fixture()
        val gate = CompletableDeferred<Unit>()
        importer.gate = gate
        val overflow = RecordingStream(bytes(8))

        val accepted = (1..IncomingImportCoordinator.MAX_IN_FLIGHT).map { fixture.readyItem("q$it.epub") }
        fixture.coordinator.enqueue(accepted)
        testScheduler.runCurrent()
        assertNull("the pool is exhausted", fixture.coordinator.acquireSlot())

        // A caller that enqueues anyway, with a slot it did not get from the coordinator: the
        // queue-depth guard is the defence in depth behind the slots.
        fixture.coordinator.enqueue(listOf(IncomingItem.Ready(pending("over.epub", overflow), ImportSlot {})))

        assertTrue("a rejected item's stream is closed immediately", overflow.closed)
        assertEquals("and it never reaches the importer", 1, importer.calls.size)
        gate.complete(Unit)
        testScheduler.runCurrent()

        val outcomes = fixture.collectOutcomes()
        assertEquals(IncomingImportCoordinator.MAX_IN_FLIGHT + 1, outcomes.size)
        assertEquals(0, fixture.coordinator.outstandingSlots)
    }

    @Test
    fun `abandoned calls are bounded, refuse admission at the ceiling, and self-heal`() = runTest {
        val fixture = fixture()
        val gate = CompletableDeferred<Unit>()
        importer.gate = gate                       // nothing ever finishes
        val items = (1..IncomingImportCoordinator.MAX_ABANDONED_CALLS).map { fixture.readyItem("stuck$it.epub") }
        fixture.coordinator.enqueue(items)
        testScheduler.advanceUntilIdle()           // every item hits its total-import deadline

        assertEquals("the queue drained regardless", items.size, fixture.collectOutcomes().size)
        assertEquals("slots came back", 0, fixture.coordinator.outstandingSlots)
        assertEquals(
            IncomingImportCoordinator.MAX_ABANDONED_CALLS,
            fixture.coordinator.boundedCalls.abandonedCalls,
        )
        assertNull("a pile of parked reads must not be recyclable into more", fixture.coordinator.acquireSlot())

        gate.complete(Unit)                        // the providers finally let go
        testScheduler.advanceUntilIdle()

        assertEquals(0, fixture.coordinator.boundedCalls.abandonedCalls)
        assertNotNull("capacity returns on its own", fixture.coordinator.acquireSlot())
    }

    // ── D8: the GUARANTEE ────────────────────────────────────────────────────────

    @Test
    fun `liveness is GUARANTEED - a read that blocks forever and ignores close cannot wedge the queue`() = runTest {
        // The first item's copy runs on a REAL thread so its read genuinely parks; every later
        // item runs on the scheduler so the assertions stay deterministic.
        val fixture = fixture(copyContextFactory = firstOnARealThread())
        val wedged = ForeverBlockingStream(honoursClose = false)
        val items = listOf(fixture.readyItem("wedged.epub", stream = wedged), fixture.readyItem("next.epub"))
        fixture.coordinator.enqueue(items)

        testScheduler.advanceUntilIdle()

        val outcomes = fixture.collectOutcomes()
        assertEquals(2, outcomes.size)
        assertEquals(IncomingImportOutcome.Failed, outcomes[0])
        assertTrue("the worker advanced to the NEXT item", outcomes[1] is IncomingImportOutcome.Imported)
        assertEquals("the abandoned item's slot came back", 0, fixture.coordinator.outstandingSlots)
        // THE point of this test: the guarantee held while the call is STILL blocked. If liveness
        // had depended on close() unblocking the read, this would be true.
        assertFalse("the blocked read has NOT returned", wedged.readReturned.get())
        assertTrue("close() was attempted (best-effort tier)", wedged.closeAttempts.get() > 0)
    }

    @Test
    fun `the stall watchdog closes a cooperative stream and the worker proceeds`() = runTest {
        val fixture = fixture(copyContextFactory = firstOnARealThread())
        val stalled = ForeverBlockingStream(honoursClose = true)
        val items = listOf(fixture.readyItem("stalled.epub", stream = stalled), fixture.readyItem("after.epub"))
        fixture.coordinator.enqueue(items)
        testScheduler.runCurrent()

        // Only the STALL deadline — not the 5-minute total. Firing both would let this test pass
        // on the total timeout and prove nothing about the watchdog.
        testScheduler.advanceTimeBy(STALL_MS + 1)
        assertTrue("the parked read was released", stalled.awaitReadFailed())

        val outcomes = fixture.awaitOutcomes(2)
        assertEquals(2, outcomes.size)
        assertEquals(IncomingImportOutcome.Failed, outcomes[0])
        assertTrue(outcomes[1] is IncomingImportOutcome.Imported)
    }

    @Test
    fun `a timeout yields Failed with the stream closed and the slot returned`() = runTest {
        val fixture = fixture(copyContextFactory = { dedicatedThreadDispatcher(it) })
        val wedged = ForeverBlockingStream(honoursClose = false)
        fixture.coordinator.enqueue(listOf(fixture.readyItem("timeout.epub", stream = wedged)))
        testScheduler.advanceUntilIdle()

        assertEquals(listOf(IncomingImportOutcome.Failed), fixture.collectOutcomes())
        assertTrue("the coordinator closed the stream it owned", wedged.closeAttempts.get() > 0)
        assertEquals(0, fixture.coordinator.outstandingSlots)
        assertEquals("no .part is left behind", 0, partFiles().size)
    }

    // ── size bounds, failure mapping, ownership ──────────────────────────────────

    @Test
    fun `an undeclared oversize stream is stopped by the post-open counting guard`() = runTest {
        val fixture = fixture(maxImportBytes = 4_096)
        val stream = RecordingStream(bytes(16_384))
        // declaredSize is null: ImportActivity's pre-open preflight had nothing to reject on.
        fixture.coordinator.enqueue(
            listOf(fixture.readyItem("lying.epub", stream = stream, declaredSize = null)),
        )
        testScheduler.runCurrent()

        assertEquals(listOf(IncomingImportOutcome.TooLarge), fixture.collectOutcomes())
        assertTrue(stream.closed)
    }

    @Test
    fun `an endless stream is stopped in bounded time`() = runTest {
        val fixture = fixture(maxImportBytes = 64 * 1024)
        val endless = EndlessStream()
        fixture.coordinator.enqueue(
            listOf(fixture.readyItem("endless.epub", stream = endless, declaredSize = null)),
        )
        testScheduler.runCurrent()

        assertEquals(listOf(IncomingImportOutcome.TooLarge), fixture.collectOutcomes())
        assertTrue(endless.bytesServed.get() <= 64 * 1024 + 8192)
        assertTrue(endless.closed.get())
    }

    @Test
    fun `an UnsupportedFormat from the importer maps to Unsupported and closes the stream`() = runTest {
        val fixture = fixture()
        val stream = RecordingStream(bytes(32))
        importer.failAt[0] = ImportException.UnsupportedFormat("weird.bin")
        fixture.coordinator.enqueue(listOf(fixture.readyItem("weird.bin", stream = stream)))
        testScheduler.runCurrent()

        assertEquals(listOf(IncomingImportOutcome.Unsupported("weird.bin")), fixture.collectOutcomes())
        assertTrue(stream.closed)
    }

    @Test
    fun `a revoked grant mid-copy maps to Failed and leaves no part file`() = runTest {
        val fixture = fixture()
        val stream = RecordingStream(bytes(32))
        importer.failAt[0] = SecurityException("Permission Denial: reading from a revoked grant")
        fixture.coordinator.enqueue(listOf(fixture.readyItem("revoked.epub", stream = stream)))
        testScheduler.runCurrent()

        assertEquals(listOf(IncomingImportOutcome.Failed), fixture.collectOutcomes())
        assertTrue(stream.closed)
        assertEquals(0, partFiles().size)
    }

    @Test
    fun `one failing item does not stop the items around it`() = runTest {
        val fixture = fixture()
        importer.failAt[1] = IOException("disk went away")
        val streams = List(3) { RecordingStream(bytes(32)) }
        fixture.coordinator.enqueue(streams.mapIndexed { i, s -> fixture.readyItem("i$i.epub", stream = s) })
        testScheduler.runCurrent()

        val outcomes = fixture.collectOutcomes()
        assertEquals(3, outcomes.size)
        assertTrue(outcomes[0] is IncomingImportOutcome.Imported)
        assertEquals(IncomingImportOutcome.Failed, outcomes[1])
        assertTrue(outcomes[2] is IncomingImportOutcome.Imported)
        assertTrue("every stream released on every path", streams.all { it.closed })
    }

    @Test
    fun `a stream whose close throws a non-fatal Error does not kill the single worker`() = runTest {
        val fixture = fixture()
        val hostile = HostileCloseStream { AssertionError("hostile close") }
        fixture.coordinator.enqueue(
            listOf(fixture.readyItem("hostile.epub", stream = hostile), fixture.readyItem("after.epub")),
        )
        testScheduler.runCurrent()

        val outcomes = fixture.collectOutcomes()
        assertTrue("close() was attempted", hostile.closeAttempts.get() > 0)
        assertEquals("the queue survived it", 2, outcomes.size)
        assertTrue("and the NEXT item still imported", outcomes[1] is IncomingImportOutcome.Imported)
        assertEquals(0, fixture.coordinator.outstandingSlots)
    }

    @Test
    fun `a stream whose close throws CancellationException does not kill the single worker`() = runTest {
        // The nastiest shape: from a NON-SUSPENDING cleanup path this is just a throwable the
        // provider chose, but a cleanup that rethrows "cancellation" unconditionally would
        // mistake it for its own coroutine dying and take the whole queue with it.
        val fixture = fixture()
        val hostile = HostileCloseStream { CancellationException("provider says cancelled") }
        fixture.coordinator.enqueue(
            listOf(fixture.readyItem("hostile.epub", stream = hostile), fixture.readyItem("after.epub")),
        )
        testScheduler.runCurrent()

        val outcomes = fixture.collectOutcomes()
        assertTrue("close() was attempted", hostile.closeAttempts.get() > 0)
        assertEquals("the queue survived it", 2, outcomes.size)
        assertTrue("and the NEXT item still imported", outcomes[1] is IncomingImportOutcome.Imported)
        assertEquals(0, fixture.coordinator.outstandingSlots)
    }

    @Test
    fun `a queued stream throwing from close at shutdown still releases the items behind it`() = runTest {
        val fixture = fixture()
        importer.gate = CompletableDeferred()               // item 1 never finishes
        val hostile = HostileCloseStream { AssertionError("hostile close") }
        val trailing = List(2) { RecordingStream(bytes(32)) }
        fixture.coordinator.enqueue(
            listOf(fixture.readyItem("running.epub")) +
                listOf(fixture.readyItem("hostile.epub", stream = hostile)) +
                trailing.mapIndexed { i, s -> fixture.readyItem("t$i.epub", stream = s) },
        )
        testScheduler.runCurrent()

        fixture.appScope.cancel()
        testScheduler.runCurrent()

        assertTrue("the hostile item was reached", hostile.closeAttempts.get() > 0)
        assertTrue("one bad close must not strand the queue behind it", trailing.all { it.closed })
        assertEquals("and every slot came back", 0, fixture.coordinator.outstandingSlots)
    }

    // ── the .part sweep ──────────────────────────────────────────────────────────

    @Test
    fun `sweepStaleTempFiles deletes an aged part file and leaves a fresh one`() = runTest {
        val fixture = fixture()
        val aged = File(booksDir(), "import-old.part").apply { writeText("x") }
        val fresh = File(booksDir(), "import-new.part").apply { writeText("x") }
        val keep = File(booksDir(), "epub_sha_12.epub").apply { writeText("x") }
        assertTrue(aged.setLastModified(System.currentTimeMillis() - 2 * 60 * 60 * 1000))

        fixture.coordinator.sweepStaleTempFiles()

        assertFalse("an hours-old temp is swept", aged.exists())
        assertTrue("a live import's temp is never touched", fresh.exists())
        assertTrue("a real artifact is never touched", keep.exists())
    }

    // ── the bounded-call primitive (WI-5 wraps peek / resolveAndOpen in this) ─────

    @Test
    fun `a bounded call returns the value when the block completes`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        val gate = BoundedCallGate(scope, StandardTestDispatcher(testScheduler))
        var result: BoundedCall<String>? = null
        scope.launch { result = gate.call(timeoutMillis = 1_000) { "ok" } }
        testScheduler.runCurrent()
        assertEquals(BoundedCall.Completed("ok"), result)
        assertEquals(0, gate.abandonedCalls)
    }

    @Test
    fun `a bounded call reports the block's failure`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        val gate = BoundedCallGate(scope, StandardTestDispatcher(testScheduler))
        var result: BoundedCall<String>? = null
        scope.launch { result = gate.call(timeoutMillis = 1_000) { throw IOException("nope") } }
        testScheduler.runCurrent()
        assertTrue(result is BoundedCall.Failed)
        assertTrue((result as BoundedCall.Failed).error is IOException)
    }

    @Test
    fun `a bounded call returns TimedOut while the blocked call is STILL running`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        val gate = BoundedCallGate(scope, StandardTestDispatcher(testScheduler)) { dedicatedThreadDispatcher(it) }
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val returned = AtomicBoolean(false)
        var result: BoundedCall<String>? = null

        scope.launch {
            result = gate.call(timeoutMillis = 60_000) {
                entered.countDown()
                release.await()                 // never released within the test
                returned.set(true)
                "late"
            }
        }
        testScheduler.runCurrent()
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        testScheduler.advanceTimeBy(60_001)
        testScheduler.runCurrent()

        assertEquals(BoundedCall.TimedOut, result)
        assertFalse("the caller advanced while the call is still parked", returned.get())
        assertEquals("and the parked call is accounted for", 1, gate.abandonedCalls)
    }

    @Test
    fun `a late result is DISPOSED, never leaked`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        val gate = BoundedCallGate(scope, StandardTestDispatcher(testScheduler)) { dedicatedThreadDispatcher(it) }
        val entered = CountDownLatch(1)
        val release = CountDownLatch(1)
        val late = RecordingStream(bytes(8))
        val disposed = CountDownLatch(1)
        var result: BoundedCall<InputStream>? = null

        scope.launch {
            result = gate.call(
                timeoutMillis = 30_000,
                dispose = { it.close(); disposed.countDown() },
            ) {
                entered.countDown()
                release.await()
                late                          // an InputStream produced AFTER the timeout
            }
        }
        testScheduler.runCurrent()
        assertTrue(entered.await(5, TimeUnit.SECONDS))
        testScheduler.advanceTimeBy(30_001)
        testScheduler.runCurrent()
        assertEquals(BoundedCall.TimedOut, result)
        assertFalse("nothing to dispose yet", late.closed)

        release.countDown()                   // the abandoned call finally finishes
        assertTrue("the orphaned stream was disposed", disposed.await(5, TimeUnit.SECONDS))
        assertTrue("an fd nobody owns is a leak on an exported entry point", late.closed)
    }

    // ── fixtures ─────────────────────────────────────────────────────────────────

    private fun booksDir(): File = temp.root.resolve("books").apply { mkdirs() }

    private fun partFiles(): List<File> =
        booksDir().listFiles()?.filter { it.name.startsWith("import-") && it.name.endsWith(".part") } ?: emptyList()

    /** The first copy on a real (parking-capable) thread, the rest on the scheduler. */
    private fun TestScope.firstOnARealThread(): (String) -> CoroutineDispatcher {
        val used = AtomicBoolean(false)
        return { name ->
            if (used.compareAndSet(false, true)) dedicatedThreadDispatcher(name)
            else StandardTestDispatcher(testScheduler)
        }
    }

    private class Fixture(
        val coordinator: IncomingImportCoordinator,
        val appScope: CoroutineScope,
        private val scope: TestScope,
    ) {
        private val collected = mutableListOf<IncomingImportOutcome>()

        /** Collects everything buffered so far — deliberately started LATE (D9). Accumulates
         *  across calls, so polling never discards an outcome it already drained. */
        fun collectOutcomes(): List<IncomingImportOutcome> {
            val job = appScope.launch { coordinator.outcomes.collect { collected += it } }
            scope.testScheduler.runCurrent()
            job.cancel()
            return collected.toList()
        }

        /** For the cases whose work genuinely runs on a REAL thread: virtual time cannot order a
         *  real read's completion against the scheduler, so poll (bounded) instead of assuming
         *  one `runCurrent` lands after it. */
        fun awaitOutcomes(expected: Int): List<IncomingImportOutcome> {
            repeat(POLL_ATTEMPTS) {
                val out = collectOutcomes()
                if (out.size >= expected) return out
                Thread.sleep(POLL_INTERVAL_MS)
            }
            return collectOutcomes()
        }
    }

    private fun TestScope.fixture(
        importTimeoutMillis: Long = IMPORT_MS,
        stallTimeoutMillis: Long = STALL_MS,
        maxImportBytes: Long = IncomingImportCoordinator.MAX_IMPORT_BYTES,
        copyContextFactory: (String) -> CoroutineDispatcher = { StandardTestDispatcher(testScheduler) },
    ): Fixture {
        val appScope = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        importer.booksDir = booksDir()
        val coordinator = IncomingImportCoordinator(
            importStream = importer,
            booksDir = booksDir(),
            appScope = appScope,
            blockingLane = StandardTestDispatcher(testScheduler),
            importTimeoutMillis = importTimeoutMillis,
            stallTimeoutMillis = stallTimeoutMillis,
            maxImportBytes = maxImportBytes,
            copyContextFactory = copyContextFactory,
        )
        return Fixture(coordinator, appScope, this)
    }

    private fun pending(
        displayName: String,
        stream: InputStream,
        uri: Uri = Uri.parse("content://provider/$displayName"),
        sourceUri: String = uri.toString().take(IncomingBookResolver.MAX_SOURCE_URI_CHARS),
        format: BookFormat = BookFormat.epub,
        declaredSize: Long? = 32L,
    ) = PendingImport(uri, displayName, format, sourceUri, declaredSize, stream)

    /** Builds a Ready item, reserving its slot the way WI-5 must — BEFORE the stream exists. */
    private fun Fixture.readyItem(
        displayName: String,
        uri: Uri = Uri.parse("content://provider/$displayName"),
        sourceUri: String = uri.toString().take(IncomingBookResolver.MAX_SOURCE_URI_CHARS),
        format: BookFormat = BookFormat.epub,
        declaredSize: Long? = 32L,
        stream: InputStream = RecordingStream(bytes(32)),
    ): IncomingItem.Ready = IncomingItem.Ready(
        pending(displayName, stream, uri, sourceUri, format, declaredSize),
        checkNotNull(coordinator.acquireSlot()) { "no slot" },
    )

    private fun bytes(n: Int) = ByteArray(n) { (it % 251).toByte() }

    /** Stands in for `BookImporter.importStream`: it CONSUMES the stream (so the counting guard
     *  is exercised), records the exact arguments, and models the library as a key-addressed map
     *  plus an on-disk artifact — the two things `wasAlreadyPresent` actually depends on. It
     *  deliberately does NOT close the stream, so every closure assertion is about the
     *  coordinator's ownership, not the fake's politeness. */
    private class FakeImporter : ImportStreamPort {
        data class Call(val sourceUri: String, val displayName: String, val format: BookFormat)

        lateinit var booksDir: File
        val calls = java.util.Collections.synchronizedList(mutableListOf<Call>())
        val library = java.util.Collections.synchronizedMap(mutableMapOf<String, Book>())
        val failAt = mutableMapOf<Int, Throwable>()
        val overlapped = AtomicBoolean(false)
        var gate: CompletableDeferred<Unit>? = null
        private val busy = AtomicBoolean(false)

        override suspend fun importStream(
            sourceUri: String,
            displayName: String,
            input: InputStream,
            format: BookFormat,
        ): Book {
            if (!busy.compareAndSet(false, true)) overlapped.set(true)
            try {
                val index: Int
                synchronized(calls) {
                    calls.add(Call(sourceUri, displayName, format))
                    index = calls.size - 1
                }
                gate?.await()
                failAt[index]?.let { throw it }
                val buffer = ByteArray(8192)
                var total = 0L
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    total += n
                }
                val key = "${format.name}:${displayName.hashCode()}:$total"
                val artifact = File(booksDir, key.replace(Regex("[^A-Za-z0-9._-]"), "_"))
                artifact.parentFile?.mkdirs()
                artifact.writeText("artifact")
                val book = Book(
                    fingerprintKey = key,
                    title = displayName,
                    originalFormat = format,
                    contentSHA256 = "sha",
                    fileByteCount = total,
                    localFilePath = artifact.absolutePath,
                    sourceUri = sourceUri,
                    addedAt = 1L,
                )
                library[key] = book
                return book
            } finally {
                busy.set(false)
            }
        }
    }

    /** Records closure; otherwise an ordinary in-memory stream. */
    private class RecordingStream(data: ByteArray) : FilterInputStream(ByteArrayInputStream(data)) {
        @Volatile var closed = false
            private set

        override fun close() {
            closed = true
            super.close()
        }
    }

    /** Throws whatever a hostile provider might throw from close() — an `Error` or, nastier, a
     *  `CancellationException`, which a naive cleanup would mistake for ITS OWN coroutine being
     *  cancelled and rethrow, killing the single worker. */
    private class HostileCloseStream(private val thrown: () -> Throwable) : InputStream() {
        val closeAttempts = AtomicInteger(0)
        private var remaining = 32

        override fun read(): Int = if (remaining-- > 0) 0x41 else -1

        override fun close() {
            closeAttempts.incrementAndGet()
            throw thrown()
        }
    }

    /** Never returns from `read()`. [honoursClose] decides whether `close()` releases it — the
     *  difference between D8's best-effort tier and the guarantee. */
    private class ForeverBlockingStream(private val honoursClose: Boolean) : InputStream() {
        private val gate = CountDownLatch(1)
        private val readFailed = CountDownLatch(1)
        val readReturned = AtomicBoolean(false)
        val closeAttempts = AtomicInteger(0)

        override fun read(): Int = read(ByteArray(1), 0, 1)

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            gate.await()
            readFailed.countDown()
            if (honoursClose) throw IOException("stream closed")
            readReturned.set(true)
            return -1
        }

        override fun close() {
            closeAttempts.incrementAndGet()
            if (honoursClose) gate.countDown()
        }

        fun awaitReadFailed(): Boolean = readFailed.await(5, TimeUnit.SECONDS)
    }

    /** Always has more bytes — the "infinite stream" the counting guard must stop. */
    private class EndlessStream : InputStream() {
        val bytesServed = AtomicInteger(0)
        val closed = AtomicBoolean(false)

        override fun read(): Int {
            bytesServed.incrementAndGet()
            return 0x41
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            b.fill(0x41, off, off + len)
            bytesServed.addAndGet(len)
            return len
        }

        override fun close() {
            closed.set(true)
        }
    }

    private companion object {
        const val IMPORT_MS = 5L * 60 * 1000
        const val STALL_MS = 60L * 1000
        const val OVERFLOW_BATCH = 200
        const val POLL_ATTEMPTS = 500
        const val POLL_INTERVAL_MS = 10L
    }
}
