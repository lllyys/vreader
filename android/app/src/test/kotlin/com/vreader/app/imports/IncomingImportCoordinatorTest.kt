// Purpose: feature #155 WI-4 — `IncomingImportCoordinator` (plan D6/D8/D9) and the
// `BoundedCallGate` primitive that closes D8's OPEN GAP for WI-5.
//
// The entry point this feeds is EXPORTED, so the load-bearing assertions are structural:
//
//   * QUEUE LIVENESS IS A GUARANTEE, NOT A HOPE. `livenessIsGuaranteed…` uses a stream
//     whose `read()` blocks forever and DELIBERATELY IGNORES `close()`, and asserts the
//     worker recorded Failed, released the permit and imported the NEXT item **while
//     that read is still parked** (`readReturned == false`). A test that only passed
//     once `close()` unblocked the read would be testing D8's *best-effort* tier and
//     would go green on an implementation that can wedge — so the blocked-ness is
//     asserted explicitly, at the end, on a real (daemon) thread.
//   * TWO DISTINCT SCOPES, NEVER ONE. A single TestScope passes whether or not the
//     caller's cancellation leaks into the copy, so the caller scope (ImportActivity's
//     lifecycleScope) and `appScope` are separate objects and are cancelled separately.
//   * THE CAP IS PROCESS-WIDE. Permits are driven from two different caller scopes, not
//     from one `enqueue` call — a per-call cap would pass the latter and still let two
//     concurrent ImportActivity instances blow past it.
//   * ONE OUTCOME PER INPUT URI, IN ORDER — asserted on a mixed Ready/PreResolved batch
//     by count AND by position, not by "an Unsupported appeared somewhere".
//   * OWNERSHIP — a recording stream asserts `closed` on every terminal path, including
//     the ones nobody thinks about (rejected past the cap, timed out).
//
// Virtual time is what makes the 5-minute/60-second bounds testable in milliseconds:
// the worker and the watchdog run on a `StandardTestDispatcher`, so their timeouts fire
// on the scheduler while a genuinely blocking read sits on a real thread. `advanceTimeBy`
// (not `advanceUntilIdle`) is used where a test must fire the STALL deadline WITHOUT
// also firing the total-import deadline — otherwise every stall test would pass for the
// wrong reason.
//
// Fixtures are synthetic: a CI JVM unit test cannot read the gitignored `test-books/`
// tree, and every case here needs byte-exact or pathological stream behaviour that no
// real book can provide (a read that never returns, an endless stream, a revoked grant).
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

@RunWith(RobolectricTestRunner::class)
class IncomingImportCoordinatorTest {

    @get:Rule
    val temp = TemporaryFolder()

    private val importer = FakeImporter()

    // ── ordering, relay, delivery ────────────────────────────────────────────────

    @Test
    fun `items import sequentially and every outcome reaches a LATE collector`() = runTest {
        val fixture = fixture()
        val items = listOf(readyItem("a.epub"), readyItem("b.epub"), readyItem("c.epub"))
        fixture.acquire(items.size)
        fixture.coordinator.enqueue(items)
        testScheduler.runCurrent()

        // The collector starts only NOW — after every import already finished. A
        // non-replaying SharedFlow would have dropped all three.
        val outcomes = fixture.collectOutcomes()
        assertEquals(3, outcomes.size)
        assertTrue(outcomes.all { it is IncomingImportOutcome.Imported })
        assertEquals(listOf("a.epub", "b.epub", "c.epub"), importer.calls.map { it.displayName })
        assertEquals(0, fixture.coordinator.outstandingSlots)
    }

