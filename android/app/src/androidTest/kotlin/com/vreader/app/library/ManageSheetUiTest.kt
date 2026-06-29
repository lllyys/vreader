package com.vreader.app.library

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.data.Collection
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #127 WI-5 — the manage-collections sheet content lists collections + their counts (the
 * design's `CollectionsManageSheet` list mode), taps a name → inline rename (submit reports the new
 * name), and the "New Collection" inline-create reports the name. Renders `ManageSheetContent` directly.
 * Delete is intentionally absent — deferred to a needs-design follow-up (rule 51).
 */
@RunWith(AndroidJUnit4::class)
class ManageSheetUiTest {
    @get:Rule val compose = createComposeRule()

    private val cols = listOf(
        Collection(id = "c1", name = "Fiction", createdAt = 1L, bookCount = 3),
        Collection(id = "c2", name = "Tech", createdAt = 2L, bookCount = 1),
    )

    @Test fun listsCollections_withCounts() {
        compose.setContent { ManageSheetContent(cols, { _, _ -> }, {}) }
        compose.onNodeWithText("Collections").assertIsDisplayed()
        compose.onNodeWithText("Fiction").assertIsDisplayed()
        compose.onNodeWithText("Tech").assertIsDisplayed()
        compose.onNodeWithText("3", useUnmergedTree = true).assertExists()  // Fiction's book count
    }

    @Test fun tappingName_revealsRenameField_andSubmitReportsNewName() {
        var renamed: Pair<String, String>? = null
        compose.setContent { ManageSheetContent(cols, { id, name -> renamed = id to name }, {}) }
        compose.onNodeWithTag("manage-name-Fiction", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("manage-rename-field", useUnmergedTree = true).performTextClearance()
        compose.onNodeWithTag("manage-rename-field", useUnmergedTree = true).performTextInput("Novels")
        compose.onNodeWithTag("manage-rename-field", useUnmergedTree = true).performImeAction()
        assertEquals("c1" to "Novels", renamed)
    }

    @Test fun inlineNewCollection_revealsField_andSubmitReportsName() {
        var created: String? = null
        compose.setContent { ManageSheetContent(cols, { _, _ -> }, { created = it }) }
        compose.onNodeWithTag("manage-new-collection").performClick()
        compose.onNodeWithTag("manage-new-collection-field").performTextInput("History")
        compose.onNodeWithTag("manage-new-collection-field").performImeAction()
        assertEquals("History", created)
    }
}
