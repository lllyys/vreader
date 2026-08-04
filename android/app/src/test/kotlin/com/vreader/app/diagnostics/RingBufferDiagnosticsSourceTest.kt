package com.vreader.app.diagnostics

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * Feature #164 WI-3 — the in-process ring buffer: the capture floor that survives a platform
 * policy revoking logcat (plan §2), and VLog's sink.
 *
 * The eviction assertions run at capacity+1 AND capacity*3 on purpose: an implementation that
 * evicts one entry per overflow passes the first and fails the second, and "never exceeds
 * capacity" is the invariant that keeps a long-running process from growing without bound.
 */
class RingBufferDiagnosticsSourceTest {

    /**
     * Deliberately far below what a healthy run produces (hundreds), so the floor detects "the
     * reader never got a look in" without becoming a load-sensitive flake.
     */
    private val MIN_INTERLEAVED_READS = 10

    /** Snapshots the reader takes on the empty ring before the writers are released. */
    private val WARMUP_READS = 200

    private fun entries(
        source: RingBufferDiagnosticsSource,
        sinceMillis: Long? = null,
        limit: Int = Int.MAX_VALUE,
    ): List<DiagnosticsLogEntry> = runBlocking {
        val result = source.recentEntries(sinceMillis, limit)
        assertTrue("ring is never Unavailable, got $result", result is SourceResult.Available)
        (result as SourceResult.Available).entries
    }

    private fun RingBufferDiagnosticsSource.put(message: String, at: Long, sequenceId: Long? = null) =
        record(DiagnosticsLevel.INFO, "Reader", message, at, sequenceId)

    // ---------------------------------------------------------------- ordering + fields

    @Test
    fun returnsOldestToNewestWithEveryFieldPreserved() {
        val ring = RingBufferDiagnosticsSource(capacity = 8)
        ring.record(DiagnosticsLevel.WARN, "Library", "first", 1_000L, 7L)
        ring.record(DiagnosticsLevel.ERROR, "Sync", "second", 2_000L, 8L)

        val got = entries(ring)
        assertEquals(listOf("first", "second"), got.map { it.message })
        assertEquals(DiagnosticsLevel.WARN, got[0].level)
        assertEquals("Library", got[0].category)
        assertEquals(1_000L, got[0].timeMillis)
        assertEquals(7L, got[0].sequenceId)
        assertEquals(DiagnosticsLevel.ERROR, got[1].level)
        assertEquals(8L, got[1].sequenceId)
    }

    @Test
    fun recordWithoutASequenceIdYieldsNull() {
        val ring = RingBufferDiagnosticsSource(capacity = 4)
        ring.put("no id", at = 1L)
        assertNull(entries(ring).single().sequenceId)
    }

    @Test
    fun emptyRingReturnsAvailableEmptyNotUnavailable() {
        assertEquals(emptyList<DiagnosticsLogEntry>(), entries(RingBufferDiagnosticsSource(capacity = 4)))
    }

    // ---------------------------------------------------------------- eviction

    @Test
    fun evictsOldestFirstAtCapacityPlusOne() {
        val ring = RingBufferDiagnosticsSource(capacity = 3)
        repeat(4) { ring.put("m$it", at = it.toLong()) }

        val got = entries(ring)
        assertEquals(3, got.size)
        assertEquals(listOf("m1", "m2", "m3"), got.map { it.message })
    }

    @Test
    fun neverExceedsCapacityAtThreeTimesCapacity() {
        val capacity = 5
        val ring = RingBufferDiagnosticsSource(capacity = capacity)
        repeat(capacity * 3) { ring.put("m$it", at = it.toLong()) }

        val got = entries(ring)
        assertEquals(capacity, got.size)
        assertEquals((10..14).map { "m$it" }, got.map { it.message })
    }

    @Test
    fun capacityOfOneKeepsOnlyTheNewest() {
        val ring = RingBufferDiagnosticsSource(capacity = 1)
        repeat(3) { ring.put("m$it", at = it.toLong()) }
        assertEquals(listOf("m2"), entries(ring).map { it.message })
    }

