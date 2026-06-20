// Purpose: feature #114 WI-2 (#110 Phase 3) — the Backup & Restore screen (design surface C),
// recreated from vreader-backup-webdav.jsx's BackupRestoreScreen across its states: idle
// (active-server header + Back Up Now + the backups list), loading, empty, and every WebDAV
// error (401/404/offline/timeout) — each naming its cause + the one CTA that fixes it.
// Stateless: a pure function of BackupUiState + callbacks (the BackupViewModel drives it).
package com.vreader.app.backup

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun BackupRestoreScreen(
    state: BackupUiState,
    onBack: () -> Unit = {},
    onBackUpNow: () -> Unit = {},
    onRestore: (String) -> Unit = {},
    onErrorCta: (WebDavError) -> Unit = {},
) {
    val t = LocalBackupTokens.current
    NavScreen(title = "Backup & Restore", large = true, onBack = onBack) {
        Column(Modifier.padding(horizontal = 18.dp).padding(bottom = 32.dp)) {
            BackupHeaderCard(state.activeServer, state.syncing, onBackUpNow)

            VSpace(22)
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 2.dp),
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                GroupHeader("Available Backups")
                // The design shows the active-server name beside the header only when idle.
                if (state.list is BackupListUi.Idle && state.activeServer != null) {
                    Text(state.activeServer.name, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 12.sp)
                }
            }

            when (val list = state.list) {
                is BackupListUi.Loading -> LoadingCard()
                is BackupListUi.Idle -> {
                    SettingsCard {
                        list.backups.forEachIndexed { i, b ->
                            BackupItemRow(b, last = i == list.backups.lastIndex, onRestore = onRestore)
                        }
                    }
                    GroupFooter("Restoring merges a backup into your current library — nothing is deleted. Use selective restore to pick individual books.")
                }
                is BackupListUi.Empty -> EmptyBlock()
                is BackupListUi.Error -> ErrorBlock(list.cause, state.activeServer, onErrorCta)
            }
        }
    }
}

@Composable
private fun BackupHeaderCard(server: ServerSummary?, syncing: Syncing?, onBackUpNow: () -> Unit) {
    val t = LocalBackupTokens.current
    SettingsCard {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                StatusDot(t.green)
                Text(
                    "ACTIVE SERVER", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 8.dp),
                )
            }
            Text(
                server?.name ?: "No server", color = t.ink, fontFamily = BackupFonts.Sans,
                fontSize = 16.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 8.dp),
            )
            Text(
                server?.url ?: "—", color = t.sec, fontFamily = BackupFonts.Mono, fontSize = 12.sp,
                modifier = Modifier.padding(top = 2.dp),
            )
            Box(Modifier.padding(top = 14.dp)) {
                if (syncing != null) {
                    PrimaryButton(
                        "Backing up… ${syncing.done} / ${syncing.total}", filled = false, onClick = {},
                    )
                } else {
                    PrimaryButton("Back Up Now", filled = true, onClick = onBackUpNow)
                }
            }
        }
    }
}

@Composable
private fun BackupItemRow(b: BackupSummary, last: Boolean, onRestore: (String) -> Unit) {
    val t = LocalBackupTokens.current
    Column {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 60.dp).padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(b.whenLabel, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    if (b.latest) {
                        Box(Modifier.padding(start = 8.dp)) { BackupTag("Latest") }
                    }
                }
                Text(
                    "${b.books} books · ${b.sizeLabel} · ${b.device}", color = t.sec,
                    fontFamily = BackupFonts.Sans, fontSize = 12.sp, modifier = Modifier.padding(top = 3.dp),
                )
            }
            Box(
                Modifier
                    .clip(RoundedCornerShape(100.dp))
                    .border(1.dp, t.tint.copy(alpha = 0.3f), RoundedCornerShape(100.dp))
                    .clickableRow { onRestore(b.id) }
                    .padding(horizontal = 14.dp, vertical = 6.dp),
            ) {
                Text("Restore", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        if (!last) HairLine(insetStart = 14)
    }
}

