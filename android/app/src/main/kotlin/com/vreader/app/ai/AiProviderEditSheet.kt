// Purpose: feature #118 WI-3 (#110 Phase 3) — the add/edit AI provider form (the committed
// EditorSheet contract from vreader-ai-provider-fields.jsx): Provider Type (segmented) · Name ·
// Endpoint (Base URL + Model, blank → kind default, with the path-append hint) · Sampling
// (Temperature slider + Max Tokens stepper) · API Key (secure; edit shows Delete Key) · Connection
// (Test — enabled once a key is available, idle/testing/ok/fail). Reuses the shared form
// vocabulary; stateless: a pure function of AiEditState + callbacks.
package com.vreader.app.ai

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
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
fun AiProviderEditSheet(
    state: AiEditState,
    onKind: (AiProviderKind) -> Unit = {},
    onName: (String) -> Unit = {},
    onBaseUrl: (String) -> Unit = {},
    onModel: (String) -> Unit = {},
    onTemperature: (Double) -> Unit = {},
    onMaxTokens: (Int) -> Unit = {},
    onApiKey: (String) -> Unit = {},
    onDeleteKey: () -> Unit = {},
    onTest: () -> Unit = {},
    onSave: () -> Unit = {},
    onCancel: () -> Unit = {},
) {
    val t = LocalBackupTokens.current
    Box(Modifier.fillMaxSize()) {
        AppSheet(
            title = if (state.editMode) "Edit Provider" else "Add Provider",
            leading = {
                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(onClick = onCancel), contentAlignment = Alignment.CenterStart) {
                    Text("Cancel", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
                }
            },
            trailing = {
                Box(Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp).clickable(enabled = state.canSave, onClick = onSave).testTag("ai-save"), contentAlignment = Alignment.CenterEnd) {
                    Text("Save", color = if (state.canSave) t.tint else t.ter, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
            },
        ) {
            Column(Modifier.padding(horizontal = 18.dp).padding(top = 16.dp, bottom = 32.dp)) {
                GroupHeader("Provider Type")
                Segmented(state.kind, onKind)

                VSpace(20)
                GroupHeader("Name")
                SettingsCard { Field("", state.name, "e.g. OpenRouter", onName) }

                VSpace(20)
                GroupHeader("Endpoint")
                SettingsCard {
                    Field("Base URL", state.baseUrl, state.kind.defaultBaseUrl, onBaseUrl, mono = true)
                    Divider()
                    Field("Model", state.model, state.kind.defaultModel, onModel)
                }
                GroupFooter(state.kind.endpointPathHint + "  Leave blank to use the default.")

                VSpace(20)
                GroupHeader("Sampling")
                SettingsCard {
                    TemperatureRow(state.temperature, onTemperature)
                    Divider()
                    MaxTokensRow(state.maxTokens, onMaxTokens)
                }

                VSpace(20)
                GroupHeader("API Key")
                SettingsCard {
                    if (state.editMode && state.keyAlreadySaved && state.apiKey.isBlank()) {
                        Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("••••••••••••••", color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 16.sp, modifier = Modifier.weight(1f))
                            Box(Modifier.size(19.dp).clip(CircleShape).background(t.green))
                        }
                        Divider()
                        Box(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(onClick = onDeleteKey).padding(horizontal = 14.dp), contentAlignment = Alignment.CenterStart) {
                            Text("Delete Key", color = t.red, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
                        }
                    } else {
                        Field("", state.apiKey, "Enter API Key", onApiKey, secure = true)
                    }
                }
                if (!state.editMode) GroupFooter("Stored in the Android Keystore when you tap Save — but you can test it below first.")

                VSpace(20)
                GroupHeader("Connection")
                SettingsCard {
                    Row(Modifier.fillMaxWidth().padding(14.dp)) { TestChip(state.test, state.canTest, onTest) }
                    if (state.test == AiConnTest.ok || state.test == AiConnTest.fail) TestResult(state.test, state.testMessage)
                }
                if (!state.canTest) GroupFooter("Enter an API key above to test — no need to save first.")
            }
        }
    }
}

@Composable
private fun Segmented(value: AiProviderKind, onChange: (AiProviderKind) -> Unit) {
    val t = LocalBackupTokens.current
    Row(Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(12.dp)).background(t.codeBg).padding(3.dp)) {
        AiProviderKind.entries.forEach { k ->
            val on = k == value
            Box(
                Modifier.weight(1f).clip(RoundedCornerShape(10.dp)).background(if (on) t.card else Color.Transparent)
                    .clickable { onChange(k) }.testTag("kind-${k.name}").padding(vertical = 9.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(k.displayName, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium)
            }
        }
    }
}

@Composable
private fun Field(label: String, value: String, placeholder: String, onChange: (String) -> Unit, mono: Boolean = false, secure: Boolean = false) {
    val t = LocalBackupTokens.current
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        if (label.isNotEmpty()) Text(label, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.padding(end = 10.dp))
        BasicTextField(
            value = value, onValueChange = onChange, singleLine = true,
            textStyle = TextStyle(color = t.ink, fontFamily = if (mono) BackupFonts.Mono else BackupFonts.Sans, fontSize = if (mono) 13.5.sp else 15.sp),
            cursorBrush = SolidColor(t.tint),
            visualTransformation = if (secure) PasswordVisualTransformation() else VisualTransformation.None,
            modifier = Modifier.weight(1f).testTag("field-${label.ifBlank { placeholder }}"),
            decorationBox = { inner ->
                Box(Modifier.fillMaxWidth(), contentAlignment = if (label.isEmpty()) Alignment.CenterStart else Alignment.CenterEnd) {
                    if (value.isEmpty()) Text(placeholder, color = t.placeholder, fontFamily = if (mono) BackupFonts.Mono else BackupFonts.Sans, fontSize = if (mono) 13.5.sp else 15.sp)
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
private fun TemperatureRow(value: Double, onChange: (Double) -> Unit) {
    val t = LocalBackupTokens.current
    val density = LocalDensity.current
    var trackPx by remember { mutableIntStateOf(0) }  // measured track width, in px
    Column(Modifier.fillMaxWidth().padding(14.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Temperature", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.weight(1f))
            Text("%.1f".format(value), color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
        }
        // Custom track + thumb (0.0–2.0); tap maps x → value using the MEASURED width.
        val frac = (value / 2.0).toFloat().coerceIn(0f, 1f)
        Box(
            Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 4.dp).height(22.dp).testTag("temperature-slider")
                .onSizeChanged { trackPx = it.width }
                .pointerInput(Unit) {
                    detectTapGestures { offset -> if (trackPx > 0) onChange(((offset.x / trackPx) * 2.0).coerceIn(0.0, 2.0)) }
                },
            contentAlignment = Alignment.CenterStart,
        ) {
            Box(Modifier.fillMaxWidth().height(4.dp).clip(RoundedCornerShape(2.dp)).background(t.sep))
            Box(Modifier.fillMaxWidth(frac).height(4.dp).clip(RoundedCornerShape(2.dp)).background(t.tint))
            val trackDp = with(density) { trackPx.toDp() }
            val startPad = (trackDp * frac - 11.dp).coerceIn(0.dp, (trackDp - 22.dp).coerceAtLeast(0.dp))
            Box(Modifier.padding(start = startPad).size(22.dp).clip(CircleShape).background(Color.White))
        }
    }
}

@Composable
private fun MaxTokensRow(value: Int, onChange: (Int) -> Unit) {
    val t = LocalBackupTokens.current
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp), verticalAlignment = Alignment.CenterVertically) {
        Text("Max Tokens: $value", color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp, modifier = Modifier.weight(1f))
        Row(Modifier.clip(RoundedCornerShape(8.dp)).background(t.codeBg)) {
            Box(Modifier.size(width = 42.dp, height = 30.dp).clickable(onClickLabel = "decrease", onClick = { onChange((value - 256).coerceAtLeast(256)) }).testTag("tokens-dec"), contentAlignment = Alignment.Center) {
                Text("−", color = t.ink, fontSize = 19.sp)
            }
            Box(Modifier.size(width = 0.5.dp, height = 30.dp).background(t.sep))
            Box(Modifier.size(width = 42.dp, height = 30.dp).clickable(onClickLabel = "increase", onClick = { onChange((value + 256).coerceAtMost(8192)) }).testTag("tokens-inc"), contentAlignment = Alignment.Center) {
                Text("+", color = t.ink, fontSize = 19.sp)
            }
        }
    }
}

@Composable
private fun TestChip(test: AiConnTest, enabled: Boolean, onTest: () -> Unit) {
    val t = LocalBackupTokens.current
    val label = if (test == AiConnTest.testing) "Testing…" else "Test Connection"
    Box(
        Modifier.clip(RoundedCornerShape(100.dp)).background(if (enabled) t.chipBg else Color.Transparent)
            .clickable(enabled = enabled && test != AiConnTest.testing, onClick = onTest).testTag("ai-test")
            .padding(horizontal = 15.dp, vertical = 8.dp),
    ) {
        Text(label, color = if (enabled) t.tint else t.ter, fontFamily = BackupFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun TestResult(test: AiConnTest, message: String) {
    val t = LocalBackupTokens.current
    val ok = test == AiConnTest.ok
    val fallback = if (ok) "Connected — the provider responded successfully." else "Failed: 401 Unauthorized — check your API key."
    Row(Modifier.fillMaxWidth().padding(start = 14.dp, end = 14.dp, bottom = 14.dp), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(16.dp).clip(CircleShape).background(if (ok) t.green else t.red))
        Text(message.ifBlank { fallback }, color = if (ok) t.green else t.red, fontFamily = BackupFonts.Sans, fontSize = 13.sp, lineHeight = 19.sp, modifier = Modifier.padding(start = 7.dp).testTag("ai-test-result"))
    }
}