    @Test
    fun nonPositiveCapacityIsRejected() {
        listOf(0, -1).forEach { bad ->
            try {
                RingBufferDiagnosticsSource(capacity = bad)
                throw AssertionError("capacity=$bad must be rejected")
            } catch (expected: IllegalArgumentException) {
                // A silently-zero-capacity ring would drop every entry with no error — the exact
                // silent-degradation shape the whole feature exists to avoid.
            }
        }
    }

    // ---------------------------------------------------------------- limit

    @Test
    fun limitReturnsTheMostRecentEntriesStillOldestToNewest() {
        val ring = RingBufferDiagnosticsSource(capacity = 10)
        repeat(5) { ring.put("m$it", at = it.toLong()) }
        assertEquals(listOf("m3", "m4"), entries(ring, limit = 2).map { it.message })
    }

    @Test
    fun limitLargerThanTheBufferReturnsEverything() {
        val ring = RingBufferDiagnosticsSource(capacity = 10)
        repeat(3) { ring.put("m$it", at = it.toLong()) }
        assertEquals(3, entries(ring, limit = 999).size)
    }

    @Test
    fun zeroAndNegativeLimitReturnEmptyWithoutThrowing() {
        val ring = RingBufferDiagnosticsSource(capacity = 10)
        repeat(3) { ring.put("m$it", at = it.toLong()) }
        assertEquals(emptyList<DiagnosticsLogEntry>(), entries(ring, limit = 0))
        assertEquals(emptyList<DiagnosticsLogEntry>(), entries(ring, limit = -5))
    }

    // ---------------------------------------------------------------- sinceMillis

    @Test
    fun sinceMillisIsInclusiveAndAppliedBeforeLimit() {
        val ring = RingBufferDiagnosticsSource(capacity = 10)
        listOf(10L, 20L, 30L, 40L).forEach { ring.put("m$it", at = it) }

        assertEquals(listOf("m20", "m30", "m40"), entries(ring, sinceMillis = 20L).map { it.message })
        // limit applies to the FILTERED set, so the newest 2 at-or-after 20 are m30/m40.
        assertEquals(listOf("m30", "m40"), entries(ring, sinceMillis = 20L, limit = 2).map { it.message })
    }

    @Test
    fun sinceMillisNewerThanEverythingReturnsEmpty() {
        val ring = RingBufferDiagnosticsSource(capacity = 4)
        ring.put("old", at = 1L)
        assertEquals(emptyList<DiagnosticsLogEntry>(), entries(ring, sinceMillis = 2L))
    }

    // ---------------------------------------------------------------- content edge cases

    @Test
    fun toleratesEmptyCjkAndVeryLongMessages() = runTest {
        val ring = RingBufferDiagnosticsSource(capacity = 4)
        val long = "x".repeat(200_000)
        ring.record(DiagnosticsLevel.DEBUG, "", "", 1L)
        ring.record(DiagnosticsLevel.DEBUG, "读者", "章节加载失败 — 第 3 章", 2L)
        ring.record(DiagnosticsLevel.DEBUG, "Reader", long, 3L)

        val got = (ring.recentEntries(null, Int.MAX_VALUE) as SourceResult.Available).entries
        assertEquals("", got[0].category)
        assertEquals("", got[0].message)
        assertEquals("章节加载失败 — 第 3 章", got[1].message)
        assertEquals(long, got[2].message)
    }

    // ---------------------------------------------------------------- concurrency

