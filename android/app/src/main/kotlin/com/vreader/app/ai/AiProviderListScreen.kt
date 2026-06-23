// Purpose: feature #118 WI-3 (#110 Phase 3) — the AI provider list (the gate), design surface A
// from vreader-ai-android.jsx `AiProviderList`: unconfigured onboards to a single Add action;
// configured shows the active provider + per-provider status (model, or the rejection reason).
// Reuses the shared form vocabulary (NavScreen / SettingsCard / GroupHeader / StatusDot / tokens —
// mapped from this surface's own design file). Stateless: a pure function of the list + callbacks.
package com.vreader.app.ai

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.Icon
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
import com.vreader.app.backup.BackupFonts
import com.vreader.app.backup.GroupFooter
import com.vreader.app.backup.GroupHeader
import com.vreader.app.backup.LocalBackupTokens
import com.vreader.app.backup.NavScreen
import com.vreader.app.backup.SettingsCard
import com.vreader.app.backup.StatusDot
import com.vreader.app.backup.VSpace

@Composable
fun AiProviderListScreen(
    state: AiProviderListState,
    onBack: () -> Unit = {},
    onAdd: () -> Unit = {},
    onEdit: (String) -> Unit = {},
) {
    val t = LocalBackupTokens.current
    val addButton: @Composable () -> Unit = {
        Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable(onClickLabel = "Add provider", onClick = onAdd),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Filled.Add, contentDescription = "Add provider", tint = t.tint, modifier = Modifier.size(22.dp)) }
    }
    NavScreen(title = "AI Providers", large = true, onBack = onBack, trailing = addButton) {
        Column(Modifier.padding(horizontal = 18.dp).padding(bottom = 32.dp)) {
            if (state.unconfigured) {
                AiEmptyState(onAdd)
            } else {
                GroupHeader("Providers")
                SettingsCard {
                    state.providers.forEachIndexed { i, p ->
                        ProviderRow(p, last = i == state.providers.lastIndex, onEdit = onEdit)
                    }
                }
                GroupFooter("The selected provider is used for translation, chat, and summaries. Tap one to edit or test it.")
            }
        }
    }
}

@Composable
private fun AiEmptyState(onAdd: () -> Unit) {
    val t = LocalBackupTokens.current
    Column(Modifier.fillMaxWidth().padding(top = 36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(64.dp).clip(CircleShape).background(t.chipBg), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = t.tint, modifier = Modifier.size(30.dp))
        }
        VSpace(18)
        Text("Connect an AI provider", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 21.sp, textAlign = TextAlign.Center)
        VSpace(8)
        Text(
            "One key unlocks bilingual translation, chat about a book, and chapter summaries. Your key is stored on-device only.",
            color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 14.sp, lineHeight = 22.sp, textAlign = TextAlign.Center,
        )
        VSpace(18)
        Box(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(13.dp)).background(t.tint)
                .clickable(onClickLabel = "Add a provider", onClick = onAdd).testTag("ai-add-provider").padding(vertical = 14.dp),
            contentAlignment = Alignment.Center,
        ) { Text("Add a provider", color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
        GroupFooter("Works with Anthropic, OpenAI-compatible endpoints, and local models.")
    }
}

@Composable
private fun ProviderRow(p: AiProviderRow, last: Boolean, onEdit: (String) -> Unit) {
    val t = LocalBackupTokens.current
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 60.dp).clickable(onClick = { onEdit(p.id) })
                .testTag("provider-${p.id}").padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // active = filled accent circle; inactive = hollow ring (sep ring + card-coloured core)
            Box(
                Modifier.size(20.dp).clip(CircleShape).background(if (p.active) t.tint else t.sep),
                contentAlignment = Alignment.Center,
            ) {
                if (!p.active) Box(Modifier.size(16.5.dp).clip(CircleShape).background(t.card))
            }
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text(p.name, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.5.sp, fontWeight = FontWeight.Medium)
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
                    StatusDot(if (p.statusOk) t.green else t.red)
                    Text(
                        p.detail, color = if (p.statusOk) t.sec else t.red,
                        fontFamily = BackupFonts.Mono, fontSize = 11.5.sp, modifier = Modifier.padding(start = 6.dp),
                    )
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = t.ter, modifier = Modifier.size(18.dp))
        }
        if (!last) Box(Modifier.fillMaxWidth().padding(start = 46.dp).height(0.5.dp).background(t.sep).align(Alignment.BottomStart))
    }
}
