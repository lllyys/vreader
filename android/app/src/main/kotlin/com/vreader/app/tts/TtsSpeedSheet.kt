// Purpose: feature #121 WI-4 (#110 Phase 3) — the speaking-rate sheet (design vreader-tts.jsx
// `SpeedSheet`): the current rate large + preset pills (0.5×–2.0×). Reuses the backup AppSheet +
// BackupTokens. Stateless: a pure function of the rate + callbacks.
package com.vreader.app.tts

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.backup.AppSheet
import com.vreader.app.backup.BackupFonts
import com.vreader.app.backup.LocalBackupTokens
import com.vreader.app.backup.VSpace
import java.util.Locale

private val PRESETS = listOf(0.5f, 0.75f, 1.0f, 1.25f, 1.5f, 1.75f, 2.0f)

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TtsSpeedSheet(rate: Float, onRate: (Float) -> Unit = {}, onDone: () -> Unit = {}) {
    val t = LocalBackupTokens.current
    AppSheet(
        title = "Speaking rate",
        leading = {},
        trailing = {
            Box(Modifier.clickable(onClick = onDone).testTag("speed-done"), contentAlignment = Alignment.CenterEnd) {
                Text("Done", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            }
        },
    ) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(rateLabel(rate), color = t.tint, fontFamily = BackupFonts.Serif, fontSize = 40.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, modifier = Modifier.testTag("speed-current"))
            VSpace(18)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally), verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                PRESETS.forEach { p ->
                    val on = kotlin.math.abs(p - rate) < 0.001f
                    Box(
                        Modifier.clip(RoundedCornerShape(100.dp)).background(if (on) t.tint else t.chipBg).clickable { onRate(p) }.testTag("speed-${rateLabel(p)}").padding(horizontal = 14.dp, vertical = 8.dp),
                    ) { Text(rateLabel(p), color = if (on) Color.White else t.ink, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, fontWeight = if (on) FontWeight.Bold else FontWeight.Medium) }
                }
            }
            VSpace(16)
        }
    }
}

private fun rateLabel(r: Float) = "${String.format(Locale.ROOT, "%.2f", r).trimEnd('0').trimEnd('.')}×"
