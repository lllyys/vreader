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

/** Feature #118 WI-3 — the AI provider list (gate): unconfigured onboarding + configured rows. */
@RunWith(AndroidJUnit4::class)
class AiProviderListScreenTest {
    @get:Rule val compose = createComposeRule()

    @Test fun unconfigured_onboards() {
        var added = false
        compose.setContent {
            BackupSurface(darkOverride = false) { AiProviderListScreen(AiProviderListState(emptyList()), onAdd = { added = true }) }
        }
        compose.onNodeWithText("Connect an AI provider").assertIsDisplayed()
        compose.onNodeWithTag("ai-add-provider").assertIsDisplayed().performClick()
        assertTrue(added)
    }

    @Test fun configured_showsProvidersWithStatus() {
        val state = AiProviderListState(
            listOf(
                AiProviderRow("a", "Claude (Anthropic)", active = true, statusOk = true, detail = "claude-sonnet-4-6"),
                AiProviderRow("b", "DeepSeek", active = false, statusOk = false, detail = "401 — key rejected"),
            )
        )
        var edited: String? = null
        compose.setContent { BackupSurface(darkOverride = false) { AiProviderListScreen(state, onEdit = { edited = it }) } }
        compose.onNodeWithText("Claude (Anthropic)").assertIsDisplayed()
        compose.onNodeWithText("claude-sonnet-4-6").assertIsDisplayed()
        compose.onNodeWithText("401 — key rejected").assertIsDisplayed()
        compose.onNodeWithTag("provider-b").performClick()
        assertTrue(edited == "b")
    }
}
