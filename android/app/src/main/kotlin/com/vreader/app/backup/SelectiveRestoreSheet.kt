// Purpose: feature #114 WI-5 (#110 Phase 3) — the selective restore picker (design surface E
// from vreader-backup-webdav.jsx SelectiveRestoreSheet): choose which books to restore from a
// backup manifest, where the per-book state is the whole point — `local` (on device), `remote`
// (downloads lazily on tap), `downloading` (inline progress), `failed` (tap to retry). A pinned
// footer totals the selection. Stateless: books + the selected set + callbacks.
package com.vreader.app.backup

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun SelectiveRestoreSheet(
    books: List<ManifestBook>,
    selected: Set<String>,
    whenLabel: String,
    onCancel: () -> Unit = {},
    onToggleSelectAll: () -> Unit = {},
    onToggle: (String) -> Unit = {},
    onRetry: (String) -> Unit = {},
    onRestore: () -> Unit = {},
) {
    val t = LocalBackupTokens.current
    val allSelected = selected.size == books.size && books.isNotEmpty()
    val localCount = books.count { it.id in selected && it.state == BookState.local }
    val downloadCount = selected.size - localCount

    Box(Modifier.fillMaxSize()) {
        AppSheet(
            title = "Choose Books",
            leading = {
                Box(Modifier.heightIn(min = 48.dp).clickable(onClick = onCancel), contentAlignment = Alignment.CenterStart) {
                    Text("Cancel", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
                }
            },
            trailing = {
                Box(Modifier.heightIn(min = 48.dp).clickable(onClick = onToggleSelectAll), contentAlignment = Alignment.CenterEnd) {
                    Text(if (allSelected) "Deselect all" else "Select all", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                }
            },
            footer = {
                Row(
                    Modifier.fillMaxWidth().background(t.sheetBg).padding(start = 18.dp, end = 18.dp, top = 12.dp, bottom = 26.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        Text("${selected.size} books selected", color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                        Text("$localCount already local · $downloadCount will download", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp)
                    }
                    Box(
                        Modifier.clip(RoundedCornerShape(12.dp)).background(t.tint).clickable(onClick = onRestore).padding(horizontal = 24.dp, vertical = 12.dp),
                    ) {
                        Text("Restore", color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
            },
        ) {
            Text(
                "From $whenLabel · ${books.size} books in this backup. Remote-only books download from the server as you restore.",
                color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 12.5.sp, lineHeight = 19.sp,
                modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 12.dp),
            )
            Column(Modifier.padding(horizontal = 18.dp).clip(RoundedCornerShape(14.dp)).background(t.card)) {
                books.forEachIndexed { i, b ->
                    ManifestRow(b, selected = b.id in selected, last = i == books.lastIndex, onToggle = onToggle, onRetry = onRetry)
                }
            }
            Box(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun ManifestRow(b: ManifestBook, selected: Boolean, last: Boolean, onToggle: (String) -> Unit, onRetry: (String) -> Unit) {
    val t = LocalBackupTokens.current
    Column(Modifier.alpha(if (selected) 1f else 0.55f)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 64.dp)
                .selectable(selected = selected, role = Role.Checkbox) { onToggle(b.id) }
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Checkbox.
            Box(
                Modifier.size(22.dp).clip(CircleShape).background(if (selected) t.tint else Color.Transparent),
                contentAlignment = Alignment.Center,
            ) {
                if (selected) Icon(Icons.Filled.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(14.dp))
                else Box(Modifier.size(22.dp).clip(CircleShape).background(t.sep))
            }
            // Cover.
            Box(
                Modifier.padding(start = 12.dp).size(width = 38.dp, height = 50.dp).clip(RoundedCornerShape(3.dp))
                    .background(Brush.linearGradient(listOf(Color(0xFF5A3A3A), Color(0xFF3A2424)))),
            )
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text(b.title, color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                if (b.author != null) {
                    Text(b.author, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp, maxLines = 1)
                }
                StateLine(b)
            }
            TrailingAffordance(b, onRetry)
        }
        if (!last) Box(Modifier.fillMaxWidth().padding(start = 48.dp).height(0.5.dp).background(t.sep))
    }
}

@Composable
private fun StateLine(b: ManifestBook) {
    val t = LocalBackupTokens.current
    when (b.state) {
        BookState.local -> Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
            StatusDot(t.green)
            Text("On this device", color = t.green, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 5.dp))
        }
        BookState.remote -> Text("Download · ${b.sizeLabel}", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp, modifier = Modifier.padding(top = 2.dp))
        BookState.downloading -> {
            val progress = b.progress.coerceIn(0f, 1f)
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                Box(Modifier.size(width = 120.dp, height = 3.dp).clip(RoundedCornerShape(2.dp)).background(t.sep)) {
                    Box(Modifier.fillMaxWidth(progress).height(3.dp).background(t.tint))
                }
                Text("${(progress * 100).toInt()}%", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 7.dp))
            }
        }
        BookState.failed -> Text("Download failed — tap to retry", color = t.red, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 2.dp))
    }
}

@Composable
private fun TrailingAffordance(b: ManifestBook, onRetry: (String) -> Unit) {
    val t = LocalBackupTokens.current
    when (b.state) {
        BookState.local -> Icon(Icons.Filled.Check, contentDescription = null, tint = t.green, modifier = Modifier.size(20.dp))
        BookState.remote -> Box(Modifier.size(30.dp).clip(CircleShape).background(t.chipBg), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.Download, contentDescription = null, tint = t.tint, modifier = Modifier.size(18.dp))
        }
        BookState.downloading -> Text("…", color = t.tint, fontSize = 18.sp)
        BookState.failed -> Box(
            Modifier.size(44.dp).clickable(onClickLabel = "Retry") { onRetry(b.id) }.semantics { contentDescription = "Retry" },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Refresh, contentDescription = null, tint = t.red, modifier = Modifier.size(20.dp))
        }
    }
}
