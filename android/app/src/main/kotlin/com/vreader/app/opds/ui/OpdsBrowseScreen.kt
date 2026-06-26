// Purpose: feature #120 WI-3 (#110 Phase 3) — the OPDS browse screen (design `vreader-opds.jsx`
// `OpdsBrowse`): navigation rows (drill into sub-feeds) + acquisition entries (cover tile + title/
// author + format badge + Get / downloading-radial / In-Library), with loading / empty / error
// phases and a Load-more affordance. Reuses the shared backup vocabulary. Stateless.
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.CircularProgressIndicator
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
import com.vreader.app.backup.GroupHeader
import com.vreader.app.backup.LocalBackupTokens
import com.vreader.app.backup.NavScreen
import com.vreader.app.backup.VSpace

@Composable
fun OpdsBrowseScreen(
    state: OpdsBrowseState,
    onBack: () -> Unit = {},
    onNavigate: (OpdsNavRow) -> Unit = {},
    onDownload: (String) -> Unit = {},
    onRetry: () -> Unit = {},
    onEditSource: () -> Unit = {},
    onLoadMore: () -> Unit = {},
) {
    NavScreen(title = state.title, onBack = onBack) {
        when (state.phase) {
            OpdsBrowsePhase.loading -> LoadingShimmer()
            OpdsBrowsePhase.error -> OpdsErrorView(state.errorKind ?: OpdsBrowseError.generic, onRetry = onRetry, onEditSource = onEditSource)
            OpdsBrowsePhase.empty -> EmptyShelf()
            OpdsBrowsePhase.feed -> Feed(state, onNavigate, onDownload, onLoadMore)
        }
    }
}

@Composable
private fun Feed(state: OpdsBrowseState, onNavigate: (OpdsNavRow) -> Unit, onDownload: (String) -> Unit, onLoadMore: () -> Unit) {
    val t = LocalBackupTokens.current
    Column(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
        if (state.navRows.isNotEmpty()) {
            VSpace(6)
            state.navRows.forEach { NavRow(it, onNavigate) }
        }
        if (state.entries.isNotEmpty()) {
            Box(Modifier.padding(start = 16.dp, top = 12.dp, bottom = 2.dp)) {
                GroupHeader(state.sectionTitle ?: "Books")
            }
            state.entries.forEachIndexed { i, e -> AcquisitionEntry(e, last = i == state.entries.lastIndex, onDownload = onDownload) }
        }
        if (state.canLoadMore) {
            Box(
                Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(enabled = !state.loadingMore, onClick = onLoadMore).testTag("opds-load-more"),
                contentAlignment = Alignment.Center,
            ) {
                if (state.loadingMore) CircularProgressIndicator(Modifier.size(20.dp), color = t.tint, strokeWidth = 2.dp)
                else Text("Load more", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun NavRow(row: OpdsNavRow, onNavigate: (OpdsNavRow) -> Unit) {
    val t = LocalBackupTokens.current
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 50.dp).clickable(onClick = { onNavigate(row) }).testTag("nav-${row.title}").padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Folder, contentDescription = null, tint = t.tint, modifier = Modifier.size(19.dp))
            Text(row.title, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).padding(start = 11.dp))
            if (row.count != null) Text(row.count, color = t.ter, fontFamily = BackupFonts.Sans, fontSize = 12.5.sp, modifier = Modifier.padding(end = 8.dp))
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = t.ter, modifier = Modifier.size(18.dp))
        }
        Box(Modifier.fillMaxWidth().padding(start = 46.dp).height(0.5.dp).background(t.sep).align(Alignment.BottomStart))
    }
}

