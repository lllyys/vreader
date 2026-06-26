// Purpose: feature #120 WI-3 (#110 Phase 3) — the OPDS browse error states (design `vreader-opds.jsx`
// `OpdsError`): offline (Retry) / 401 (Edit sign-in) / 404 (Edit URL) / generic, each one cause +
// one CTA. Stateless: a pure function of the error kind + callbacks.
package com.vreader.app.opds.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.WifiOff
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.backup.BackupFonts
import com.vreader.app.backup.LocalBackupTokens
import com.vreader.app.backup.VSpace

private data class ErrorCopy(val icon: ImageVector, val title: String, val body: String, val cta: String)

@Composable
fun OpdsErrorView(
    kind: OpdsBrowseError,
    onRetry: () -> Unit = {},
    onEditSource: () -> Unit = {},
) {
    val t = LocalBackupTokens.current
    val e = when (kind) {
        OpdsBrowseError.offline -> ErrorCopy(Icons.Filled.WifiOff, "You’re offline", "VReader can’t reach this catalog. Check your connection and try again.", "Retry")
        // Cause-level titles (no hardcoded code): the VM's mapping is many-to-one (401+403 → auth,
        // 404 + parse/invalid-url/empty → notfound), so a literal "401"/"404" would misreport a 403
        // or a parse error. The cause + CTA stay accurate.
        OpdsBrowseError.auth -> ErrorCopy(Icons.Filled.Lock, "Sign-in required", "This catalog needs a username and password. Add them to the source to browse it.", "Edit sign-in")
        OpdsBrowseError.notfound -> ErrorCopy(Icons.Filled.ErrorOutline, "Feed not found", "The catalog URL didn’t return a feed. Double-check the OPDS address.", "Edit URL")
        OpdsBrowseError.generic -> ErrorCopy(Icons.Filled.ErrorOutline, "Couldn’t load the catalog", "Something went wrong reaching this catalog. Try again, or check the source.", "Retry")
    }
    val onCta = if (kind == OpdsBrowseError.offline || kind == OpdsBrowseError.generic) onRetry else onEditSource
    Column(
        Modifier.fillMaxWidth().padding(horizontal = 30.dp, vertical = 74.dp).testTag("opds-error-${kind.name}"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.size(62.dp).clip(CircleShape).background(t.red.copy(alpha = 0.10f)), contentAlignment = Alignment.Center) {
            Icon(e.icon, contentDescription = null, tint = t.red, modifier = Modifier.size(30.dp))
        }
        VSpace(18)
        Text(e.title, color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 19.sp, textAlign = TextAlign.Center)
        VSpace(8)
        Text(e.body, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 14.sp, lineHeight = 21.sp, textAlign = TextAlign.Center)
        VSpace(20)
        Box(
            Modifier.clip(RoundedCornerShape(11.dp)).background(t.tint).clickable(onClick = onCta).testTag("opds-error-cta").padding(horizontal = 22.dp, vertical = 11.dp),
            contentAlignment = Alignment.Center,
        ) { Text(e.cta, color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold) }
    }
}
