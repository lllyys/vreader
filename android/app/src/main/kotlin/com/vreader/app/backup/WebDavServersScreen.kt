// Purpose: feature #114 WI-3 (#110 Phase 3) — the WebDAV server settings list (design surface
// A from vreader-backup-webdav.jsx WebDAVServerList): the saved-servers list with its empty
// onboarding state and populated rows carrying a live status dot + the EXACT failure reason
// (e.g. "401 — authentication failed"), tap-to-edit, and an Add Server affordance. Stateless:
// a pure function of the server list + callbacks.
package com.vreader.app.backup

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.Icon
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
fun WebDavServersScreen(
    servers: List<ServerSummary>,
    onBack: () -> Unit = {},
    onAdd: () -> Unit = {},
    onEdit: (String) -> Unit = {},
) {
    val t = LocalBackupTokens.current
    val addButton: @Composable () -> Unit = {
        Box(
            Modifier.size(44.dp).clip(RoundedCornerShape(22.dp)).clickable(onClickLabel = "Add server", onClick = onAdd),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Add, contentDescription = "Add server", tint = t.tint, modifier = Modifier.size(22.dp))
        }
    }
    NavScreen(title = "WebDAV Servers", large = true, onBack = onBack, trailing = addButton) {
        Column(Modifier.padding(horizontal = 18.dp).padding(bottom = 32.dp)) {
            if (servers.isEmpty()) {
                ServersEmptyState(onAdd)
            } else {
                GroupHeader("Saved Servers")
                SettingsCard {
                    servers.forEachIndexed { i, s ->
                        ServerRow(s, last = i == servers.lastIndex, onEdit = onEdit)
                    }
                }
                GroupFooter("Tap a server to edit its details or test the connection. The active server is used for automatic backups.")

                VSpace(22)
                SettingsCard {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 50.dp).clickable(onClick = onAdd).padding(horizontal = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.Add, contentDescription = null, tint = t.tint, modifier = Modifier.size(18.dp))
                        Text("Add Server", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.Medium, modifier = Modifier.padding(start = 8.dp))
                    }
                }
            }
        }
    }
}

@Composable
private fun ServerRow(server: ServerSummary, last: Boolean, onEdit: (String) -> Unit) {
    val t = LocalBackupTokens.current
    val statusColor = serverStatusColor(server.status, t)
    Column(Modifier.clickable { onEdit(server.id) }) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(38.dp).clip(RoundedCornerShape(10.dp)).background(t.sep.copy(alpha = 0.4f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.Storage, contentDescription = null, tint = t.sec, modifier = Modifier.size(20.dp))
            }
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text(server.name, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.5.sp, fontWeight = FontWeight.SemiBold)
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 3.dp)) {
                    StatusDot(statusColor)
                    Text(
                        server.detail,
                        color = if (server.status == ServerStatus.error) t.red else t.sec,
                        fontFamily = BackupFonts.Sans, fontSize = 12.sp, maxLines = 1,
                        modifier = Modifier.padding(start = 6.dp),
                    )
                }
            }
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = t.ter, modifier = Modifier.size(20.dp))
        }
        if (!last) Box(Modifier.fillMaxWidth().padding(start = 64.dp).height(0.5.dp).background(t.sep))
    }
}

/** Pure status→token-color mapping (extracted for a JVM unit test — Gate-4). */
fun serverStatusColor(status: ServerStatus, t: BackupTokens): Color = when (status) {
    ServerStatus.ok -> t.green
    ServerStatus.error -> t.red
    ServerStatus.unknown -> t.sec
}

@Composable
private fun ServersEmptyState(onAdd: () -> Unit) {
    val t = LocalBackupTokens.current
    Column(
        Modifier.fillMaxWidth().padding(top = 64.dp, start = 24.dp, end = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.size(72.dp).clip(RoundedCornerShape(36.dp)).background(t.chipBg),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Filled.Storage, contentDescription = null, tint = t.tint, modifier = Modifier.size(32.dp))
        }
        Text("No servers yet", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 19.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(top = 20.dp))
        Text(
            "Add a WebDAV server to back up your library and sync reading progress across devices. Works with Nextcloud, Fastmail, Synology, and any standard WebDAV host.",
            color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, lineHeight = 21.sp,
            textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp),
        )
        Box(Modifier.padding(top = 22.dp)) {
            Row(
                Modifier.clip(RoundedCornerShape(100.dp)).background(t.tint).clickable(onClick = onAdd).padding(horizontal = 22.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Add, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                Text("Add Server", color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 7.dp))
            }
        }
    }
}
