package com.vreader.app.stats

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import com.vreader.app.stats.clock.DateClock
import com.vreader.app.stats.clock.DateSegment
import com.vreader.app.stats.clock.ElapsedClock
import com.vreader.app.stats.clock.SystemDateClock
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.Clock
import java.time.Instant
import java.time.ZoneId

/** Feature #122 WI-2 — ReadingTimeTracker accounting (carry, idle-cap, midnight split, no-replay,
 *  book-switch, idempotent stop). Real repo + in-memory Room; fake monotonic + wall clocks. */
@RunWith(RobolectricTestRunner::class)
class ReadingTimeTrackerTest {
    private class FakeElapsed(var ms: Long = 0) : ElapsedClock { override fun nowMillis() = ms }
    private class FakeDate(var wallMs: Long, zone: ZoneId = ZoneId.of("UTC")) : DateClock {
        private val d = SystemDateClock(Clock.systemUTC(), zone)  // splitByLocalDate/localDate take explicit ms
        override fun today() = d.localDate(wallMs)
        override fun nowEpochMillis() = wallMs
        override fun localDate(epochMillis: Long) = d.localDate(epochMillis)
        override fun splitByLocalDate(startInclusiveMs: Long, endExclusiveMs: Long): List<DateSegment> =
            d.splitByLocalDate(startInclusiveMs, endExclusiveMs)
    }

    private lateinit var db: VReaderDatabase
    private lateinit var repo: ReadingStatsRepository
    private val elapsed = FakeElapsed()
    private fun ms(iso: String) = Instant.parse(iso).toEpochMilli()

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java)
            .allowMainThreadQueries().build()
        repo = ReadingStatsRepository(db.readingStatsDao(), LibraryRepository(db.bookDao(), db.readingPositionDao()),
            FakeDate(ms("2026-06-27T10:00:00Z")))
    }
    @After fun tearDown() = db.close()

    private fun tracker(wall: String) = ReadingTimeTracker(repo, elapsed, FakeDate(ms(wall)))
    private suspend fun minutesOn(date: String) = db.readingStatsDao().rowsSince(date).filter { it.date == date }.sumOf { it.minutes }

    @Test fun accumulatesWholeMinutes_carryingRemainder() = runBlocking {
        val t = tracker("2026-06-27T10:00:00Z")
        elapsed.ms = 1_000
        t.start("b1")
        elapsed.ms = 1_000 + 70_000          // 70s → 1 min banked, 10s carried
        t.flush()
        assertEquals(1, minutesOn("2026-06-27"))
        elapsed.ms += 55_000                  // carry 10s + 55s = 65s → +1 min, 5s carried
        t.flush()
        assertEquals(2, minutesOn("2026-06-27"))
    }

    @Test fun idleGapBanksZero() = runBlocking {
        val t = tracker("2026-06-27T10:00:00Z")
        t.start("b1")
        elapsed.ms += 10 * 60_000             // 10 min > 5 min idle cap
        t.flush()
        assertEquals(0, minutesOn("2026-06-27"))
    }

    @Test fun midnightCrossing_splitsAcrossDays_sumExact() = runBlocking {
        val t = tracker("2026-06-27T23:58:00Z")  // start near midnight
        t.start("b1")
        elapsed.ms += 4 * 60_000              // 4 minutes, crossing into 06-28
        t.flush()
        val total = minutesOn("2026-06-27") + minutesOn("2026-06-28")
        assertEquals(4, total)               // no minute lost or duplicated across the boundary
        assertEquals(true, minutesOn("2026-06-28") > 0)  // some banked to the new day
    }

    @Test fun carryCrossingMidnightAcrossTwoFlushes_banksToCorrectDay() = runBlocking {
        // pre-midnight active time must bank to the PRE-midnight day even when the minute completes in
        // a later flush past midnight (the per-date-carry provenance fix).
        val t = tracker("2026-06-27T23:59:00Z")
        t.start("b1")
        elapsed.ms += 50_000                  // → 23:59:50, 50s carried on 2026-06-27
        t.flush()
        assertEquals(0, minutesOn("2026-06-27"))
        elapsed.ms += 20_000                  // → 00:00:10: 10s on 06-27 (completes the minute) + 10s on 06-28
        t.flush()
        assertEquals(1, minutesOn("2026-06-27"))   // the carried pre-midnight time banks to 06-27
        assertEquals(0, minutesOn("2026-06-28"))   // only 10s on 06-28 — sub-minute, still carried
    }

    @Test fun reFlushDoesNotReplay() = runBlocking {
        val t = tracker("2026-06-27T10:00:00Z")
        t.start("b1")
        elapsed.ms += 120_000                 // 2 min
        t.flush(); t.flush(); t.flush()       // extra flushes with delta 0
        assertEquals(2, minutesOn("2026-06-27"))
    }

    @Test fun bookSwitch_flushesPreviousBook() = runBlocking {
        val t = tracker("2026-06-27T10:00:00Z")
        t.start("b1")
        elapsed.ms += 180_000                 // 3 min on b1
        t.start("b2")                         // switch flushes b1
        assertEquals(3, db.readingStatsDao().allRows().single { it.bookKey == "b1" }.minutes)
    }

    @Test fun stopIsIdempotent() = runBlocking {
        val t = tracker("2026-06-27T10:00:00Z")
        t.start("b1")
        elapsed.ms += 120_000
        t.stop()
        t.stop()                              // second stop: no active book → no-op
        assertEquals(2, minutesOn("2026-06-27"))
    }
}