    @Test
    fun `a mixed Ready and PreResolved batch yields one outcome per input in input order`() = runTest {
        val fixture = fixture()
        val ready = readyItem("b.epub")
        val second = readyItem("e.epub")
        fixture.acquire(2)
        val items = listOf(
            IncomingItem.PreResolved(IncomingImportOutcome.Unsupported("a.xyz")),
            ready,
            IncomingItem.PreResolved(IncomingImportOutcome.TooLarge),
            IncomingItem.PreResolved(IncomingImportOutcome.Unreadable),
            second,
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
    fun `re-importing the same book reports wasAlreadyPresent and adds no second row`() = runTest {
        val fixture = fixture()
        fixture.acquire(2)
        fixture.coordinator.enqueue(listOf(readyItem("dup.epub")))
        testScheduler.runCurrent()
        fixture.coordinator.enqueue(listOf(readyItem("dup.epub")))
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
        // already-capped value; re-deriving it from `uri.toString()` would silently
        // discard the cap and persist the unbounded string (r4 M1).
        val uri = Uri.parse("content://provider/" + "a".repeat(4000))
        val capped = uri.toString().take(IncomingBookResolver.MAX_SOURCE_URI_CHARS)
        fixture.acquire(1)
        fixture.coordinator.enqueue(listOf(readyItem("long.epub", uri = uri, sourceUri = capped)))
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

        fixture.acquire(1)
        callerScope.launch { fixture.coordinator.enqueue(listOf(readyItem("survives.epub"))) }
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

        fixture.acquire(1)
        fixture.coordinator.enqueue(listOf(readyItem("cancelled.epub", stream = stream)))
        testScheduler.runCurrent()
        assertEquals(1, importer.calls.size)

        fixture.appScope.cancel()
        gate.complete(Unit)
        testScheduler.runCurrent()

        assertEquals("no outcome for a cancelled app", 0, fixture.collectOutcomes().size)
        assertTrue("the stream is still released", stream.closed)
        assertEquals("the permit still comes back", 0, fixture.coordinator.outstandingSlots)
    }

    // ── process-wide sequencing and admission ────────────────────────────────────

    @Test
    fun `sequencing holds ACROSS concurrent callers, not merely within one enqueue`() = runTest {
        val fixture = fixture()
        val callerA = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        val callerB = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        fixture.acquire(4)

        callerA.launch { fixture.coordinator.enqueue(listOf(readyItem("a1.epub"), readyItem("a2.epub"))) }
        callerB.launch { fixture.coordinator.enqueue(listOf(readyItem("b1.epub"), readyItem("b2.epub"))) }
        testScheduler.runCurrent()

        assertFalse("two imports must never overlap", importer.overlapped.get())
        assertEquals(4, fixture.collectOutcomes().size)
        assertEquals(4, importer.calls.size)
    }

    @Test
    fun `MAX_IN_FLIGHT permits are process-wide and every terminal outcome returns exactly one`() = runTest {
        val fixture = fixture()
        val coordinator = fixture.coordinator
        // Two "ImportActivity instances" competing for the ONE process-wide pool.
        val callerA = (1..IncomingImportCoordinator.MAX_IN_FLIGHT / 2).count { coordinator.tryAcquireSlot() }
        val callerB = (1..IncomingImportCoordinator.MAX_IN_FLIGHT / 2).count { coordinator.tryAcquireSlot() }
        assertEquals(IncomingImportCoordinator.MAX_IN_FLIGHT, callerA + callerB)
        assertFalse("the 21st concurrent open is refused", coordinator.tryAcquireSlot())

        val half = IncomingImportCoordinator.MAX_IN_FLIGHT / 2
        coordinator.enqueue((1..half).map { readyItem("a$it.epub") })
        coordinator.enqueue((1..half).map { readyItem("b$it.epub") })
        testScheduler.runCurrent()

        assertEquals(IncomingImportCoordinator.MAX_IN_FLIGHT, fixture.collectOutcomes().size)
        assertEquals("every terminal outcome released its permit", 0, coordinator.outstandingSlots)
        assertTrue("the pool is usable again", coordinator.tryAcquireSlot())
    }

    @Test
    fun `an item beyond MAX_IN_FLIGHT is closed, relayed as Failed, and gives its permit back`() = runTest {
        val fixture = fixture()
        val gate = CompletableDeferred<Unit>()
        importer.gate = gate
        val overflow = RecordingStream(bytes(8))

        val accepted = (1..IncomingImportCoordinator.MAX_IN_FLIGHT).map { readyItem("q$it.epub") }
        fixture.acquire(IncomingImportCoordinator.MAX_IN_FLIGHT)
        fixture.coordinator.enqueue(accepted)
        testScheduler.runCurrent()
        // The pool is exhausted, so WI-5 could not have got a permit for this one — the
        // coordinator's own depth guard is the defence against a caller that enqueues anyway.
        assertFalse(fixture.coordinator.tryAcquireSlot())
        fixture.coordinator.enqueue(listOf(readyItem("over.epub", stream = overflow)))

        assertTrue("a rejected item's stream is closed immediately", overflow.closed)
        assertEquals("and it never reaches the importer", 1, importer.calls.size)
        gate.complete(Unit)
        testScheduler.runCurrent()

        val outcomes = fixture.collectOutcomes()
        assertEquals(IncomingImportCoordinator.MAX_IN_FLIGHT + 1, outcomes.size)
        assertEquals(0, fixture.coordinator.outstandingSlots)
    }

    // ── D8: the GUARANTEE ────────────────────────────────────────────────────────

    @Test
    fun `liveness is GUARANTEED - a read that blocks forever and ignores close cannot wedge the queue`() = runTest {
        // The first item's copy runs on a REAL thread so its read genuinely parks; every
        // later item runs on the scheduler so the assertions stay deterministic.
        var first = true
        val fixture = fixture(
            copyContextFactory = { name ->
                if (first) { first = false; dedicatedThreadDispatcher(name) } else StandardTestDispatcher(testScheduler)
            },
        )
        val wedged = ForeverBlockingStream(honoursClose = false)
        fixture.acquire(2)
        fixture.coordinator.enqueue(listOf(readyItem("wedged.epub", stream = wedged), readyItem("next.epub")))

        testScheduler.advanceUntilIdle()

        val outcomes = fixture.collectOutcomes()
        assertEquals(2, outcomes.size)
        assertEquals(IncomingImportOutcome.Failed, outcomes[0])
        assertTrue("the worker advanced to the NEXT item", outcomes[1] is IncomingImportOutcome.Imported)
        assertEquals("the abandoned item's permit came back", 0, fixture.coordinator.outstandingSlots)
        // THE point of this test: the guarantee held while the call is STILL blocked. If
        // liveness had depended on close() unblocking the read, this would be true.
        assertFalse("the blocked read has NOT returned", wedged.readReturned.get())
        assertTrue("close() was attempted (best-effort tier)", wedged.closeAttempts.get() > 0)
    }

    @Test
    fun `the stall watchdog closes a cooperative stream and the worker proceeds`() = runTest {
        var first = true
        val fixture = fixture(
            copyContextFactory = { name ->
                if (first) { first = false; dedicatedThreadDispatcher(name) } else StandardTestDispatcher(testScheduler)
            },
        )
        val stalled = ForeverBlockingStream(honoursClose = true)
        fixture.acquire(2)
        fixture.coordinator.enqueue(listOf(readyItem("stalled.epub", stream = stalled), readyItem("after.epub")))
        testScheduler.runCurrent()

        // Only the STALL deadline — not the 5-minute total. Firing both would let this
        // test pass on the total timeout and prove nothing about the watchdog.
        testScheduler.advanceTimeBy(STALL_MS + 1)
        assertTrue("the parked read was released", stalled.awaitReadFailed())

        val outcomes = fixture.awaitOutcomes(2)
        assertEquals(2, outcomes.size)
        assertEquals(IncomingImportOutcome.Failed, outcomes[0])
        assertTrue(outcomes[1] is IncomingImportOutcome.Imported)
    }

    @Test
    fun `a timeout yields Failed with the stream closed and the permit returned`() = runTest {
        val fixture = fixture(copyContextFactory = { dedicatedThreadDispatcher(it) })
        val wedged = ForeverBlockingStream(honoursClose = false)
        fixture.acquire(1)
        fixture.coordinator.enqueue(listOf(readyItem("timeout.epub", stream = wedged)))
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
        fixture.acquire(1)
        // declaredSize is null: ImportActivity's pre-open preflight had nothing to reject on.
        fixture.coordinator.enqueue(listOf(readyItem("lying.epub", stream = stream, declaredSize = null)))
        testScheduler.runCurrent()

        assertEquals(listOf(IncomingImportOutcome.TooLarge), fixture.collectOutcomes())
        assertTrue(stream.closed)
    }

    @Test
    fun `an endless stream is stopped in bounded time`() = runTest {
        val fixture = fixture(maxImportBytes = 64 * 1024)
        val endless = EndlessStream()
        fixture.acquire(1)
        fixture.coordinator.enqueue(listOf(readyItem("endless.epub", stream = endless, declaredSize = null)))
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
        fixture.acquire(1)
        fixture.coordinator.enqueue(listOf(readyItem("weird.bin", stream = stream)))
        testScheduler.runCurrent()

        assertEquals(listOf(IncomingImportOutcome.Unsupported("weird.bin")), fixture.collectOutcomes())
        assertTrue(stream.closed)
    }

    @Test
    fun `a revoked grant mid-copy maps to Failed and leaves no part file`() = runTest {
        val fixture = fixture()
        val stream = RecordingStream(bytes(32))
        importer.failAt[0] = SecurityException("Permission Denial: reading from a revoked grant")
        fixture.acquire(1)
        fixture.coordinator.enqueue(listOf(readyItem("revoked.epub", stream = stream)))
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
        fixture.acquire(3)
        fixture.coordinator.enqueue(streams.mapIndexed { i, s -> readyItem("i$i.epub", stream = s) })
        testScheduler.runCurrent()

        val outcomes = fixture.collectOutcomes()
        assertEquals(3, outcomes.size)
        assertTrue(outcomes[0] is IncomingImportOutcome.Imported)
        assertEquals(IncomingImportOutcome.Failed, outcomes[1])
        assertTrue(outcomes[2] is IncomingImportOutcome.Imported)
        assertTrue("every stream released on every path", streams.all { it.closed })
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
        val gate = BoundedCallGate(scope) { StandardTestDispatcher(testScheduler) }
        var result: BoundedCall<String>? = null
        scope.launch { result = gate.call(timeoutMillis = 1_000) { "ok" } }
        testScheduler.runCurrent()
        assertEquals(BoundedCall.Completed("ok"), result)
    }

    @Test
    fun `a bounded call reports the block's failure`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        val gate = BoundedCallGate(scope) { StandardTestDispatcher(testScheduler) }
        var result: BoundedCall<String>? = null
        scope.launch { result = gate.call(timeoutMillis = 1_000) { throw IOException("nope") } }
        testScheduler.runCurrent()
        assertTrue(result is BoundedCall.Failed)
        assertTrue((result as BoundedCall.Failed).error is IOException)
    }

    @Test
    fun `a bounded call returns TimedOut while the blocked call is STILL running`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        val gate = BoundedCallGate(scope) { dedicatedThreadDispatcher(it) }
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
    }

