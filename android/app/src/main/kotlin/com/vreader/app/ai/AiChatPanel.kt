// Purpose: feature #118 WI-4 (#110 Phase 3) — the AI chat + summary panel (the committed
// `AiChatPanel`), docked over a dimmed reader. States: unconfigured (gate → AI settings) / idle
// (suggested prompts) / in-flight (typing dots) / answer (streamed in the reading serif, via
// AiMarkdownRenderer) / summary (cached key-points + regenerate). Stateless: a pure function of
// AiChatUiState + callbacks. Reuses the shared tokens.
package com.vreader.app.ai

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.backup.BackupFonts
import com.vreader.app.backup.LocalBackupTokens

@Composable
fun AiChatPanel(
    state: AiChatUiState,
    onSend: (String) -> Unit = {},
    onSuggested: (String) -> Unit = {},
    onOpenSettings: () -> Unit = {},
    onRegenerate: () -> Unit = {},
) {
    val t = LocalBackupTokens.current
    Column(
        Modifier.fillMaxSize().clip(RoundedCornerShape(topStart = 22.dp, topEnd = 22.dp)).background(t.sheetBg),
    ) {
        // grabber
        Box(Modifier.fillMaxWidth().padding(top = 8.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.width(36.dp).height(5.dp).clip(RoundedCornerShape(3.dp)).background(t.sep))
        }
        // header
        Row(Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = t.tint, modifier = Modifier.size(20.dp))
            Text(
                if (state.mode == AiChatMode.summary) "Chapter summary" else "Ask about this book",
                color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 16.5.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f).padding(start = 9.dp),
            )
            if (!state.unconfigured && state.providerName != null) {
                Box(Modifier.clip(RoundedCornerShape(100.dp)).background(t.codeBg).padding(horizontal = 9.dp, vertical = 4.dp)) {
                    Text(state.providerName, color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp, fontWeight = FontWeight.SemiBold)
                }
            }
        }
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(t.sep))

        Box(Modifier.weight(1f).fillMaxWidth()) {
            when {
                state.unconfigured -> UnconfiguredGate(onOpenSettings)
                state.mode == AiChatMode.summary -> SummaryView(state, onRegenerate)
                else -> ChatView(state)
            }
        }

        if (!state.unconfigured && state.mode == AiChatMode.chat) InputBar(onSend)
    }
}

@Composable
private fun UnconfiguredGate(onOpenSettings: () -> Unit) {
    val t = LocalBackupTokens.current
    Column(Modifier.fillMaxSize().padding(horizontal = 26.dp, vertical = 50.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.size(60.dp).clip(CircleShape).background(t.chipBg), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = t.tint, modifier = Modifier.size(28.dp))
        }
        Text("Connect a provider first", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 19.sp, modifier = Modifier.padding(top = 18.dp), textAlign = TextAlign.Center)
        Text("Chat and summaries need an AI provider. Add one in Settings — it takes a key and a minute.", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, lineHeight = 20.sp, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 8.dp))
        Box(
            Modifier.padding(top = 18.dp).clip(RoundedCornerShape(11.dp)).background(t.tint)
                .clickable(onClick = onOpenSettings).testTag("ai-open-settings").padding(horizontal = 20.dp, vertical = 11.dp),
        ) { Text("Open AI settings", color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold) }
    }
}

