package com.vreader.app.diagnostics

import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
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
     * Writers from many threads while a reader loops. Two failure shapes are caught:
     * a lost/duplicated entry (the set + size assertions), and a snapshot taken over a live
     * collection (`ConcurrentModificationException` on the reader thread). Capacity is sized
     * ABOVE the total so eviction cannot mask a lost write.
     */
    @Test
    fun concurrentRecordLosesNothingWhileAReadIsInFlight() {
        val threads = 8
        val perThread = 500
        val ring = RingBufferDiagnosticsSource(capacity = threads * perThread)
        val start = CountDownLatch(1)
        val stopReading = AtomicBoolean(false)
        val readerFailure = AtomicReference<Throwable?>(null)
        val writerFailure = AtomicReference<Throwable?>(null)

        val reader = Thread {
            start.await()
            try {
                while (!stopReading.get()) {
                    runBlocking { ring.recentEntries(null, Int.MAX_VALUE) }
                }
            } catch (t: Throwable) {
                readerFailure.set(t)
            }
        }
        val writers = (0 until threads).map { t ->
            Thread {
                start.await()
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

        assertNull("reader threw: ${readerFailure.get()}", readerFailure.get())
        assertNull("writer threw: ${writerFailure.get()}", writerFailure.get())

        val got = entries(ring)
        val expected = (0 until threads).flatMap { t -> (0 until perThread).map { "$t-$it" } }.toSet()
        assertEquals("lost or duplicated entries", threads * perThread, got.size)
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
