package com.vreader.app.stats

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.BookEntity
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import com.vreader.app.stats.clock.DateClock
import com.vreader.app.stats.clock.DateSegment
import com.vreader.app.stats.clock.SystemDateClock
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.Clock
import java.time.LocalDate
import java.time.ZoneId

/** Feature #122 WI-2 — ReadingStatsRepository: streak (window-independent), windows, per-book join, chart. */
@RunWith(RobolectricTestRunner::class)
class ReadingStatsRepositoryTest {
    private class FixedDate(private val today: String) : DateClock {
        private val d = SystemDateClock(Clock.systemUTC(), ZoneId.of("UTC"))
        override fun today() = today
        override fun nowEpochMillis() = 0L
        override fun localDate(epochMillis: Long) = d.localDate(epochMillis)
        override fun splitByLocalDate(s: Long, e: Long): List<DateSegment> = d.splitByLocalDate(s, e)
    }

    private lateinit var db: VReaderDatabase
    private fun repo(today: String) =
        ReadingStatsRepository(db.readingStatsDao(), LibraryRepository(db.bookDao(), db.readingPositionDao()), FixedDate(today))

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java)
            .allowMainThreadQueries().build()
    }
    @After fun tearDown() = db.close()

    private fun day(today: String, back: Int) = LocalDate.parse(today).minusDays(back.toLong()).toString()

    // ── streak (pure helper) ────────────────────────────────────────
    @Test fun streak_consecutiveEndingToday() {
        val r = repo("2026-06-27")
        val dates = setOf("2026-06-27", "2026-06-26", "2026-06-25")
        assertEquals(3, r.currentStreak(dates, LocalDate.parse("2026-06-27")))
    }

    @Test fun streak_todayZeroButYesterdayActive() {
        val r = repo("2026-06-27")
        val dates = setOf("2026-06-26", "2026-06-25")   // today not active
        assertEquals(2, r.currentStreak(dates, LocalDate.parse("2026-06-27")))
    }

    @Test fun streak_brokenByGap() {
        val r = repo("2026-06-27")
        val dates = setOf("2026-06-27", "2026-06-25")   // 06-26 missing
        assertEquals(1, r.currentStreak(dates, LocalDate.parse("2026-06-27")))
    }

    @Test fun streak_emptyIsZero() {
        assertEquals(0, repo("2026-06-27").currentStreak(emptySet(), LocalDate.parse("2026-06-27")))
    }

    // ── dashboard (real Room) ──────────────────────────────────────
    @Test fun dashboard_windowIndependentStreak_andWindowScopedTotals() = runBlocking {
        val today = "2026-06-27"
        val r = repo(today)
        db.bookDao().upsert(book("b1", "Austen"))
        // 30 consecutive active days, 5 min each
        repeat(30) { back -> r.recordMinutes("b1", day(today, back), 5) }

        val d7 = r.dashboard(StatsWindow.d7).first()
        assertEquals(30, d7.streakDays)            // streak is ALL-TIME, not capped by the 7-day window
        assertEquals(7 * 5, d7.windowMinutes)      // totals ARE window-scoped
        assertEquals(14, d7.daily14.size)          // chart is always 14 days
        assertEquals(listOf("Austen"), d7.perBook.map { it.title })
    }

    @Test fun dashboard_orphanStatsExcludedFromPerBook_butCountInTotals() = runBlocking {
        val today = "2026-06-27"
        val r = repo(today)
        db.bookDao().upsert(book("b1", "Austen"))
        r.recordMinutes("b1", today, 10)
        r.recordMinutes("ghost", today, 4)         // no book row → orphan
        val data = r.dashboard(StatsWindow.all).first()
        assertEquals(14, data.windowMinutes)       // orphan minutes still count
        assertEquals(listOf("Austen"), data.perBook.map { it.title })  // but orphan omitted from the table
    }

    @Test fun dashboard_noData() = runBlocking {
        val data = repo("2026-06-27").dashboard(StatsWindow.d30).first()
        assertEquals(0, data.windowMinutes)
        assertEquals(false, data.hasData)
    }

    private fun book(key: String, title: String) =
        BookEntity(key, title, "txt", "h", 1L, null, null, 0L, null)
}
