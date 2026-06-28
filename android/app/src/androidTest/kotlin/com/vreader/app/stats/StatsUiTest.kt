package com.vreader.app.stats

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.backup.BackupSurface
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Feature #122 WI-3 — the in-reader pill/card + the dashboard (populated + no-data). */
@RunWith(AndroidJUnit4::class)
class StatsUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun sessionPill_formatsClock() {
        compose.setContent { com.vreader.app.ui.theme.VReaderTheme { InReaderSessionPill(sessionSeconds = 1448) } }
        compose.onNodeWithTag("stats-session-pill").assertIsDisplayed()
        compose.onNodeWithText("24:08").assertIsDisplayed()   // 1448s = 24:08
    }

    @Test fun detailCard_showsStats() {
        compose.setContent {
            com.vreader.app.ui.theme.VReaderTheme {
                InReaderTimeDetailCard(InReaderStats(sessionSeconds = 1440, bookTotalMinutes = 738, timeLeftMinutes = 580, pace = 230), bookTitle = "Pride and Prejudice", progressPercent = 42)
            }
        }
        compose.onNodeWithText("Pride and Prejudice").assertIsDisplayed()
        compose.onNodeWithText("12h 18m").assertIsDisplayed()   // 738 min total
        compose.onNodeWithText("230 wpm").assertIsDisplayed()
    }

    @Test fun dashboard_populated_showsHeroChartTable_andWindowSwitch() {
        val data = DashboardData(
            windowMinutes = 2472, streakDays = 9, dailyAvgMinutes = 82,
            daily14 = (0 until 14).map { DayMinutes("2026-06-${it + 14}", (it * 5) % 60) },
            perBook = listOf(BookStat("b1", "Pride and Prejudice", 738), BookStat("b2", "Walden", 242)),
        )
        var picked: StatsWindow? = null
        compose.setContent { BackupSurface(darkOverride = false) { StatsDashboard(DashboardUiState(StatsWindow.d30, data, false), onWindow = { picked = it }) } }
        compose.onNodeWithTag("stats-hero-total").assertIsDisplayed()
        compose.onNodeWithText("41h 12m").assertIsDisplayed()       // 2472 min
        compose.onNodeWithText("9 days").assertIsDisplayed()        // streak
        compose.onNodeWithTag("stats-daily-chart").assertIsDisplayed()
        compose.onNodeWithText("Pride and Prejudice").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("window-7d").performClick()
        assertEquals(StatsWindow.d7, picked)
    }

    @Test fun dashboard_noData_keepsFrames() {
        compose.setContent { BackupSurface(darkOverride = false) { StatsDashboard(DashboardUiState(StatsWindow.d30, DashboardData(), false)) } }
        compose.onNodeWithTag("stats-nodata").assertIsDisplayed()           // hero nudge
        compose.onNodeWithTag("stats-daily-chart").assertIsDisplayed()      // chart frame kept
        compose.onNodeWithTag("stats-perbook-empty").performScrollTo().assertIsDisplayed()
    }
}