    @Test
    fun `a late result is DISPOSED, never leaked`() = runTest {
        val scope = CoroutineScope(StandardTestDispatcher(testScheduler) + SupervisorJob())
        val gate = BoundedCallGate(scope) { dedicatedThreadDispatcher(it) }
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

    private class Fixture(
        val coordinator: IncomingImportCoordinator,
        val appScope: CoroutineScope,
        private val scope: TestScope,
    ) {
        private val collected = mutableListOf<IncomingImportOutcome>()

        fun acquire(n: Int) = repeat(n) { check(coordinator.tryAcquireSlot()) { "no permit" } }

        /** Collects everything buffered so far — deliberately started LATE (D9). Accumulates
         *  across calls, so polling never discards an outcome it already drained. */
        fun collectOutcomes(): List<IncomingImportOutcome> {
            val job = appScope.launch { coordinator.outcomes.collect { collected += it } }
            scope.testScheduler.runCurrent()
            job.cancel()
            return collected.toList()
        }

        /** For the cases whose work genuinely runs on a REAL thread: virtual time cannot
         *  order a real read's completion against the scheduler, so poll (bounded) instead
         *  of assuming one `runCurrent` lands after it. */
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
            importTimeoutMillis = importTimeoutMillis,
            stallTimeoutMillis = stallTimeoutMillis,
            maxImportBytes = maxImportBytes,
            copyContextFactory = copyContextFactory,
        )
        return Fixture(coordinator, appScope, this)
    }

