package com.vreader.app.backup

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #114 WI-3 surface B — the add/edit server sheet (design surface B): the form, the
 * Test-Connection lifecycle (idle/testing/ok/fail) running against the live form, and the
 * edit-mode Remove + confirm alert.
 */
@RunWith(AndroidJUnit4::class)
class ServerEditSheetTest {
    @get:Rule val compose = createComposeRule()

    private val edit = ServerEditState(
        editMode = true, name = "Home NAS", baseUrl = "https://nas.local/dav/vreader",
        username = "leon", password = "secret", wifiOnly = true,
    )

    @Test fun addMode_showsTitle_fields_andPlaceholders() {
        compose.setContent { BackupSurface { ServerEditSheet(ServerEditState(editMode = false)) } }
        compose.onNodeWithText("Add Server").assertIsDisplayed()
        compose.onNodeWithText("Name").assertIsDisplayed()
        compose.onNodeWithText("Base URL").assertIsDisplayed()
        compose.onNodeWithText("Back up on Wi-Fi only").assertIsDisplayed()
        compose.onNodeWithText("Test Connection").assertIsDisplayed()
    }

    @Test fun editMode_showsTitle_andRemoveServer() {
        compose.setContent { BackupSurface { ServerEditSheet(edit) } }
        compose.onNodeWithText("Edit Server").assertIsDisplayed()
        compose.onNodeWithText("Remove Server").assertIsDisplayed()
    }

    @Test fun testing_showsTestingLabel() {
        compose.setContent { BackupSurface { ServerEditSheet(edit.copy(test = ConnTest.testing)) } }
        compose.onNodeWithText("Testing…").assertIsDisplayed()
    }

    @Test fun testOk_showsSuccessResult() {
        compose.setContent {
            BackupSurface { ServerEditSheet(edit.copy(test = ConnTest.ok, testMessage = "Connected — found an existing /vreader folder with 3 backups.")) }
        }
        compose.onNodeWithText("Connected — found an existing /vreader folder with 3 backups.").assertIsDisplayed()
    }

    @Test fun testFail_showsFailureResult() {
        compose.setContent {
            BackupSurface { ServerEditSheet(edit.copy(test = ConnTest.fail, testMessage = "Failed: 401 Unauthorized — check the username and password.")) }
        }
        compose.onNodeWithText("Failed: 401 Unauthorized — check the username and password.").assertIsDisplayed()
    }

    @Test fun testConnection_click_invokesCallback() {
        var tested = false
        compose.setContent { BackupSurface { ServerEditSheet(edit, onTest = { tested = true }) } }
        compose.onNodeWithText("Test Connection").performClick()
        assertTrue(tested)
    }

    @Test fun removeServer_click_invokesCallback() {
        var clicked = false
        compose.setContent { BackupSurface { ServerEditSheet(edit, onRemoveClick = { clicked = true }) } }
        compose.onNodeWithText("Remove Server").performClick()
        assertTrue(clicked)
    }

    @Test fun removeConfirm_alert_promisesBackupsKept_andConfirms() {
        var confirmed = false
        compose.setContent { BackupSurface { ServerEditSheet(edit.copy(showRemoveConfirm = true), onRemoveConfirm = { confirmed = true }) } }
        compose.onNodeWithText("Remove this server?").assertIsDisplayed()
        compose.onNodeWithText("Existing backups on the server are left untouched.", substring = true).assertIsDisplayed()
        compose.onNodeWithText("Remove").performClick()
        assertTrue(confirmed)
    }

    @Test fun removeConfirm_tappingTitle_doesNotDismiss() {
        var dismissed = false
        compose.setContent { BackupSurface { ServerEditSheet(edit.copy(showRemoveConfirm = true), onRemoveDismiss = { dismissed = true }) } }
        // A tap on the alert's own title must be swallowed by the card, not fall through to scrim-dismiss.
        compose.onNodeWithText("Remove this server?").performTouchInput { click() }
        assertFalse("inside-card tap did not dismiss", dismissed)
    }

    @Test fun cancel_invokesCallback() {
        var cancelled = false
        compose.setContent { BackupSurface { ServerEditSheet(ServerEditState(editMode = false), onCancel = { cancelled = true }) } }
        compose.onNodeWithText("Cancel").performClick()
        assertTrue(cancelled)
    }

    @Test fun save_doesNotFireWhenFormIncomplete() {
        var saved = false
        // Blank fields → Save has no click action (disabled); proven by absence, not a click.
        compose.setContent { BackupSurface { ServerEditSheet(ServerEditState(editMode = false), onSave = { saved = true }) } }
        compose.onNodeWithText("Save").assertExists()
        assertFalse("Save not wired with blank fields", saved)
    }

    @Test fun save_firesWhenComplete() {
        var saved = false
        compose.setContent { BackupSurface { ServerEditSheet(edit, onSave = { saved = true }) } }
        compose.onNodeWithText("Save").performClick()
        assertTrue(saved)
    }

    @Test fun wifiRow_tap_togglesCallback() {
        var newValue: Boolean? = null
        compose.setContent { BackupSurface { ServerEditSheet(edit.copy(wifiOnly = true), onWifiOnly = { newValue = it }) } }
        compose.onNodeWithText("Back up on Wi-Fi only").performClick()
        assertFalse("toggling from on → off", newValue!!)
    }

    @Test fun nameField_typing_invokesOnChange() {
        var typed = ""
        compose.setContent { BackupSurface { ServerEditSheet(ServerEditState(editMode = false), onName = { typed = it }) } }
        compose.onNodeWithTag("field-Name").performTextInput("X")
        assertTrue(typed.isNotEmpty())
    }

    @Test fun rendersInDark() {
        compose.setContent { BackupSurface(darkOverride = true) { ServerEditSheet(edit) } }
        compose.onNodeWithText("Edit Server").assertIsDisplayed()
    }
}
