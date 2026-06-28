// Purpose: feature #122 WI-3 (#110 Phase 3) — the in-reader reading-time surfaces (design
// vreader-stats-android.jsx `InReaderTime`): a glassy session pill (auto-fade is the host's concern)
// + the time-detail card (session · book total · left · pace). Uses the reader's VReaderColors/
// VReaderFonts. Stateless: pure functions of the inputs.
package com.vreader.app.stats

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.ui.theme.VReaderColors
import com.vreader.app.ui.theme.VReaderFonts
import java.util.Locale

/** The session pill: timer glyph + MM:SS + "this session". The host (#122 WI-4) handles auto-fade. */
@Composable
fun InReaderSessionPill(sessionSeconds: Long, modifier: Modifier = Modifier) {
    val c = VReaderColors
    Row(
        modifier.clip(RoundedCornerShape(100.dp)).background(c.Surface).padding(horizontal = 13.dp, vertical = 7.dp).testTag("stats-session-pill"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.Schedule, contentDescription = null, tint = c.Accent, modifier = Modifier.size(15.dp))
        Text(formatClock(sessionSeconds), color = c.Ink, fontFamily = VReaderFonts.Sans, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 7.dp))
        Text("this session", color = c.InkMuted, fontFamily = VReaderFonts.Sans, fontSize = 12.sp, modifier = Modifier.padding(start = 5.dp))
    }
}

/** The time-detail card: book + progress + 4 stat cells + the pace line. */
@Composable
fun InReaderTimeDetailCard(stats: InReaderStats, bookTitle: String, progressPercent: Int, modifier: Modifier = Modifier) {
    val c = VReaderColors
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(c.Surface).padding(16.dp).testTag("stats-detail-card"),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(bookTitle, color = c.Ink, fontFamily = VReaderFonts.Serif, fontSize = 16.sp, modifier = Modifier.weight(1f))
            Text("$progressPercent%", color = c.InkMuted, fontFamily = VReaderFonts.Sans, fontSize = 12.sp)
        }
        Row(Modifier.fillMaxWidth().padding(top = 12.dp)) {
            Cell("This session", formatClock(stats.sessionSeconds), Modifier.weight(1f))
            Cell("Total in book", formatMinutes(stats.bookTotalMinutes), Modifier.weight(1f))
        }
        Row(Modifier.fillMaxWidth().padding(top = 12.dp)) {
            Cell("Left in book", "~" + formatMinutes(stats.timeLeftMinutes), Modifier.weight(1f))
            Cell("Pace", stats.pace?.let { "$it wpm" } ?: "—", Modifier.weight(1f))
        }
    }
}

@Composable
private fun Cell(label: String, value: String, modifier: Modifier) {
    val c = VReaderColors
    Column(modifier) {
        Text(label, color = c.InkMuted, fontFamily = VReaderFonts.Sans, fontSize = 11.5.sp)
        Text(value, color = c.Ink, fontFamily = VReaderFonts.Serif, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 1.dp))
    }
}

internal fun formatClock(totalSeconds: Long): String {
    val s = totalSeconds.coerceAtLeast(0)
    val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
    return if (h > 0) String.format(Locale.ROOT, "%d:%02d:%02d", h, m, sec) else String.format(Locale.ROOT, "%d:%02d", m, sec)
}

internal fun formatMinutes(minutes: Int): String {
    val m = minutes.coerceAtLeast(0)
    val h = m / 60; val rem = m % 60
    return if (h > 0) "${h}h ${rem}m" else "${rem}m"
}
