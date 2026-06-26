// Purpose: feature #121 WI-4 (#110 Phase 3) — the voice/engine sheet (design vreader-tts.jsx
// `VoiceSheet`): the on-device engine list + the per-locale voice list (selected check / network /
// not-installed → Download). Reuses the backup AppSheet/SettingsCard + BackupTokens. Stateless.
package com.vreader.app.tts

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Download
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.backup.AppSheet
import com.vreader.app.backup.BackupFonts
import com.vreader.app.backup.GroupFooter
import com.vreader.app.backup.GroupHeader
import com.vreader.app.backup.LocalBackupTokens
import com.vreader.app.backup.SettingsCard
import com.vreader.app.backup.VSpace

@Composable
fun TtsVoiceSheet(
    state: TtsVoiceListState,
    onEngine: (TtsEngineOption) -> Unit = {},
    onVoice: (TtsVoiceOption) -> Unit = {},
    onInstall: (TtsVoiceOption) -> Unit = {},
    onDone: () -> Unit = {},
) {
    val t = LocalBackupTokens.current
    AppSheet(
        title = "Voice",
        leading = {},
        trailing = {
            Box(Modifier.clickable(onClick = onDone).testTag("voice-done")) {
                Text("Done", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            }
        },
    ) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 28.dp)) {
            if (state.engines.isNotEmpty()) {
                GroupHeader("Engine")
                SettingsCard {
                    state.engines.forEachIndexed { i, e ->
                        Row(
                            Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable { onEngine(e) }.testTag("engine-${e.id}").padding(horizontal = 14.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(e.label, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.5.sp, modifier = Modifier.weight(1f))
                            if (e.id == state.selectedEngineId) Icon(Icons.Filled.Check, contentDescription = "Selected", tint = t.tint, modifier = Modifier.size(20.dp))
                        }
                        if (i < state.engines.lastIndex) Box(Modifier.fillMaxWidth().padding(start = 14.dp).height(0.5.dp).background(t.sep))
                    }
                }
                GroupFooter("Engines are provided by Android. Add more in System settings → Text-to-speech.")
                VSpace(18)
            }
            GroupHeader("Voices")
            SettingsCard {
                if (state.voices.isEmpty()) {
                    Box(Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(14.dp), contentAlignment = Alignment.CenterStart) {
                        Text("No voices for this language", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 14.sp)
                    }
                } else state.voices.forEachIndexed { i, v ->
                    VoiceRow(v, selected = v.name == state.selectedVoiceName, onVoice = onVoice, onInstall = onInstall)
                    if (i < state.voices.lastIndex) Box(Modifier.fillMaxWidth().padding(start = 14.dp).height(0.5.dp).background(t.sep))
                }
            }
            GroupFooter("VReader follows the book's language when a matching voice is installed.")
        }
    }
}

@Composable
private fun VoiceRow(v: TtsVoiceOption, selected: Boolean, onVoice: (TtsVoiceOption) -> Unit, onInstall: (TtsVoiceOption) -> Unit) {
    val t = LocalBackupTokens.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp).clickable { if (v.notInstalled) onInstall(v) else onVoice(v) }.testTag("voice-${v.name}").padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(v.label, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.5.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val sub = when { v.notInstalled -> "Not installed"; v.networkRequired -> "Network required"; else -> "On-device" }
            Text(sub, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 12.5.sp, modifier = Modifier.padding(top = 1.dp))
        }
        when {
            v.notInstalled -> Icon(Icons.Filled.Download, contentDescription = "Download voice", tint = t.tint, modifier = Modifier.size(20.dp))
            selected -> Icon(Icons.Filled.Check, contentDescription = "Selected", tint = t.tint, modifier = Modifier.size(20.dp))
        }
    }
}
