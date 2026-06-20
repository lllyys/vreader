// Purpose: feature #114 WI-2 (#110 Phase 3) — the shared Compose primitives for the backup/
// restore surfaces, recreated from the design's reused primitives (NavScreen/TopBar/Card/
// GroupHeader/GroupFooter/StatusDot/Tag/Toggle in vreader-ai-provider-fields.jsx +
// vreader-backup-webdav.jsx). BackupSurface provides the BackupTokens via CompositionLocal on
// the system dark mode (overridable for tests/previews).
package com.vreader.app.backup

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Provides the BackupTokens for the chosen appearance + paints the page background. */
@Composable
fun BackupSurface(darkOverride: Boolean? = null, content: @Composable () -> Unit) {
    val dark = darkOverride ?: isSystemInDarkTheme()
    val tokens = if (dark) BackupTokens.Dark else BackupTokens.Light
    CompositionLocalProvider(LocalBackupTokens provides tokens) {
        Box(Modifier.fillMaxSize().background(tokens.bg)) { content() }
    }
}

/** Back ("Settings") + serif title (large title below, or centered compact), optional trailing. */
@Composable
fun BackupTopBar(
    title: String,
    large: Boolean = false,
    onBack: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
) {
    val t = LocalBackupTokens.current
    Column(Modifier.fillMaxWidth().background(t.bg)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                Modifier.clip(RoundedCornerShape(8.dp)).clickableBack(onBack).padding(6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBackIos, contentDescription = "Back", tint = t.tint, modifier = Modifier.size(15.dp))
                Text("Settings", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            }
            Box(Modifier.weight(1f)) {
                if (!large) {
                    Text(
                        title, color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
                        modifier = Modifier.align(Alignment.Center), maxLines = 1,
                    )
                }
            }
            Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) { trailing?.invoke() }
        }
        if (large) {
            Text(
                title, color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 28.sp, fontWeight = FontWeight.Bold,
                modifier = Modifier.padding(start = 20.dp, end = 20.dp, bottom = 10.dp),
            )
        }
    }
}

/** A pushed settings screen — top bar + a scrollable body. */
@Composable
fun NavScreen(
    title: String,
    large: Boolean = false,
    onBack: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
    body: @Composable ColumnScope.() -> Unit,
) {
    val t = LocalBackupTokens.current
    Column(Modifier.fillMaxSize().background(t.bg).systemBarsPadding()) {
        BackupTopBar(title, large, onBack, trailing)
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) { body() }
    }
}

/** A rounded-14 settings card (the design's Card). */
@Composable
fun SettingsCard(content: @Composable ColumnScope.() -> Unit) {
    val t = LocalBackupTokens.current
    Column(
        Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(14.dp)).background(t.card),
        content = content,
    )
}

/** UPPERCASE section label (the design's GroupHeader / SectionLabel). */
@Composable
fun GroupHeader(text: String) {
    val t = LocalBackupTokens.current
    Text(
        text.uppercase(), color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 2.dp),
    )
}

/** A small explanatory footer under a card (the design's GroupFooter). */
@Composable
fun GroupFooter(text: String) {
    val t = LocalBackupTokens.current
    Text(
        text, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 12.sp, lineHeight = 17.sp,
        modifier = Modifier.padding(horizontal = 4.dp).padding(top = 8.dp),
    )
}

/** The status pip (ok green / error red / muted) — the design's StatusDot. */
@Composable
fun StatusDot(color: Color) {
    Box(Modifier.size(8.dp).clip(CircleShape).background(color))
}

/** A small uppercase pill (the design's Tag, e.g. "Latest"). */
@Composable
fun BackupTag(text: String) {
    val t = LocalBackupTokens.current
    Text(
        text.uppercase(), color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 10.5.sp, fontWeight = FontWeight.SemiBold,
        modifier = Modifier.clip(RoundedCornerShape(5.dp)).background(t.tagBg).padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

/** Vertical spacer matching the design's `<div style={{ height: N }}/>`. */
@Composable
fun VSpace(dp: Int) {
    Box(Modifier.height(dp.dp))
}

/** A bottom-aligned modal sheet (the design's AppSheet): dim scrim, top-rounded sheet, drag
 *  grabber, Cancel/title/Save header, and a scrollable body. */
@Composable
fun AppSheet(
    title: String,
    leading: @Composable () -> Unit,
    trailing: @Composable () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val t = LocalBackupTokens.current
    Box(Modifier.fillMaxSize().background(Color(0x59000000)), contentAlignment = Alignment.BottomCenter) {
        Column(
            Modifier.fillMaxWidth().fillMaxHeight(0.96f)
                .clip(RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp)).background(t.sheetBg),
        ) {
            Box(Modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.Center) {
                Box(Modifier.width(36.dp).height(5.dp).clip(RoundedCornerShape(3.dp)).background(t.sep))
            }
            Row(
                Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.width(64.dp)) { leading() }
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Text(title, color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                }
                Box(Modifier.width(64.dp), contentAlignment = Alignment.CenterEnd) { trailing() }
            }
            Box(Modifier.fillMaxWidth().height(0.5.dp).background(t.sep))
            Column(
                Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()),
                content = content,
            )
        }
    }
}

/** A centered iOS-style confirm alert (the design's AppAlert) — Cancel + a confirm action. */
@Composable
fun AppAlert(
    title: String,
    message: androidx.compose.ui.text.AnnotatedString,
    confirmLabel: String,
    confirmDanger: Boolean = false,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val t = LocalBackupTokens.current
    Box(
        Modifier.fillMaxSize().background(Color(0x66000000)).clickable(onClick = onDismiss).padding(28.dp),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier.widthIn(max = 300.dp).fillMaxWidth()
                .clip(RoundedCornerShape(18.dp)).background(if (t.isDark) Color(0xFF2A2724) else Color(0xFFFBF7EF))
                // An ENABLED no-op consumer reliably swallows taps inside the card so they
                // don't fall through to the scrim's dismiss (Gate-4 r2).
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {},
        ) {
            Column(Modifier.padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(title, color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 17.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center)
                Text(message, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.sp, lineHeight = 20.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
            }
            Box(Modifier.fillMaxWidth().height(0.5.dp).background(t.sep))
            Row(Modifier.fillMaxWidth()) {
                Box(Modifier.weight(1f).clickable(onClick = onDismiss).padding(vertical = 13.dp), contentAlignment = Alignment.Center) {
                    Text("Cancel", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 15.5.sp, fontWeight = FontWeight.Medium)
                }
                Box(Modifier.width(0.5.dp).height(46.dp).background(t.sep))
                Box(Modifier.weight(1f).clickable(onClick = onConfirm).padding(vertical = 13.dp), contentAlignment = Alignment.Center) {
                    Text(confirmLabel, color = if (confirmDanger) t.red else t.tint, fontFamily = BackupFonts.Sans, fontSize = 15.5.sp, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

private fun Modifier.clickableBack(onBack: () -> Unit): Modifier =
    this.clickable(onClickLabel = "Back") { onBack() }
