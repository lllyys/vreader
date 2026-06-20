// Purpose: feature #114 WI-4 (#110 Phase 3) — the restore flow (design surface D from
// vreader-backup-webdav.jsx RestoreProgress + the confirm alert): a confirm dialog stating the
// merge rules ("Nothing is deleted"), an in-progress radial ring with a book-by-book label +
// Cancel, and the three distinct results (success → Done, partial → Done + Retry, failed →
// library-unchanged → Try Again). "Restore never deletes" appears in the confirm + the success
// copy. Stateless: a pure function of RestoreProgress + callbacks.
package com.vreader.app.backup

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.PriorityHigh
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

private val PartialAmber = Color(0xFFC79A2E)

@Composable
fun RestoreScreen(
    progress: RestoreProgress,
    onBack: () -> Unit = {},
    onCancel: () -> Unit = {},
    onDone: () -> Unit = {},
    onRetry: () -> Unit = {},
    onTryAgain: () -> Unit = {},
) {
    val t = LocalBackupTokens.current
    // Self-contained Box/Column root (does not rely on the caller being a Box).
    Column(Modifier.fillMaxSize().background(t.bg).systemBarsPadding()) {
        BackupTopBar("Restore", large = false, onBack = onBack)
        Column(
            Modifier.weight(1f).fillMaxWidth().padding(horizontal = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            when (progress) {
                is RestoreProgress.InProgress -> InProgressContent(progress)
                is RestoreProgress.Result -> ResultContent(progress)
            }
        }
        Box(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 30.dp)) {
            when (progress) {
                is RestoreProgress.InProgress -> OutlineButton("Cancel", onCancel)
                is RestoreProgress.Result -> when (progress.outcome) {
                    RestoreOutcome.success -> FilledButton("Done", onDone)
                    RestoreOutcome.partial -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Box(Modifier.weight(1f)) { OutlineButton("Done", onDone) }
                        Box(Modifier.weight(1f)) { FilledButton("Retry ${progress.failed} Books", onRetry) }
                    }
                    RestoreOutcome.failed -> Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        Box(Modifier.weight(1f)) { OutlineButton("Back", onCancel) }
                        Box(Modifier.weight(1f)) { FilledButton("Try Again", onTryAgain) }
                    }
                }
            }
        }
    }
}

@Composable
private fun InProgressContent(p: RestoreProgress.InProgress) {
    val t = LocalBackupTokens.current
    val pct = (if (p.total == 0) 0f else p.done.toFloat() / p.total).coerceIn(0f, 1f)
    ProgressRing(fraction = pct, ringColor = t.tint) {
        Text("${(pct * 100).toInt()}%", color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 22.sp, fontWeight = FontWeight.Bold)
    }
    Text("Restoring your library", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 24.dp))
    Text(
        "Downloading book ${p.done} of ${p.total} · ${p.currentTitle}", color = t.sec,
        fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, lineHeight = 21.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp),
    )
    Column(Modifier.widthIn(max = 280.dp).fillMaxWidth().padding(top = 22.dp)) {
        Box(Modifier.fillMaxWidth().height(5.dp).clip(RoundedCornerShape(3.dp)).background(t.sep)) {
            Box(Modifier.fillMaxWidth(pct).height(5.dp).clip(RoundedCornerShape(3.dp)).background(t.tint))
        }
        Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("${p.done} / ${p.total} books", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp)
        }
    }
}

@Composable
private fun ResultContent(r: RestoreProgress.Result) {
    val t = LocalBackupTokens.current
    val (color, icon, title, sub) = when (r.outcome) {
        RestoreOutcome.success -> ResultMeta(
            t.green, Icons.Filled.Check, "Restore complete",
            "${r.total} of ${r.total} books restored${if (r.whenLabel.isNotBlank()) " from ${r.whenLabel}" else ""}. Nothing in your library was deleted.",
        )
        RestoreOutcome.partial -> ResultMeta(PartialAmber, Icons.Filled.PriorityHigh, "Restored with issues", "${r.restored} of ${r.total} books restored. ${r.failed} couldn’t be downloaded — retry them below.")
        RestoreOutcome.failed -> ResultMeta(t.red, Icons.Filled.Close, "Restore failed", "The connection dropped before any books were restored. Your library is unchanged.")
    }
    ProgressRing(fraction = 1f, ringColor = color) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(40.dp))
    }
    Text(title, color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 20.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 24.dp))
    Text(sub, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, lineHeight = 21.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
}

private data class ResultMeta(val color: Color, val icon: androidx.compose.ui.graphics.vector.ImageVector, val title: String, val sub: String)

@Composable
private fun ProgressRing(fraction: Float, ringColor: Color, center: @Composable () -> Unit) {
    val t = LocalBackupTokens.current
    Box(Modifier.size(96.dp), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(96.dp)) {
            val stroke = 6.dp.toPx()
            drawArc(color = t.sep, startAngle = 0f, sweepAngle = 360f, useCenter = false, style = Stroke(width = stroke))
            drawArc(
                color = ringColor, startAngle = -90f, sweepAngle = 360f * fraction.coerceIn(0f, 1f),
                useCenter = false, style = Stroke(width = stroke, cap = StrokeCap.Round),
            )
        }
        center()
    }
}

@Composable
private fun FilledButton(label: String, onClick: () -> Unit) {
    val t = LocalBackupTokens.current
    Box(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(t.tint).clickable(onClick = onClick).height(46.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun OutlineButton(label: String, onClick: () -> Unit) {
    val t = LocalBackupTokens.current
    Box(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(t.sheetBg).clickable(onClick = onClick).height(46.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.Medium)
    }
}

/** The pre-restore confirm dialog — states the merge rules ("Nothing is deleted"). */
@Composable
fun RestoreConfirmDialog(bookCount: Int, whenLabel: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val t = LocalBackupTokens.current
    AppAlert(
        title = "Restore this backup?",
        message = buildAnnotatedString {
            append("Merges ")
            withStyle(SpanStyle(color = t.ink, fontWeight = FontWeight.SemiBold)) { append("$bookCount books") }
            append(" from ")
            withStyle(SpanStyle(color = t.ink, fontWeight = FontWeight.SemiBold)) { append(whenLabel) }
            append(" into your library. Nothing is deleted — existing books and progress are kept, newer versions win.")
        },
        confirmLabel = "Restore",
        onConfirm = onConfirm,
        onDismiss = onDismiss,
    )
}
