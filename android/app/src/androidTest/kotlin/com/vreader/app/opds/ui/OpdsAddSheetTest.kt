package com.vreader.app.opds.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
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

/** Feature #120 WI-2 — the add/edit catalog sheet: auth reveal, test states, save gating, remove. */
@RunWith(AndroidJUnit4::class)
class OpdsAddSheetTest {
    @get:Rule val compose = createComposeRule()

    @Test fun authToggle_revealsCredentialFields() {
        compose.setContent {
            var st by remember { mutableStateOf(OpdsEditState(name = "C", url = "http://h/opds")) }
            BackupSurface(darkOverride = false) {
                OpdsAddSheet(st, onRequiresAuth = { st = st.copy(requiresAuth = it) })
            }
        }
        // hidden initially; revealed after toggling sign-in on
        compose.onAllNodesWithTagCount("field-Username", 0)
        compose.onNodeWithTag("opds-auth-toggle").performScrollTo().performClick()
        compose.onNodeWithTag("field-Username").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("field-Password").performScrollTo().assertIsDisplayed()
    }

    @Test fun blankForm_doesNotSave() {
        var saved = false
        compose.setContent {
            BackupSurface(darkOverride = false) { OpdsAddSheet(OpdsEditState(name = "", url = ""), onSave = { saved = true }) }
        }
        compose.onNodeWithTag("opds-save").performClick()
        assertTrue("blank form does not save", !saved)
    }

    @Test fun completeForm_saves() {
        var saved = false
        compose.setContent {
            BackupSurface(darkOverride = false) {
                OpdsAddSheet(OpdsEditState(name = "Standard Ebooks", url = "https://standardebooks.org/opds"), onSave = { saved = true })
            }
        }
        compose.onNodeWithTag("opds-save").performClick()
        assertTrue(saved)
    }

    @Test fun testResult_ok_showsMessage() {
        compose.setContent {
            BackupSurface(darkOverride = false) {
                OpdsAddSheet(OpdsEditState(name = "C", url = "http://h/opds", test = OpdsConnTest.ok, testMessage = "Connected — the catalog responded successfully."))
            }
        }
        compose.onNodeWithText("Connected — the catalog responded successfully.").performScrollTo().assertIsDisplayed()
    }

    @Test fun editMode_showsRemove() {
        var removed = false
        compose.setContent {
            BackupSurface(darkOverride = false) {
                OpdsAddSheet(OpdsEditState(editMode = true, id = "b", name = "Calibre", url = "http://h/opds"), onRemove = { removed = true })
            }
        }
        compose.onNodeWithTag("opds-remove").performScrollTo().performClick()
        assertTrue(removed)
    }
}

/** assert N nodes with [tag] exist (avoids the assertExists API the project's Compose-test version
 *  doesn't resolve). */
private fun androidx.compose.ui.test.junit4.ComposeContentTestRule.onAllNodesWithTagCount(tag: String, count: Int) {
    onAllNodesWithTag(tag).assertCountEquals(count)
}
