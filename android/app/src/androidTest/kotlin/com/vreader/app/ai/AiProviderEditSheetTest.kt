package com.vreader.app.ai

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.backup.BackupSurface
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #118 WI-3 — the add/edit AI provider sheet. The AppSheet body is vertically scrollable, so
 * off-screen sections are scrolled into view (performScrollTo) before asserting they're displayed.
 */
@RunWith(AndroidJUnit4::class)
class AiProviderEditSheetTest {
    @get:Rule val compose = createComposeRule()

    @Test fun addMode_showsAllSections() {
        compose.setContent { BackupSurface(darkOverride = false) { AiProviderEditSheet(AiEditState(editMode = false)) } }
        compose.onNodeWithText("Add Provider").assertIsDisplayed()  // pinned header
        // GroupHeader renders text.uppercase().
        compose.onNodeWithText("PROVIDER TYPE").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("ENDPOINT").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("SAMPLING").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("API KEY").performScrollTo().assertIsDisplayed()
        compose.onNodeWithText("Test Connection").performScrollTo().assertIsDisplayed()  // chip, not a header
        compose.onNodeWithTag("kind-anthropicNative").performScrollTo().assertIsDisplayed()
    }

    @Test fun selectingKind_callsBack() {
        var picked: AiProviderKind? = null
        compose.setContent { BackupSurface(darkOverride = false) { AiProviderEditSheet(AiEditState(), onKind = { picked = it }) } }
        compose.onNodeWithTag("kind-anthropicNative").performScrollTo().performClick()
        assertTrue(picked == AiProviderKind.anthropicNative)
    }

    @Test fun test_disabledUntilKey_showsFooter() {
        compose.setContent { BackupSurface(darkOverride = false) { AiProviderEditSheet(AiEditState(apiKey = "")) } }
        compose.onNodeWithText("Enter an API key above to test — no need to save first.").performScrollTo().assertIsDisplayed()
    }

    @Test fun testResult_ok_renders() {
        compose.setContent {
            BackupSurface(darkOverride = false) {
                AiProviderEditSheet(AiEditState(apiKey = "sk", test = AiConnTest.ok, testMessage = "Connected — the provider responded successfully."))
            }
        }
        compose.onNodeWithTag("ai-test-result").performScrollTo().assertIsDisplayed()
    }

    @Test fun editMode_showsDeleteKey() {
        compose.setContent {
            BackupSurface(darkOverride = false) {
                AiProviderEditSheet(AiEditState(editMode = true, id = "x", name = "DeepSeek", keyAlreadySaved = true))
            }
        }
        compose.onNodeWithText("Edit Provider").assertIsDisplayed()
        compose.onNodeWithText("Delete Key").performScrollTo().assertIsDisplayed()
    }
}
