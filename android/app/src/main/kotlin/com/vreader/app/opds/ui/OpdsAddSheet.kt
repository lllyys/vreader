// Purpose: feature #120 WI-2 (#110 Phase 3) — the add/edit OPDS catalog sheet (design
// `vreader-opds.jsx` `OpdsAddSheet`): Catalog (Name · URL) · Authentication (a Requires-sign-in
// toggle revealing Username + Password) · Connection (Test — idle/testing/ok/fail) · edit-mode
// Remove. Reuses the shared backup form vocabulary; stateless: a pure function of OpdsEditState +
// callbacks. The password field is secure and never logged.
package com.vreader.app.opds.ui

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
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.foundation.text.KeyboardOptions as FoundationKeyboardOptions
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
fun OpdsAddSheet(
    state: OpdsEditState,
    onName: (String) -> Unit = {},
    onUrl: (String) -> Unit = {},
    onRequiresAuth: (Boolean) -> Unit = {},
    onUsername: (String) -> Unit = {},
    onPassword: (String) -> Unit = {},
    onTest: () -> Unit = {},
    onSave: () -> Unit = {},
    onRemove: () -> Unit = {},
    onCancel: () -> Unit = {},
) {
    val t = LocalBackupTokens.current
    Box(Modifier.fillMaxSize()) {
        AppSheet(
            title = if (state.editMode) "Edit Catalog" else "Add Catalog",
            leading = {
                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(onClick = onCancel), contentAlignment = Alignment.CenterStart) {
                    Text("Cancel", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
                }
            },
            trailing = {
                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(enabled = state.canSave, onClick = onSave).testTag("opds-save"), contentAlignment = Alignment.CenterEnd) {
                    Text("Save", color = if (state.canSave) t.tint else t.ter, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
            },
        ) {
            Column(Modifier.padding(horizontal = 18.dp).padding(top = 16.dp, bottom = 32.dp)) {
                GroupHeader("Catalog")
                SettingsCard {
                    Field("Name", state.name, "e.g. Standard Ebooks", onName)
                    Divider()
                    Field("URL", state.url, "https://…/opds", onUrl, mono = true, url = true)
                }
                GroupFooter("Paste the catalog's OPDS feed URL. VReader follows navigation links from there.")

                VSpace(18)
                GroupHeader("Authentication")
                SettingsCard {
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Requires sign-in", color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.weight(1f))
                        OpdsToggle(state.requiresAuth, onRequiresAuth)
                    }
                    if (state.requiresAuth) {
                        Divider()
                        Field("Username", state.username, "reader", onUsername)
                        Divider()
                        PasswordField(state, onPassword)
                    }
                }
                if (state.requiresAuth) {
                    GroupFooter("Sent only to this catalog's address, over a secure or local connection.")
                }

                VSpace(18)
                GroupHeader("Connection")
                SettingsCard {
                    Box(Modifier.fillMaxWidth().padding(14.dp)) {
                        TestChip(state.test, enabled = state.canTest, onTest = onTest)
                    }
                    if (state.test == OpdsConnTest.ok || state.test == OpdsConnTest.fail) {
                        TestResultRow(state.test, state.testMessage)
                    }
                }

                if (state.editMode) {
                    VSpace(18)
                    SettingsCard {
                        Box(
                            Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClick = onRemove).testTag("opds-remove").padding(horizontal = 14.dp),
                            contentAlignment = Alignment.CenterStart,
                        ) { Text("Remove Catalog", color = t.red, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.Medium) }
                    }
                }
            }
        }
    }
}

@Composable
private fun Field(label: String, value: String, placeholder: String, onChange: (String) -> Unit, mono: Boolean = false, url: Boolean = false) {
    val t = LocalBackupTokens.current
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.padding(end = 10.dp))
        BasicTextField(
            value = value,
            onValueChange = onChange,
            singleLine = true,
            keyboardOptions = if (url) FoundationKeyboardOptions(keyboardType = KeyboardType.Uri) else FoundationKeyboardOptions.Default,
            textStyle = TextStyle(color = t.ink, fontFamily = if (mono) BackupFonts.Mono else BackupFonts.Sans, fontSize = if (mono) 13.5.sp else 15.sp),
            cursorBrush = SolidColor(t.tint),
            modifier = Modifier.weight(1f).testTag("field-$label"),
            decorationBox = { inner ->
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                    if (value.isEmpty()) Text(placeholder, color = t.placeholder, fontFamily = if (mono) BackupFonts.Mono else BackupFonts.Sans, fontSize = if (mono) 13.5.sp else 15.sp)
                    inner()
                }
            },
        )
    }
}

@Composable
private fun PasswordField(state: OpdsEditState, onPassword: (String) -> Unit) {
    val t = LocalBackupTokens.current
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("Password", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.padding(end = 10.dp))
        BasicTextField(
            value = state.password,
            onValueChange = onPassword,
            singleLine = true,
            keyboardOptions = FoundationKeyboardOptions(keyboardType = KeyboardType.Password),
            visualTransformation = PasswordVisualTransformation(),
            textStyle = TextStyle(color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp),
            cursorBrush = SolidColor(t.tint),
            modifier = Modifier.weight(1f).testTag("field-Password"),
            decorationBox = { inner ->
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
                    // Edit mode with a stored key: dots stand in until the user types a new one.
                    if (state.password.isEmpty()) {
                        val hint = if (state.keyAlreadySaved) "••••••••" else "required"
                        Text(hint, color = t.placeholder, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
                    }
                    inner()
                }
            },
        )
    }
}

@Composable
private fun Divider() {
    val t = LocalBackupTokens.current
    Box(Modifier.fillMaxWidth().padding(start = 14.dp).height(0.5.dp).background(t.sep))
}

@Composable
private fun OpdsToggle(on: Boolean, onChange: (Boolean) -> Unit) {
    val t = LocalBackupTokens.current
    Box(
        Modifier.size(width = 44.dp, height = 27.dp).clip(RoundedCornerShape(14.dp))
            .background(if (on) t.tint else t.sep).clickable { onChange(!on) }.testTag("opds-auth-toggle"),
        contentAlignment = if (on) Alignment.CenterEnd else Alignment.CenterStart,
    ) { Box(Modifier.padding(horizontal = 2.5.dp).size(22.dp).clip(CircleShape).background(Color.White)) }
}

@Composable
private fun TestChip(test: OpdsConnTest, enabled: Boolean, onTest: () -> Unit) {
    val t = LocalBackupTokens.current
    val label = if (test == OpdsConnTest.testing) "Testing…" else "Test Connection"
    // Disabled (no URL yet) → dim + no click, so the affordance matches what the VM will accept.
    Box(
        Modifier.clip(RoundedCornerShape(100.dp)).background(t.chipBg).clickable(enabled = enabled && test != OpdsConnTest.testing, onClick = onTest)
            .testTag("opds-test").padding(horizontal = 15.dp, vertical = 8.dp),
    ) { Text(label, color = if (enabled) t.tint else t.ter, fontFamily = BackupFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold) }
}

@Composable
private fun TestResultRow(test: OpdsConnTest, message: String) {
    val t = LocalBackupTokens.current
    val ok = test == OpdsConnTest.ok
    val fallback = if (ok) "Connected — the catalog responded successfully." else "Failed — check the URL and sign-in."
    Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 14.dp), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(16.dp).clip(CircleShape).background(if (ok) t.green else t.red))
        Text(
            message.ifBlank { fallback }, color = if (ok) t.green else t.red,
            fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, modifier = Modifier.padding(start = 7.dp).testTag("opds-test-result"),
        )
    }
}
