// Purpose: feature #122 WI-2 (#110 Phase 3) — accumulates in-reader reading time into per-day/per-book
// minutes. Idempotent state machine over a MONOTONIC ElapsedClock (durations) + a calendar DateClock
// (local-date buckets): start switches/flushes the old book; flush banks whole minutes (carrying a
// sub-minute remainder so none is lost), clamps an idle gap to 0, splits a midnight-crossing window
// across local dates (largest-remainder so the per-day sum is exact), and advances the accounted marks
// so a restart/repeat can never replay. Process-singleton (the reader VM is shorter-lived).
package com.vreader.app.stats

import com.vreader.app.stats.clock.DateClock
import com.vreader.app.stats.clock.ElapsedClock
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class ReadingTimeTracker(
    private val repo: ReadingStatsRepository,
    private val elapsed: ElapsedClock,
    private val dateClock: DateClock,
    private val maxIdleMillis: Long = 5 * 60_000L,   // a gap longer than this banks 0 (backgrounded/idle)
) {
    private val mutex = Mutex()
    private var activeBook: String? = null
    private var lastAccountedElapsed = 0L
    private var lastAccountedWall = 0L
    private var sessionStartElapsed = 0L
    // sub-minute reading time not yet banked, kept PER LOCAL DATE (provenance) — so a fragment from
    // before midnight banks to the right day even across flushes. Cleared on a book switch / idle gap.
    private val carryByDate = HashMap<String, Long>()

    private val _sessionSeconds = MutableStateFlow(0L)
    val sessionSeconds: StateFlow<Long> = _sessionSeconds.asStateFlow()

    /** Begin (or switch to) a book. A different active book is flushed first. Idempotent for the same book. */
    suspend fun start(bookKey: String) = mutex.withLock {
        if (activeBook == bookKey) return@withLock
        if (activeBook != null) flushLocked()
        activeBook = bookKey
        lastAccountedElapsed = elapsed.nowMillis()
        lastAccountedWall = dateClock.nowEpochMillis()
        sessionStartElapsed = lastAccountedElapsed
        carryByDate.clear()                          // a new session/book starts fresh (sub-minute carry dropped)
        _sessionSeconds.value = 0
    }

    /** Bank the time since the last accounting, then keep going (periodic flush). */
    suspend fun flush() = mutex.withLock { flushLocked() }

    /** Bank the time, then clear the active book. Idempotent (a second stop banks 0 and no-ops). A
     *  [bookKey], when given, only stops that book — so a stale Activity can't stop another's session. */
    suspend fun stop(bookKey: String? = null) = mutex.withLock {
        if (bookKey != null && activeBook != bookKey) return@withLock
        flushLocked()
        activeBook = null
        _sessionSeconds.value = 0
    }

    /** Refresh the live session-time pill (call from a ticker). No banking. */
    fun tickSessionSeconds() {
        if (activeBook == null) return
        _sessionSeconds.value = (elapsed.nowMillis() - sessionStartElapsed).coerceAtLeast(0) / 1000
    }

    // caller holds the mutex
    private suspend fun flushLocked() {
        val book = activeBook ?: return
        val now = elapsed.nowMillis()
        val delta = now - lastAccountedElapsed
        // delta <= 0 = no time / a monotonic anomaly: do NOT move the marks backward (that would let a
        // recovered clock replay the interval). Leave the high-water marks; bank nothing.
        if (delta <= 0) return
        val windowStart = lastAccountedWall
        lastAccountedElapsed = now
        lastAccountedWall += delta
        if (delta > maxIdleMillis) { carryByDate.clear(); return }  // idle gap → bank nothing, drop sub-minute carry

        // Add each local-date segment's millis to that DATE's carry, then bank whole minutes per date,
        // keeping the per-date remainder. Each segment lies within one local date, so attribution is
        // exact + a fragment before midnight banks to the right day even across flushes. NonCancellable
        // so a teardown can't interrupt the durable write after the marks have advanced (no lost minutes).
        withContext(NonCancellable) {
            for (seg in dateClock.splitByLocalDate(windowStart, windowStart + delta)) {
                val total = (carryByDate[seg.date] ?: 0L) + (seg.endMs - seg.startMs)
                val minutes = (total / 60_000L).toInt()
                carryByDate[seg.date] = total % 60_000L
                if (minutes > 0) repo.recordMinutes(book, seg.date, minutes)
            }
        }
    }
}