@Composable
private fun ChatView(state: AiChatUiState) {
    val t = LocalBackupTokens.current
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 18.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(vertical = 16.dp)) {
        if (state.showSuggestions) {
            item {
                Text("Ask anything about what you're reading, or try:", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 13.sp, modifier = Modifier.padding(bottom = 12.dp))
            }
            items(AiChatUiState.SUGGESTED_PROMPTS) { p ->
                Box(Modifier.padding(bottom = 8.dp).clip(RoundedCornerShape(100.dp)).background(t.codeBg).wrapContentWidth().padding(horizontal = 14.dp, vertical = 9.dp).testTag("suggested")) {
                    Text(p, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 13.5.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
        items(state.messages) { m -> MessageRow(m) }
        if (state.streaming) {
            item {
                Row(Modifier.fillMaxWidth().padding(top = 4.dp)) {
                    Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = t.tint, modifier = Modifier.size(18.dp).padding(top = 2.dp))
                    if (state.streamingText.isBlank()) {
                        Row(Modifier.padding(start = 9.dp, top = 6.dp).testTag("typing"), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            repeat(3) { Box(Modifier.size(7.dp).clip(CircleShape).background(t.sec)) }
                        }
                    } else {
                        Text(AiMarkdownRenderer.render(state.streamingText), color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 15.5.sp, lineHeight = 24.sp, modifier = Modifier.padding(start = 9.dp).testTag("streaming-answer"))
                    }
                }
            }
        }
        state.error?.let { err -> item { Text(err, color = t.red, fontFamily = BackupFonts.Sans, fontSize = 13.sp, modifier = Modifier.padding(top = 10.dp).testTag("chat-error")) } }
    }
}

@Composable
private fun MessageRow(m: ChatMessage) {
    val t = LocalBackupTokens.current
    if (m.fromUser) {
        Row(Modifier.fillMaxWidth().padding(bottom = 16.dp), horizontalArrangement = Arrangement.End) {
            Box(Modifier.clip(RoundedCornerShape(16.dp, 16.dp, 4.dp, 16.dp)).background(t.chipBg).padding(horizontal = 14.dp, vertical = 10.dp)) {
                Text(m.text, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 14.5.sp, lineHeight = 21.sp)
            }
        }
    } else {
        Row(Modifier.fillMaxWidth().padding(bottom = 16.dp)) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = t.tint, modifier = Modifier.size(18.dp).padding(top = 2.dp))
            Text(AiMarkdownRenderer.render(m.text), color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 15.5.sp, lineHeight = 24.sp, modifier = Modifier.padding(start = 9.dp).testTag("assistant-message"))
        }
    }
}

@Composable
private fun SummaryView(state: AiChatUiState, onRegenerate: () -> Unit) {
    val t = LocalBackupTokens.current
    Column(Modifier.fillMaxSize().padding(18.dp)) {
        if (state.streaming && state.summary == null) {
            Row(testTagged("summary-loading"), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                repeat(3) { Box(Modifier.size(7.dp).clip(CircleShape).background(t.sec)) }
            }
        } else {
            Box(Modifier.clip(RoundedCornerShape(14.dp)).background(t.card).padding(16.dp)) {
                Text(AiMarkdownRenderer.render(state.summary.orEmpty()), color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 14.5.sp, lineHeight = 22.sp, modifier = Modifier.testTag("summary-text"))
            }
            Box(
                Modifier.padding(top = 12.dp).clickable(onClick = onRegenerate).testTag("summary-regenerate"),
            ) {
                Text(
                    "Regenerate · ${state.providerName ?: "AI"}${if (state.summaryCached) " · cached" else ""}",
                    color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 12.5.sp,
                )
            }
        }
    }
}

@Composable
private fun InputBar(onSend: (String) -> Unit) {
    val t = LocalBackupTokens.current
    Box(Modifier.fillMaxWidth().height(0.5.dp).background(t.sep))
    Row(Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.weight(1f).heightIn(min = 44.dp).clip(RoundedCornerShape(22.dp)).background(t.codeBg).padding(horizontal = 16.dp), contentAlignment = Alignment.CenterStart) {
            Text("Ask a question…", color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
        }
        Box(
            Modifier.padding(start = 10.dp).size(44.dp).clip(CircleShape).background(t.tint)
                .clickable(onClickLabel = "Send", onClick = { onSend("Tell me about this book") }).testTag("ai-send"),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send", tint = Color.White, modifier = Modifier.size(20.dp)) }
    }
}

private fun testTagged(tag: String): Modifier = Modifier.testTag(tag)