@Composable
private fun LoadingCard() {
    val t = LocalBackupTokens.current
    SettingsCard {
        repeat(3) { i ->
            Column(Modifier.fillMaxWidth().heightIn(min = 60.dp).padding(14.dp)) {
                Box(Modifier.fillMaxWidth(0.46f).height(11.dp).clip(RoundedCornerShape(3.dp)).background(t.sep))
                Box(Modifier.padding(top = 7.dp).fillMaxWidth(0.66f).height(9.dp).clip(RoundedCornerShape(3.dp)).background(t.sep.copy(alpha = 0.5f)))
            }
            if (i < 2) HairLine(insetStart = 14)
        }
        Text(
            "Reading backups from server…", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 12.5.sp,
            textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth().padding(12.dp),
        )
    }
}

@Composable
private fun EmptyBlock() {
    val t = LocalBackupTokens.current
    Column(
        Modifier.fillMaxWidth().padding(top = 36.dp, start = 24.dp, end = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("No backups yet", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        Text(
            "This server has no VReader backups. Tap Back Up Now to create your first one.",
            color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.sp, lineHeight = 19.sp,
            textAlign = TextAlign.Center, modifier = Modifier.padding(top = 6.dp),
        )
    }
}

private data class ErrorMeta(val title: String, val desc: String, val cta: String)

private fun errorMeta(cause: WebDavError, server: ServerSummary?): ErrorMeta {
    val name = server?.name ?: "the server"
    val host = server?.url?.substringBefore('/') ?: "the server"
    return when (cause) {
        WebDavError.auth401 -> ErrorMeta(
            "Authentication failed",
            "The server rejected your credentials (401). Re-enter the password in the server settings.",
            "Open Server Settings",
        )
        WebDavError.notFound404 -> ErrorMeta(
            "No backup folder found",
            "The /vreader folder doesn’t exist on this server yet (404). Run your first backup to create it.",
            "Back Up Now",
        )
        WebDavError.offline -> ErrorMeta(
            "You’re offline",
            "Connect to the internet to reach $name, then pull to refresh.",
            "Retry",
        )
        WebDavError.timeout -> ErrorMeta(
            "Server didn’t respond",
            "The request to $host timed out. Check the server is reachable on your network.",
            "Retry",
        )
    }
}

@Composable
private fun ErrorBlock(cause: WebDavError, server: ServerSummary?, onErrorCta: (WebDavError) -> Unit) {
    val t = LocalBackupTokens.current
    val m = errorMeta(cause, server)
    Column(
        Modifier.fillMaxWidth().padding(top = 40.dp, start = 24.dp, end = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(m.title, color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Text(
            m.desc, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, lineHeight = 20.sp,
            textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp),
        )
        Box(Modifier.padding(top = 20.dp)) {
            Box(
                Modifier.clip(RoundedCornerShape(100.dp)).background(t.tint)
                    .clickableRow { onErrorCta(cause) }.padding(horizontal = 20.dp, vertical = 12.dp),
            ) {
                Text(m.cta, color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@Composable
private fun PrimaryButton(label: String, filled: Boolean, onClick: () -> Unit) {
    val t = LocalBackupTokens.current
    Box(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
            .background(if (filled) t.tint else t.chipBg)
            .heightIn(min = 46.dp).clickableRow(onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            label, color = if (filled) Color.White else t.tint,
            fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(vertical = 12.dp),
        )
    }
}

@Composable
private fun HairLine(insetStart: Int) {
    val t = LocalBackupTokens.current
    Box(Modifier.fillMaxWidth().padding(start = insetStart.dp).height(0.5.dp).background(t.sep))
}

private fun Modifier.clickableRow(onClick: () -> Unit): Modifier =
    this.clickable { onClick() }