    /**
     * Writers from many threads while a reader loops. Three failure shapes are caught: a
     * lost/duplicated entry (the set + size assertions), a snapshot taken over a live collection
     * (`ConcurrentModificationException` on the reader thread), and — the reason for the handshake
     * below — the test itself quietly failing to overlap at all.
     *
     * A shared start latch alone does NOT establish "a read in flight": a legal scheduler may run
     * every writer to completion before the reader takes its first snapshot, so a ring with its
     * synchronisation removed could pass by luck. The run therefore RECORDS how many DISTINCT
     * intermediate sizes the reader observed (strictly between empty and complete) and asserts a
     * floor. One intermediate size proves only that a read happened early; many distinct ones can
     * only be produced by reads interleaved through the write stream. Capacity equals the total, so
     * no eviction can manufacture an intermediate size after the writers finish.
     *
     * The earlier revision instead had writers spin on `Thread.yield()` until the reader signalled
     * a partial observation. That coupling was CI-hostile (a scheduling hint, not a guarantee, with
     * a 30s deadline) and proved less. What the reader genuinely needs is not a handshake per write
     * but a WARM-UP: its first `runBlocking` snapshot pays coroutine/classload costs far larger
     * than the whole write burst, so a cold reader reliably takes its first sample after the
     * writers are done. It therefore does warm-up snapshots on the empty ring first and releases
     * the writers only once it is looping hot.
     */
    @Test
    fun concurrentRecordLosesNothingWhileAReadIsInFlight() {
        val threads = 8
        val perThread = 2_000
        val total = threads * perThread
        val ring = RingBufferDiagnosticsSource(capacity = total)
        val start = CountDownLatch(1)
        val readerWarm = CountDownLatch(1)
        val stopReading = AtomicBoolean(false)
        val intermediateSizes = Collections.synchronizedSet(HashSet<Int>())
        val readerFailure = AtomicReference<Throwable?>(null)
        val writerFailure = AtomicReference<Throwable?>(null)

        val reader = Thread {
            start.await()
            try {
                var reads = 0
                while (!stopReading.get()) {
                    val size = runBlocking {
                        (ring.recentEntries(null, Int.MAX_VALUE) as SourceResult.Available).entries.size
                    }
                    if (size in 1 until total) intermediateSizes.add(size)
                    if (++reads == WARMUP_READS) readerWarm.countDown()
                }
            } catch (t: Throwable) {
                readerFailure.set(t)
            } finally {
                readerWarm.countDown()   // never strand the writers if the reader dies
            }
        }
        val writers = (0 until threads).map { t ->
            Thread {
                start.await()
                readerWarm.await()
                try {
                    repeat(perThread) { i -> ring.put("$t-$i", at = i.toLong()) }
                } catch (e: Throwable) {
                    writerFailure.set(e)
                }
            }
        }

        reader.start()
        writers.forEach { it.start() }
        start.countDown()
        writers.forEach { it.join(60_000) }
        stopReading.set(true)
        reader.join(60_000)

        writers.forEachIndexed { i, w -> assertFalse("writer $i still alive", w.isAlive) }
        assertFalse("reader still alive", reader.isAlive)
        assertNull("reader threw: ${readerFailure.get()}", readerFailure.get())
        assertNull("writer threw: ${writerFailure.get()}", writerFailure.get())
        assertTrue(
            "reads did not interleave with the writes (${intermediateSizes.size} distinct " +
                "intermediate sizes) — this run proved nothing about concurrent reads",
            intermediateSizes.size >= MIN_INTERLEAVED_READS,
        )

        val got = entries(ring)
        val expected = (0 until threads).flatMap { t -> (0 until perThread).map { "$t-$it" } }.toSet()
        assertEquals("lost or duplicated entries", total, got.size)
        assertEquals(expected, got.map { it.message }.toSet())
    }

    @Test
    fun concurrentOverflowNeverExceedsCapacity() {
        val ring = RingBufferDiagnosticsSource(capacity = 100)
        val start = CountDownLatch(1)
        val writers = (0 until 6).map { t ->
            Thread {
                start.await()
                repeat(400) { i -> ring.put("$t-$i", at = i.toLong()) }
            }
        }
        writers.forEach { it.start() }
        start.countDown()
        writers.forEach { it.join(60_000) }

        assertEquals(100, entries(ring).size)
    }
}