    private fun readyItem(
        displayName: String,
        uri: Uri = Uri.parse("content://provider/$displayName"),
        sourceUri: String = uri.toString().take(IncomingBookResolver.MAX_SOURCE_URI_CHARS),
        format: BookFormat = BookFormat.epub,
        declaredSize: Long? = 32L,
        stream: InputStream = RecordingStream(bytes(32)),
    ) = IncomingItem.Ready(
        PendingImport(
            uri = uri,
            displayName = displayName,
            format = format,
            sourceUri = sourceUri,
            declaredSize = declaredSize,
            stream = stream,
        ),
    )

    private fun bytes(n: Int) = ByteArray(n) { (it % 251).toByte() }

    /** Stands in for `BookImporter.importStream`: it CONSUMES the stream (so the counting
     *  guard is exercised), records the exact arguments, and models the library as a
     *  key-addressed map plus an on-disk artifact — the two things `wasAlreadyPresent`
     *  actually depends on. It deliberately does NOT close the stream, so every closure
     *  assertion is about the coordinator's ownership, not the fake's politeness. */
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

    /** Never returns from `read()`. [honoursClose] decides whether `close()` releases it —
     *  the difference between D8's best-effort tier and the guarantee. */
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
        const val POLL_ATTEMPTS = 500
        const val POLL_INTERVAL_MS = 10L
    }
}
