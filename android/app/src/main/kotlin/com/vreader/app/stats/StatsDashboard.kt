// Purpose: feature #122 WI-3 (#110 Phase 3) — the reading-stats dashboard (design
// vreader-stats-android.jsx `StatsDashboard`): a time-window chip bar + an hour hero (streak +
// daily-avg, or a no-data nudge) + a 14-day daily-reading column chart (today tinted) + a per-book
// table (Time + Hl/Nt + a per-row time hairline). Reuses the backup AppSheet/SettingsCard +
// BackupTokens. Stateless: a pure function of DashboardUiState + callbacks.
package com.vreader.app.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.backup.AppSheet
import com.vreader.app.backup.BackupFonts
import com.vreader.app.backup.LocalBackupTokens
import com.vreader.app.backup.SettingsCard
import com.vreader.app.backup.VSpace

private val WINDOWS = listOf(
    StatsWindow.today to "Today", StatsWindow.d7 to "7d", StatsWindow.d30 to "30d",
    StatsWindow.d90 to "90d", StatsWindow.year to "Year", StatsWindow.all to "All",
)

@Composable
fun StatsDashboard(state: DashboardUiState, onWindow: (StatsWindow) -> Unit = {}, onClose: () -> Unit = {}) {
    val t = LocalBackupTokens.current
    AppSheet(
        title = "Reading Stats",
        leading = {
            Box(Modifier.clickable(onClick = onClose).testTag("stats-close")) {
                Text("Close", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
            }
        },
        trailing = {},
    ) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 28.dp)) {
            WindowBar(state.window, onWindow)
            VSpace(12)
            Hero(state.data)
            VSpace(12)
            DailyChart(state.data.daily14)
            VSpace(12)
            PerBookTable(state.data.perBook)
        }
    }
}

@Composable
private fun WindowBar(active: StatsWindow, onWindow: (StatsWindow) -> Unit) {
    val t = LocalBackupTokens.current
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(7.dp)) {
        WINDOWS.forEach { (w, label) ->
            val on = w == active
            Box(
                Modifier.clip(RoundedCornerShape(100.dp)).background(if (on) t.ink else t.chipBg)
                    .clickable { onWindow(w) }.testTag("window-$label").padding(horizontal = 14.dp, vertical = 7.dp),
            ) { Text(label, color = if (on) t.bg else t.ink, fontFamily = BackupFonts.Sans, fontSize = 13.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium) }
        }
    }
}

@Composable
private fun Hero(data: DashboardData) {
    val t = LocalBackupTokens.current
    SettingsCard {
        Column(Modifier.fillMaxWidth().padding(17.dp)) {
            Text("THIS WINDOW", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Text(if (data.hasData) formatMinutes(data.windowMinutes) else "0m", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 44.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 4.dp).testTag("stats-hero-total"))
            if (data.hasData) {
                Row(Modifier.padding(top = 14.dp), horizontalArrangement = Arrangement.spacedBy(18.dp)) {
                    HeroStat("${data.streakDays} days", "Streak")
                    HeroStat(formatMinutes(data.dailyAvgMinutes), "Daily avg")
                }
            } else {
                Text("Open a book to start tracking. Your reading time, streak, and per-book breakdown show up here.",
                    color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, lineHeight = 20.sp, modifier = Modifier.padding(top = 6.dp).testTag("stats-nodata"))
            }
        }
    }
}

@Composable
private fun HeroStat(value: String, label: String) {
    val t = LocalBackupTokens.current
    Column {
        Text(value, color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 18.sp, fontWeight = FontWeight.Bold)
        Text(label, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 11.sp, modifier = Modifier.padding(top = 1.dp))
    }
}

@Composable
private fun DailyChart(days: List<DayMinutes>) {
    val t = LocalBackupTokens.current
    // always 14 slots so the no-data/initial state keeps the designed frame (the last slot = today).
    val slots = when { days.size == 14 -> days; days.isEmpty() -> List(14) { DayMinutes("", 0) }; else -> days }
    val max = (slots.maxOfOrNull { it.minutes.coerceAtLeast(0) } ?: 0).coerceAtLeast(1)
    SettingsCard {
        Column(Modifier.fillMaxWidth().padding(15.dp)) {
            Text("Daily reading · last 14 days", color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Row(Modifier.fillMaxWidth().height(88.dp).padding(top = 12.dp).testTag("stats-daily-chart"), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                slots.forEachIndexed { i, d ->
                    val frac = (d.minutes.coerceAtLeast(0).toFloat() / max).coerceIn(0f, 1f)
                    val isToday = i == slots.lastIndex
                    Box(Modifier.weight(1f).fillMaxWidth()) {
                        Box(
                            Modifier.fillMaxWidth().height((84 * frac).dp.coerceAtLeast(2.dp))
                                .clip(RoundedCornerShape(3.dp))
                                .background(if (isToday) t.tint else t.tint.copy(alpha = 0.38f))
                                .align(Alignment.BottomCenter),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun PerBookTable(books: List<BookStat>) {
    val t = LocalBackupTokens.current
    SettingsCard {
        Column(Modifier.fillMaxWidth().padding(horizontal = 15.dp, vertical = 13.dp)) {
            Row(Modifier.fillMaxWidth().padding(bottom = 9.dp)) {
                Text("BOOK", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                Text("TIME", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(70.dp))
                Text("HL", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(30.dp))
                Text("NT", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(30.dp))
            }
            if (books.isEmpty()) {
                Text("No books opened yet", color = t.ter, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, modifier = Modifier.padding(vertical = 16.dp).testTag("stats-perbook-empty"))
            } else {
                val maxM = books.maxOf { it.minutes }.coerceAtLeast(1)
                books.forEach { b ->
                    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp).testTag("book-${b.bookKey}")) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            Text(b.title, color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                            Text(formatMinutes(b.minutes), color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.width(70.dp))
                            Text("0", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.sp, modifier = Modifier.width(30.dp))   // Hl — until #1801
                            Text("0", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.sp, modifier = Modifier.width(30.dp))   // Nt — until #1801
                        }
                        // full-width track (padding BEFORE height so the bar keeps its 3dp) + clamped fill
                        Box(Modifier.fillMaxWidth().padding(top = 7.dp).height(3.dp).clip(RoundedCornerShape(2.dp)).background(t.sep)) {
                            val frac = (b.minutes.coerceAtLeast(0).toFloat() / maxM).coerceIn(0f, 1f)
                            Box(Modifier.fillMaxWidth(frac).height(3.dp).clip(RoundedCornerShape(2.dp)).background(t.tint.copy(alpha = 0.7f)))
                        }
                    }
                }
            }
        }
    }
}
