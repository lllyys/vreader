// Purpose: feature #122 WI-2 (#110 Phase 3) — reading-stats aggregate policy over ReadingStatsDao +
// LibraryRepository. Derives the dashboard (window totals, 14-day chart, per-book table with live
// titles, a WINDOW-INDEPENDENT consecutive-day streak, daily average) from all daily_reading rows.
// Date-string math uses java.time.LocalDate anchored on the injected DateClock.today() (deterministic).
package com.vreader.app.stats

import com.vreader.app.data.ReadingStatsDao
import com.vreader.app.data.LibraryRepository
import com.vreader.app.stats.clock.DateClock
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import java.time.LocalDate

/** Dashboard time window. `days == null` = all-time. */
enum class StatsWindow(val days: Int?) { today(1), d7(7), d30(30), d90(90), year(365), all(null) }

data class DayMinutes(val date: String, val minutes: Int)
data class BookStat(val bookKey: String, val title: String, val minutes: Int)
data class DashboardData(
    val windowMinutes: Int = 0,
    val streakDays: Int = 0,
    val dailyAvgMinutes: Int = 0,
    val daily14: List<DayMinutes> = emptyList(),
    val perBook: List<BookStat> = emptyList(),
) {
    val hasData: Boolean get() = windowMinutes > 0 || daily14.any { it.minutes > 0 } || perBook.isNotEmpty()
}

class ReadingStatsRepository(
    private val dao: ReadingStatsDao,
    private val library: LibraryRepository,
    private val dateClock: DateClock,
) {
    suspend fun recordMinutes(bookKey: String, date: String, deltaMinutes: Int) {
        if (deltaMinutes > 0) dao.addMinutes(date, bookKey, deltaMinutes)
    }

    suspend fun bookTotalMinutes(bookKey: String): Int {
        val today = dateClock.today()   // exclude future-dated rows (clock skew), consistent with dashboard()
        return dao.allRows().filter { it.bookKey == bookKey && it.date <= today }.sumOf { it.minutes }
    }

    /** Observe the dashboard for [window]. All rows are observed (daily_reading is small — one row per
     *  day per book); the window scopes totals/chart/perBook in-memory, while the streak is all-time. */
    fun dashboard(window: StatsWindow): Flow<DashboardData> =
        combine(dao.observeRowsSince(ALL_FLOOR), library.observeLibrary()) { allRows, books ->
            val today = LocalDate.parse(dateClock.today())
            val todayStr = today.toString()
            // exclude FUTURE-dated rows (clock skew / bad seed) from every aggregate.
            val rows = allRows.filter { it.date <= todayStr }
            val since = window.days?.let { today.minusDays((it - 1).toLong()).toString() }
            val windowRows = if (since == null) rows else rows.filter { it.date >= since }

            val windowMinutes = windowRows.sumOf { it.minutes }
            // "Daily avg" = average per day OVER the window: bounded windows divide by the window's day
            // span; all-time divides by the active-day count (no fixed span).
            val denomDays = window.days ?: windowRows.map { it.date }.distinct().size
            val dailyAvg = if (denomDays > 0) windowMinutes / denomDays else 0

            val titles = books.associate { it.fingerprintKey to it.title }
            val perBook = windowRows.groupBy { it.bookKey }
                .mapNotNull { (key, rs) -> titles[key]?.let { BookStat(key, it, rs.sumOf { r -> r.minutes }) } }  // orphans omitted
                .sortedByDescending { it.minutes }

            DashboardData(
                windowMinutes = windowMinutes,
                streakDays = currentStreak(rows.map { it.date }.toSet(), today),  // WINDOW-INDEPENDENT
                dailyAvgMinutes = dailyAvg,
                daily14 = last14Days(rows, today),
                perBook = perBook,
            )
        }

    /** Consecutive active local days ending today (or yesterday if today is 0) — NOT window-scoped. */
    internal fun currentStreak(activeDates: Set<String>, today: LocalDate): Int {
        // anchor: today if active, else yesterday if active, else streak 0.
        var day = when {
            today.toString() in activeDates -> today
            today.minusDays(1).toString() in activeDates -> today.minusDays(1)
            else -> return 0
        }
        var streak = 0
        while (day.toString() in activeDates) { streak++; day = day.minusDays(1) }
        return streak
    }

    /** The last 14 local days (chronological), 0-filled for inactive days — the daily chart. */
    internal fun last14Days(rows: List<com.vreader.app.data.DailyReadingEntity>, today: LocalDate): List<DayMinutes> {
        val byDate = rows.groupBy { it.date }.mapValues { (_, rs) -> rs.sumOf { it.minutes } }
        return (13 downTo 0).map { back ->
            val d = today.minusDays(back.toLong()).toString()
            DayMinutes(d, byDate[d] ?: 0)
        }
    }

    private companion object { const val ALL_FLOOR = "0000-01-01" }
}
