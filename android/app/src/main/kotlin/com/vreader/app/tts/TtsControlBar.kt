// Purpose: feature #121 WI-4 (#110 Phase 3) — the docked read-aloud transport (design vreader-tts.jsx
// `TtsBar`): a chunk-progress line, a status row, the speed chip + prev/play-pause/next transport + a
// close, and a voice/engine chip; plus the error layout (no-voice-data → Install voice data + System
// TTS). Uses the reader's VReaderColors/VReaderFonts (the in-reader surface). Stateless: a pure
// function of TtsUiState + callbacks.
package com.vreader.app.tts

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.ui.theme.VReaderColors
import com.vreader.app.ui.theme.VReaderFonts

@Composable
fun TtsControlBar(
    state: TtsUiState,
    onPlayPause: () -> Unit = {},
    onPrevious: () -> Unit = {},
    onNext: () -> Unit = {},
    onStop: () -> Unit = {},
    onSpeed: () -> Unit = {},
    onVoice: () -> Unit = {},
    onInstallVoice: () -> Unit = {},
    onSystemTts: () -> Unit = {},
) {
    val c = VReaderColors
    val rule = Color(0x14000000)
    Column(
        Modifier.fillMaxWidth().background(c.Background).testTag("tts-bar"),
    ) {
        // progress line
        Box(Modifier.fillMaxWidth().height(3.dp).background(rule)) {
            if (state.phase != TtsPhase.error) {
                Box(Modifier.fillMaxWidth(state.progressFraction.coerceIn(0f, 1f)).height(3.dp).background(c.Accent))
            }
        }
        if (state.phase == TtsPhase.error) ErrorLayout(state, onInstallVoice, onSystemTts)
        else TransportLayout(state, onPlayPause, onPrevious, onNext, onStop, onSpeed, onVoice)
    }
}

@Composable
private fun TransportLayout(
    state: TtsUiState, onPlayPause: () -> Unit, onPrevious: () -> Unit, onNext: () -> Unit,
    onStop: () -> Unit, onSpeed: () -> Unit, onVoice: () -> Unit,
) {
    val c = VReaderColors
    val playing = state.phase == TtsPhase.speaking
    Column(Modifier.fillMaxWidth().padding(start = 18.dp, end = 18.dp, top = 11.dp, bottom = 12.dp)) {
        // status row
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                when (state.phase) { TtsPhase.idle -> "READY TO READ ALOUD"; TtsPhase.speaking -> "READING ALOUD"; else -> "PAUSED" },
                color = if (playing) c.Accent else c.InkMuted, fontFamily = VReaderFonts.Sans,
                fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold,
            )
            if (state.sentenceCount > 0) {
                Text("${state.sentenceIndex + 1} / ${state.sentenceCount}", color = c.InkMuted, fontFamily = VReaderFonts.Sans, fontSize = 12.5.sp)
            }
        }
        // transport row
        Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            Chip(state.rateLabel, c.ChipFill, c.Ink, onSpeed, "tts-speed")
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                IconBtn(Icons.Filled.SkipPrevious, "Previous sentence", c.Ink, onPrevious, "tts-prev")
                Box(
                    Modifier.size(60.dp).clip(CircleShape).background(c.Accent)
                        .clickable(onClickLabel = if (playing) "Pause" else "Play", onClick = onPlayPause).testTag("tts-playpause"),
                    contentAlignment = Alignment.Center,
                ) { Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, contentDescription = null, tint = Color.White, modifier = Modifier.size(30.dp)) }
                IconBtn(Icons.Filled.SkipNext, "Next sentence", c.Ink, onNext, "tts-next")
            }
            IconBtn(Icons.Filled.Close, "Stop read-aloud", c.Ink, onStop, "tts-stop")
        }
        // voice/engine chip (constrained so a long label ellipsizes instead of overflowing)
        Row(Modifier.fillMaxWidth().padding(top = 10.dp), horizontalArrangement = Arrangement.Center) {
            Chip(state.voiceLabel.ifBlank { state.engineLabel.ifBlank { "Voice" } }, c.ChipFill, c.Ink, onVoice, "tts-voice", Modifier.widthIn(max = 240.dp))
        }
    }
}

@Composable
private fun ErrorLayout(state: TtsUiState, onInstallVoice: () -> Unit, onSystemTts: () -> Unit) {
    val c = VReaderColors
    Column(Modifier.fillMaxWidth().padding(18.dp).testTag("tts-error")) {
        Text(
            when (state.error) {
                TtsErrorKind.noVoiceData, TtsErrorKind.languageNotSupported -> "No voice for this language"
                TtsErrorKind.initFailed -> "Text-to-speech is unavailable"
                else -> "Read-aloud failed"
            },
            color = c.Ink, fontFamily = VReaderFonts.Sans, fontSize = 14.5.sp, fontWeight = FontWeight.SemiBold,
        )
        Text(
            "The on-device speech engine has no voice data installed for this language.",
            color = c.InkMuted, fontFamily = VReaderFonts.Sans, fontSize = 13.sp, modifier = Modifier.padding(top = 2.dp),
        )
        Row(Modifier.fillMaxWidth().padding(top = 13.dp), horizontalArrangement = Arrangement.spacedBy(9.dp)) {
            Box(
                Modifier.weight(1f).clip(RoundedCornerShape(11.dp)).background(c.Accent).clickable(onClick = onInstallVoice).testTag("tts-install-voice").padding(vertical = 11.dp),
                contentAlignment = Alignment.Center,
            ) { Text("Install voice data", color = Color.White, fontFamily = VReaderFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold) }
            Box(
                Modifier.clip(RoundedCornerShape(11.dp)).background(c.ChipFill).clickable(onClick = onSystemTts).testTag("tts-system").padding(horizontal = 16.dp, vertical = 11.dp),
                contentAlignment = Alignment.Center,
            ) { Text("System TTS", color = c.Ink, fontFamily = VReaderFonts.Sans, fontSize = 14.sp) }
        }
    }
}

@Composable
private fun Chip(label: String, bg: Color, fg: Color, onClick: () -> Unit, tag: String, modifier: Modifier = Modifier) {
    Box(
        modifier.clip(RoundedCornerShape(100.dp)).background(bg).clickable(onClick = onClick).testTag(tag).padding(horizontal = 12.dp, vertical = 7.dp),
    ) { Text(label, color = fg, fontFamily = VReaderFonts.Sans, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis) }
}

@Composable
private fun IconBtn(icon: androidx.compose.ui.graphics.vector.ImageVector, desc: String, tint: Color, onClick: () -> Unit, tag: String) {
    // the action label lives on the clickable node; the icon is decorative.
    Box(Modifier.size(40.dp).clip(CircleShape).clickable(onClickLabel = desc, onClick = onClick).testTag(tag), contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(26.dp))
    }
}
