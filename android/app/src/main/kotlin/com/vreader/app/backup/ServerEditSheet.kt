// Purpose: feature #114 WI-3 surface B (#110 Phase 3) — the add / edit WebDAV server form
// (design surface B from vreader-backup-webdav.jsx ServerEditSheet): Name / Base URL /
// Username / Password fields, a "Back up on Wi-Fi only" toggle, Test Connection that runs
// against the LIVE form (idle/testing/ok/fail with an inline result), and (edit mode) a
// destructive Remove Server with a confirm alert that promises the on-server backups are
// kept. Stateless: a pure function of ServerEditState + callbacks.
package com.vreader.app.backup

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun ServerEditSheet(
    state: ServerEditState,
    onName: (String) -> Unit = {},
    onBaseUrl: (String) -> Unit = {},
    onUsername: (String) -> Unit = {},
    onPassword: (String) -> Unit = {},
    onWifiOnly: (Boolean) -> Unit = {},
    onTest: () -> Unit = {},
    onSave: () -> Unit = {},
    onCancel: () -> Unit = {},
    onRemoveClick: () -> Unit = {},
    onRemoveConfirm: () -> Unit = {},
    onRemoveDismiss: () -> Unit = {},
) {
    val t = LocalBackupTokens.current
    val canSave = state.name.isNotBlank() && state.baseUrl.isNotBlank() && state.username.isNotBlank()
    Box(Modifier.fillMaxSize()) {
        AppSheet(
            title = if (state.editMode) "Edit Server" else "Add Server",
            leading = {
                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(onClick = onCancel), contentAlignment = Alignment.CenterStart) {
                    Text("Cancel", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
                }
            },
            trailing = {
                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(enabled = canSave, onClick = onSave), contentAlignment = Alignment.CenterEnd) {
                    Text("Save", color = if (canSave) t.tint else t.ter, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
            },
        ) {
            Column(Modifier.padding(horizontal = 18.dp).padding(top = 16.dp, bottom = 32.dp)) {
                GroupHeader("Server")
                SettingsCard {
                    EditField("Name", state.name, "Home NAS", onName)
                    FieldDivider()
                    EditField("Base URL", state.baseUrl, "https://host/dav", onBaseUrl, mono = true)
                    FieldDivider()
                    EditField("Username", state.username, "Required", onUsername)
                }
                GroupFooter("The full WebDAV collection URL — the app stores backups in a /vreader folder there.")

                VSpace(20)
                GroupHeader("Authentication")
                SettingsCard {
                    EditField("Password", state.password, "Required", onPassword, secure = true)
                }
                GroupFooter("Stored in the Android Keystore. Use an app password if your host offers one.")

                VSpace(20)
                GroupHeader("Sync")
                SettingsCard {
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 50.dp).clickable { onWifiOnly(!state.wifiOnly) }.padding(horizontal = 14.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("Back up on Wi-Fi only", color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.weight(1f))
                        BackupToggle(state.wifiOnly, onWifiOnly)
                    }
                }
                GroupFooter("When off, backups may run over cellular data.")

                VSpace(20)
                GroupHeader("Connection")
                SettingsCard {
                    Row(Modifier.fillMaxWidth().padding(14.dp)) {
                        TestConnectionChip(state.test, onTest)
                    }
                    if (state.test == ConnTest.ok || state.test == ConnTest.fail) {
                        TestResultRow(state.test, state.testMessage)
                    }
                }

                if (state.editMode) {
                    VSpace(28)
                    SettingsCard {
                        Box(
                            Modifier.fillMaxWidth().heightIn(min = 50.dp).clickable(onClick = onRemoveClick),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text("Remove Server", color = t.red, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                        }
                    }
                }
            }
        }

        if (state.showRemoveConfirm) {
            AppAlert(
                title = "Remove this server?",
                message = buildAnnotatedString {
                    append("VReader will stop backing up to ")
                    withStyle(SpanStyle(color = t.ink, fontWeight = FontWeight.SemiBold)) { append(state.name.ifBlank { "this server" }) }
                    append(". Existing backups on the server are left untouched.")
                },
                confirmLabel = "Remove",
                confirmDanger = true,
                onConfirm = onRemoveConfirm,
                onDismiss = onRemoveDismiss,
            )
        }
    }
}

@Composable
private fun EditField(label: String, value: String, placeholder: String, onChange: (String) -> Unit, mono: Boolean = false, secure: Boolean = false) {
    val t = LocalBackupTokens.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.padding(end = 10.dp))
        BasicTextField(
            value = value,
            onValueChange = onChange,
            singleLine = true,
            textStyle = TextStyle(color = t.ink, fontFamily = if (mono) BackupFonts.Mono else BackupFonts.Sans, fontSize = if (mono) 13.5.sp else 15.sp),
            cursorBrush = androidx.compose.ui.graphics.SolidColor(t.tint),
            visualTransformation = if (secure) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
            modifier = Modifier.weight(1f).testTag("field-$label"),
            decorationBox = { inner ->
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                    if (value.isEmpty()) {
                        Text(placeholder, color = t.placeholder, fontFamily = if (mono) BackupFonts.Mono else BackupFonts.Sans, fontSize = if (mono) 13.5.sp else 15.sp)
                    }
                    inner()
                }
            },
        )
    }
}

@Composable
private fun FieldDivider() {
    val t = LocalBackupTokens.current
    Box(Modifier.fillMaxWidth().padding(start = 14.dp).height(0.5.dp).background(t.sep))
}

@Composable
private fun BackupToggle(on: Boolean, onChange: (Boolean) -> Unit) {
    val t = LocalBackupTokens.current
    Box(
        Modifier.size(width = 44.dp, height = 27.dp).clip(RoundedCornerShape(14.dp))
            .background(if (on) t.tint else t.sep).clickable { onChange(!on) },
        contentAlignment = if (on) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Box(Modifier.padding(horizontal = 2.5.dp).size(22.dp).clip(CircleShape).background(Color.White))
    }
}

@Composable
private fun TestConnectionChip(test: ConnTest, onTest: () -> Unit) {
    val t = LocalBackupTokens.current
    val label = if (test == ConnTest.testing) "Testing…" else "Test Connection"
    Box(
        Modifier.clip(RoundedCornerShape(100.dp)).background(t.chipBg).clickable(enabled = test != ConnTest.testing, onClick = onTest)
            .padding(horizontal = 15.dp, vertical = 8.dp),
    ) {
        Text(label, color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun TestResultRow(test: ConnTest, message: String) {
    val t = LocalBackupTokens.current
    val ok = test == ConnTest.ok
    val fallback = if (ok) "Connected — the provider responded successfully." else "Failed: 401 Unauthorized — check the username and password."
    Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 14.dp), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(16.dp).clip(CircleShape).background(if (ok) t.green else t.red))
        Text(
            message.ifBlank { fallback }, color = if (ok) t.green else t.red,
            fontFamily = BackupFonts.Sans, fontSize = 13.sp, lineHeight = 19.sp, modifier = Modifier.padding(start = 7.dp),
        )
    }
}