@Composable
private fun AcquisitionEntry(e: OpdsEntryRow, last: Boolean, onDownload: (String) -> Unit) {
    val t = LocalBackupTokens.current
    Box {
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
            // tonal mini-cover (no remote image fetch in v1 — design's MiniCover)
            Box(Modifier.size(width = 52.dp, height = 78.dp).clip(RoundedCornerShape(5.dp)).background(coverTone(e.key, t.isDark)))
            Column(Modifier.weight(1f).padding(start = 13.dp)) {
                Text(e.title, color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 15.5.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                if (e.author != null) Text(e.author, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 12.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 8.dp)) {
                    Box(Modifier.clip(RoundedCornerShape(5.dp)).background(t.codeBg).padding(horizontal = 6.dp, vertical = 2.dp)) {
                        Text(e.format, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 9.5.sp, fontWeight = FontWeight.Bold)
                    }
                    if (e.state == OpdsItemState.failed && e.failMessage != null) {
                        Text(e.failMessage, color = t.red, fontFamily = BackupFonts.Sans, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(start = 8.dp))
                    }
                }
            }
            Box(Modifier.padding(start = 8.dp)) { EntryAction(e, onDownload) }
        }
        if (!last) Box(Modifier.fillMaxWidth().padding(start = 81.dp).height(0.5.dp).background(t.sep).align(Alignment.BottomStart))
    }
}

@Composable
private fun EntryAction(e: OpdsEntryRow, onDownload: (String) -> Unit) {
    val t = LocalBackupTokens.current
    when (e.state) {
        OpdsItemState.downloading -> CircularProgressIndicator(Modifier.size(28.dp).testTag("dl-progress-${e.key}"), color = t.tint, strokeWidth = 3.dp)
        OpdsItemState.library -> Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("dl-library-${e.key}")) {
            Icon(Icons.Filled.Check, contentDescription = null, tint = t.green, modifier = Modifier.size(16.dp))
            Text("In Library", color = t.green, fontFamily = BackupFonts.Sans, fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 5.dp))
        }
        else -> Row(  // remote OR failed → a Get / Retry chip
            Modifier.clip(RoundedCornerShape(100.dp)).background(t.chipBg).clickable(onClick = { onDownload(e.key) }).testTag("dl-get-${e.key}").padding(horizontal = 14.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Download, contentDescription = null, tint = t.tint, modifier = Modifier.size(15.dp))
            Text(if (e.state == OpdsItemState.failed) "Retry" else "Get", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 6.dp))
        }
    }
}

@Composable
private fun LoadingShimmer() {
    val t = LocalBackupTokens.current
    Column(Modifier.fillMaxWidth().padding(top = 8.dp).testTag("opds-loading")) {
        repeat(4) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 13.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(width = 52.dp, height = 78.dp).clip(RoundedCornerShape(5.dp)).background(t.sep.copy(alpha = 0.6f)))
                Column(Modifier.weight(1f).padding(start = 13.dp)) {
                    Box(Modifier.fillMaxWidth(0.7f).height(13.dp).clip(RoundedCornerShape(4.dp)).background(t.sep.copy(alpha = 0.6f)))
                    VSpace(8)
                    Box(Modifier.fillMaxWidth(0.4f).height(11.dp).clip(RoundedCornerShape(4.dp)).background(t.sep.copy(alpha = 0.4f)))
                }
            }
        }
        Text("Loading feed…", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.sp, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(14.dp))
    }
}

@Composable
private fun EmptyShelf() {
    val t = LocalBackupTokens.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 30.dp, vertical = 80.dp).testTag("opds-empty"), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(60.dp).clip(RoundedCornerShape(30.dp)).background(t.chipBg), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Folder, contentDescription = null, tint = t.ter, modifier = Modifier.size(28.dp))
        }
        VSpace(18)
        Text("This shelf is empty", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 19.sp, textAlign = TextAlign.Center)
        VSpace(8)
        Text("The catalog returned no entries for this feed. Try another section.", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 14.sp, lineHeight = 21.sp, textAlign = TextAlign.Center)
    }
}

/** A deterministic tonal cover from the entry key (no remote image fetch in v1). */
private fun coverTone(key: String, dark: Boolean): Color {
    val palette = if (dark)
        listOf(0xFF3A4A5C, 0xFF5C2F3A, 0xFF2F4630, 0xFF3A3550, 0xFF4A4030, 0xFF2F4A4A)
    else
        listOf(0xFF6E8196, 0xFF9C6470, 0xFF5E8062, 0xFF6E6890, 0xFF8A7A55, 0xFF5E8585)
    return Color(palette[(key.hashCode().and(0x7FFFFFFF)) % palette.size])
}
