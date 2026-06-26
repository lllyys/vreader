// Purpose: feature #120 WI-2 (#110 Phase 3) — the OPDS catalog list (design `vreader-opds.jsx`
// `OpdsSourceList`): empty onboards with a Globe tile + "Try one of these" suggested catalogs;
// populated shows saved rows with a status dot + host, tap-to-browse. Reuses the shared backup form
// vocabulary (NavScreen / SettingsCard / GroupHeader / GroupFooter / StatusDot / tokens). Stateless:
// a pure function of the list + callbacks.
package com.vreader.app.opds.ui

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
import androidx.compose.material.icons.filled.Public
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
import androidx.compose.ui.text.style.TextOverflow
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

/** The catalogs the empty state offers as one-tap shortcuts (name + OPDS feed URL, prefilled). */
val OpdsSuggestedCatalogs: List<Pair<String, String>> = listOf(
    "Standard Ebooks" to "https://standardebooks.org/opds",
    "Project Gutenberg" to "https://m.gutenberg.org/ebooks.opds/",
    "Feedbooks" to "https://catalog.feedbooks.com/catalog/index.atom",
)

private val AuthDot = Color(0xFFCAA23A)  // the design's amber "sign-in required" dot

@Composable
fun OpdsSourceListScreen(
    state: OpdsSourceListState,
    onBack: () -> Unit = {},
    onAdd: () -> Unit = {},
    onPickSuggested: (name: String, url: String) -> Unit = { _, _ -> },
    onBrowse: (String) -> Unit = {},
) {
    val t = LocalBackupTokens.current
    val addButton: @Composable () -> Unit = {
        Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable(onClickLabel = "Add catalog", onClick = onAdd).testTag("opds-add"),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Filled.Add, contentDescription = "Add catalog", tint = t.tint, modifier = Modifier.size(22.dp)) }
    }
    NavScreen(title = "Catalogs", large = true, onBack = onBack, trailing = addButton) {
        Column(Modifier.padding(horizontal = 18.dp).padding(bottom = 32.dp)) {
            if (state.empty) EmptyState(onAdd, onPickSuggested)
            else {
                GroupHeader("Your catalogs")
                SettingsCard {
                    state.sources.forEachIndexed { i, s ->
                        SourceRow(s, last = i == state.sources.lastIndex, onBrowse = onBrowse)
                    }
                }
                GroupFooter("Tap a catalog to browse it. The status dot reflects its sign-in configuration.")
            }
        }
    }
}

@Composable
private fun EmptyState(onAdd: () -> Unit, onPickSuggested: (String, String) -> Unit) {
    val t = LocalBackupTokens.current
    Column(Modifier.fillMaxWidth().padding(top = 36.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(62.dp).clip(CircleShape).background(t.chipBg), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Public, contentDescription = null, tint = t.ter, modifier = Modifier.size(30.dp))
        }
        VSpace(18)
        Text("Add a catalog", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 21.sp, textAlign = TextAlign.Center)
        VSpace(8)
        Text(
            "Browse and download books from any OPDS catalog — public libraries or your own Calibre server.",
            color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 14.sp, lineHeight = 22.sp, textAlign = TextAlign.Center,
        )
        VSpace(20)
    }
    GroupHeader("Try one of these")
    SettingsCard {
        OpdsSuggestedCatalogs.forEachIndexed { i, (name, url) ->
            SuggestedRow(name, url, last = i == OpdsSuggestedCatalogs.lastIndex, onPick = onPickSuggested)
        }
    }
    GroupFooter("Or tap + to add any catalog by URL.")
}

@Composable
private fun SuggestedRow(name: String, url: String, last: Boolean, onPick: (String, String) -> Unit) {
    val t = LocalBackupTokens.current
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 50.dp).clickable(onClick = { onPick(name, url) })
                .testTag("suggest-$name").padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Public, contentDescription = null, tint = t.tint, modifier = Modifier.size(19.dp))
            Text(name, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).padding(start = 11.dp))
            Icon(Icons.Filled.Add, contentDescription = "Add $name", tint = t.tint, modifier = Modifier.size(19.dp))
        }
        if (!last) Box(Modifier.fillMaxWidth().padding(start = 44.dp).height(0.5.dp).background(t.sep).align(Alignment.BottomStart))
    }
}

@Composable
private fun SourceRow(s: OpdsSourceRow, last: Boolean, onBrowse: (String) -> Unit) {
    val t = LocalBackupTokens.current
    val dotColor = when (s.status) {
        OpdsSourceStatus.ok -> t.green
        OpdsSourceStatus.auth -> AuthDot
        OpdsSourceStatus.off -> t.red
        OpdsSourceStatus.unknown -> t.ter
    }
    val detailColor = if (s.status == OpdsSourceStatus.off) t.red else t.sec
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 58.dp).clickable(onClick = { onBrowse(s.id) })
                .testTag("source-${s.id}").padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(s.name, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.5.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 3.dp)) {
                    StatusDot(dotColor)
                    Text(s.detail, color = detailColor, fontFamily = BackupFonts.Mono, fontSize = 11.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 6.dp))
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = t.ter, modifier = Modifier.size(18.dp))
        }
        if (!last) Box(Modifier.fillMaxWidth().padding(start = 14.dp).height(0.5.dp).background(t.sep).align(Alignment.BottomStart))
    }
}
