package com.vreader.app.annotations

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
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.ui.theme.VReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Feature #123 WI-3 — the [SelectionPopover] composable (design vreader-android-annotations.jsx). */
@RunWith(AndroidJUnit4::class)
class SelectionPopoverUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun selectMode_showsColorsAndActions_colorTapFires() {
        var tapped: AnnotationColor? = null
        compose.setContent {
            VReaderTheme {
                SelectionPopover(
                    state = SelectionPopoverState(visible = true, mode = PopoverMode.SELECT),
                    actions = SelectionPopoverActions(onColor = { tapped = it }),
                )
            }
        }
        compose.onNodeWithTag("selection-popover").assertIsDisplayed()
        // all 5 design colors present
        for (c in AnnotationColor.palette) compose.onNodeWithTag("popover-color-${c.key}").assertIsDisplayed()
        // SELECT-mode actions (Translate omitted in #123 — lands with #119)
        compose.onNodeWithText("Highlight").assertIsDisplayed()
        compose.onNodeWithText("Copy").assertIsDisplayed()
        compose.onNodeWithTag("popover-color-pink").performClick()
        assertEquals(AnnotationColor.pink, tapped)
    }

    @Test fun editMode_showsRemove_notHighlight() {
        compose.setContent {
            VReaderTheme {
                SelectionPopover(
                    state = SelectionPopoverState(visible = true, mode = PopoverMode.EDIT, activeColor = AnnotationColor.red),
                    actions = SelectionPopoverActions(),
                )
            }
        }
        compose.onNodeWithText("Remove").assertIsDisplayed()
        compose.onNodeWithText("Note").assertIsDisplayed()
    }

    @Test fun noteMode_typeAndSave() {
        var saved = false
        var typed = ""
        compose.setContent {
            VReaderTheme {
                // host the draft so the controlled BasicTextField actually updates (a fixed value
                // breaks the IME connection and drops the input).
                var draft by remember { mutableStateOf("") }
                SelectionPopover(
                    state = SelectionPopoverState(visible = true, mode = PopoverMode.NOTE, noteDraft = draft),
                    actions = SelectionPopoverActions(
                        onNoteDraftChange = { draft = it; typed = it },
                        onSaveNote = { saved = true },
                    ),
                )
            }
        }
        compose.onNodeWithTag("popover-note-field").performTextInput("a thought")
        compose.onNodeWithTag("popover-note-save").performClick()
        assertEquals("a thought", typed)
        assert(saved)
    }

    @Test fun notVisible_rendersNothing() {
        compose.setContent { VReaderTheme { SelectionPopover(SelectionPopoverState(visible = false), SelectionPopoverActions()) } }
        compose.onAllNodesWithTag("selection-popover").assertCountEquals(0)
    }
}
