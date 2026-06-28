package com.vreader.app.stats

import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import com.vreader.app.data.BookEntity
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import com.vreader.app.stats.clock.DateClock
import com.vreader.app.stats.clock.DateSegment
import com.vreader.app.stats.clock.ElapsedClock
import com.vreader.app.stats.clock.SystemDateClock
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId

/**
 * Feature #122 WI-4 — the FINAL-WI acceptance: drives the REAL stack on the emulator
 * (ReadingTimeTracker → ReadingStatsRepository → Room daily_reading via the real SQLite), then asserts
 * the dashboard reflects the banked minutes, per-book join, streak, and 14-day chart. Clocks are
 * injected (deterministic) — the "real environment" here is on-device Room + the production aggregation.
 */
@RunWith(AndroidJUnit4::class)
class ReadingStatsConnectedTest {
    private class FakeElapsed(var ms: Long = 0) : ElapsedClock { override fun nowMillis() = ms }
    private class FixedDate(private val today: String) : DateClock {
        private val d = SystemDateClock(Clock.systemUTC(), ZoneId.of("UTC"))
        override fun today() = today
        override fun nowEpochMillis() = LocalDate.parse(today).atStartOfDay(ZoneId.of("UTC")).toInstant().toEpochMilli() + 12 * 3_600_000L
        override fun localDate(epochMillis: Long) = d.localDate(epochMillis)
        override fun splitByLocalDate(s: Long, e: Long): List<DateSegment> = d.splitByLocalDate(s, e)
    }

    private lateinit var db: VReaderDatabase
    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            InstrumentationRegistry.getInstrumentation().targetContext, VReaderDatabase::class.java,
        ).build()
    }
    @After fun tearDown() = db.close()

    @Test fun realStack_recordAcrossDaysAndBooks_dashboardReflects() = runBlocking {
        val today = "2026-06-28"
        val lib = LibraryRepository(db.bookDao(), db.readingPositionDao())
        db.bookDao().upsert(book("b1", "Pride and Prejudice"))
        db.bookDao().upsert(book("b2", "Walden"))
        val date = FixedDate(today)
        val repo = ReadingStatsRepository(db.readingStatsDao(), lib, date)

        // 1) drive the REAL tracker for b1 today → proves tracker→repo→Room banking on device.
        val elapsed = FakeElapsed()
        val tracker = ReadingTimeTracker(repo, elapsed, date)
        tracker.start("b1")
        elapsed.ms = 5 * 60_000L          // 5 minutes
        tracker.stop()

        // 2) seed a 3-day streak for the chart/streak (b2 yesterday + b1 two days ago).
        repo.recordMinutes("b2", LocalDate.parse(today).minusDays(1).toString(), 12)
        repo.recordMinutes("b1", LocalDate.parse(today).minusDays(2).toString(), 8)

        val data = repo.dashboard(StatsWindow.all).first()
        assertEquals("total minutes across the real Room rows", 5 + 12 + 8, data.windowMinutes)
        assertEquals("3 consecutive active days ending today", 3, data.streakDays)
        assertTrue("per-book joins live titles", data.perBook.map { it.title }.containsAll(listOf("Pride and Prejudice", "Walden")))
        assertEquals("chart is 14 days", 14, data.daily14.size)
        assertEquals("today's bank is the tracker's 5 min", 5, data.daily14.last().minutes)
    }

    /**
     * WI-4 Gate-4 fix coverage: drives a REAL AndroidX [LifecycleRegistry] through the exact bracket the
     * reader installs — registering the observer AFTER the owner is already RESUMED (the Loaded-composition
     * case), then ON_STOP. Proves on-device: (a) addObserver's event replay delivers ON_RESUME so the
     * initial open is tracked (no missed first session), (b) a keyed stop banks through to Room, and (c) a
     * stale keyed stop for a different book is a no-op (a stale Activity can't clobber another session).
     */
    @Test fun lifecycleHook_replayStartsAndKeyedStopBanks_onDevice() = runBlocking {
        val today = "2026-06-28"
        val lib = LibraryRepository(db.bookDao(), db.readingPositionDao())
        db.bookDao().upsert(book("b1", "Pride and Prejudice"))
        val date = FixedDate(today)
        val repo = ReadingStatsRepository(db.readingStatsDao(), lib, date)
        val elapsed = FakeElapsed()
        val tracker = ReadingTimeTracker(repo, elapsed, date)
        // mirror the reader's must-finish appScope. The launches are fire-and-forget there; here we join
        // the launched jobs (drain) before asserting so the suspending Room write has committed.
        val supervisor = Job()
        val scope = CoroutineScope(Dispatchers.Unconfined + supervisor)
        suspend fun drain() = supervisor.children.toList().forEach { it.join() }

        val owner = object : LifecycleOwner {
            val reg = LifecycleRegistry.createUnsafe(this)   // createUnsafe: skip the main-thread check (test thread)
            override val lifecycle get() = reg
        }
        // already RESUMED before the observer exists — exactly the reader's "load finished after ON_RESUME" path.
        owner.reg.handleLifecycleEvent(Lifecycle.Event.ON_CREATE)
        owner.reg.handleLifecycleEvent(Lifecycle.Event.ON_START)
        owner.reg.handleLifecycleEvent(Lifecycle.Event.ON_RESUME)

        val obs = LifecycleEventObserver { _, e ->
            when (e) {
                Lifecycle.Event.ON_RESUME -> scope.launch { tracker.start("b1") }
                Lifecycle.Event.ON_STOP -> scope.launch { tracker.stop("b1") }
                else -> Unit
            }
        }
        owner.reg.addObserver(obs)   // replay delivers ON_RESUME → start("b1")
        drain()                      // start() finished, session marks set at elapsed=0

        elapsed.ms = 4 * 60_000L     // under maxIdleMillis (5m) so the gap is read as continuous reading, not idle
        owner.reg.handleLifecycleEvent(Lifecycle.Event.ON_PAUSE)
        owner.reg.handleLifecycleEvent(Lifecycle.Event.ON_STOP)   // keyed stop banks 4 min
        drain()                      // the keyed stop's Room write has committed

        tracker.stop("someOtherBook")   // stale keyed stop for a different book → no-op, must not clobber

        val data = repo.dashboard(StatsWindow.all).first()
        assertEquals("registration replay started the session; keyed stop banked 4 min", 4, data.windowMinutes)
    }

    private fun book(key: String, title: String) = BookEntity(key, title, "txt", "h", 1L, null, null, 0L, null)
}
