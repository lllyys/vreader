package com.vreader.app.library

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performImeAction
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.data.Collection
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #127 WI-4 — the assign-to-collections sheet content renders the book + a checklist of
 * collections (member = check, non-member = ring), tapping a row reports the toggle (no auto-close),
 * and the inline "New Collection…" reveals a field whose submit reports the name. Renders
 * `AssignSheetContent` directly (the ModalBottomSheet wrapper is the same content).
 */
@RunWith(AndroidJUnit4::class)
class AssignSheetUiTest {
    @get:Rule val compose = createComposeRule()

    private val cols = listOf(
        Collection(id = "c1", name = "Fiction", createdAt = 1L, bookCount = 0),
        Collection(id = "c2", name = "Tech", createdAt = 2L, bookCount = 0),
    )

    @Test fun rendersRows_withCheckedAndUncheckedState() {
        compose.setContent { AssignSheetContent("My Book", cols, setOf("c1"), { _, _ -> }, {}) }
        compose.onNodeWithText("Add to Collection").assertIsDisplayed()
        compose.onNodeWithText("My Book").assertIsDisplayed()
        compose.onNodeWithText("Fiction").assertIsDisplayed()
        // the check/ring icons live inside the clickable row, whose semantics MERGE the children →
        // find them in the unmerged tree.
        compose.onNodeWithTag("assign-check-Fiction", useUnmergedTree = true).assertExists()   // member → check
        compose.onNodeWithTag("assign-uncheck-Tech", useUnmergedTree = true).assertExists()    // non-member → ring
    }

    @Test fun tappingUncheckedRow_reportsToggleOn() {
        var toggled: Pair<String, Boolean>? = null
        compose.setContent { AssignSheetContent("My Book", cols, setOf("c1"), { id, now -> toggled = id to now }, {}) }
        compose.onNodeWithTag("assign-row-Tech").performClick()
        assertEquals("c2" to true, toggled)
        // tapping a member row reports toggle OFF.
        compose.onNodeWithTag("assign-row-Fiction").performClick()
        assertEquals("c1" to false, toggled)
    }

    @Test fun inlineNewCollection_revealsField_andSubmitReportsName() {
        var created: String? = null
        compose.setContent { AssignSheetContent("My Book", cols, emptySet(), { _, _ -> }, { created = it }) }
        compose.onNodeWithTag("assign-new-collection").performClick()
        compose.onNodeWithTag("assign-new-collection-field").performTextInput("Sci-Fi")
        compose.onNodeWithTag("assign-new-collection-field").performImeAction()
        assertEquals("Sci-Fi", created)
    }
}
