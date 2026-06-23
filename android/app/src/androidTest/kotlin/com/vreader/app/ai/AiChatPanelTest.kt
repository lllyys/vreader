package com.vreader.app.ai

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.backup.BackupSurface
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Feature #118 WI-4 — the AI chat + summary panel states (unconfigured / idle / answer / summary). */
@RunWith(AndroidJUnit4::class)
class AiChatPanelTest {
    @get:Rule val compose = createComposeRule()

    @Test fun unconfigured_gatesToSettings() {
        var opened = false
        compose.setContent { BackupSurface(darkOverride = false) { AiChatPanel(AiChatUiState(unconfigured = true), onOpenSettings = { opened = true }) } }
        compose.onNodeWithText("Connect a provider first").assertIsDisplayed()
        compose.onNodeWithTag("ai-open-settings").performClick()
        assertTrue(opened)
    }

    @Test fun idle_showsSuggestedPrompts() {
        compose.setContent { BackupSurface(darkOverride = false) { AiChatPanel(AiChatUiState(unconfigured = false, providerName = "Claude")) } }
        compose.onNodeWithText("Ask about this book").assertIsDisplayed()
        compose.onNodeWithText("Who is the main character?").assertIsDisplayed()
    }

    @Test fun answer_rendersAssistantMessage() {
        val state = AiChatUiState(
            unconfigured = false, providerName = "Claude",
            messages = listOf(ChatMessage(true, "Who is Bingley?"), ChatMessage(false, "A wealthy bachelor.")),
        )
        compose.setContent { BackupSurface(darkOverride = false) { AiChatPanel(state) } }
        compose.onNodeWithTag("assistant-message").assertIsDisplayed()
    }

    @Test fun summary_showsCachedRegenerate() {
        val state = AiChatUiState(unconfigured = false, providerName = "Claude", mode = AiChatMode.summary, summary = "- one\n- two", summaryCached = true)
        compose.setContent { BackupSurface(darkOverride = false) { AiChatPanel(state) } }
        compose.onNodeWithText("Chapter summary").assertIsDisplayed()
        compose.onNodeWithTag("summary-text").assertIsDisplayed()
        compose.onNodeWithTag("summary-regenerate").assertIsDisplayed()
    }
}
