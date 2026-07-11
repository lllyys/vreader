package com.vreader.app.reader.chrome

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #135 WI-5 — the top-bar [BookmarkToggleButton] (vreader-reader.jsx `ReaderTopChrome` bookmark
 * button): a filled bookmark icon (accent) when the current position IS bookmarked, an outline bookmark
 * icon (ink) when it is not; tapping toggles create/remove. Design-authored, rule 51: exactly the
 * `BookmarkFilled`/`Bookmark` swap the JSX depicts, a >=48dp touch target (the trailing-cluster a11y
 * contract), and a content-description that FLIPS with state so accessibility announces the action.
 */
@RunWith(AndroidJUnit4::class)
class BookmarkToggleButtonTest {
    @get:Rule val compose = createComposeRule()

    @Test fun tapping_invokesOnToggle() {
        var toggled = false
        compose.setContent {
            BookmarkToggleButton(theme = ReaderTheme.Paper, isBookmarked = false, onToggle = { toggled = true })
        }
        compose.onNodeWithContentDescription("Add bookmark").performClick()
        assertTrue(toggled)
    }

    @Test fun unfilled_whenNotBookmarked_hasAddDescription() {
        // Not bookmarked → the a11y action is "Add bookmark" (the outline icon state).
        compose.setContent {
            BookmarkToggleButton(theme = ReaderTheme.Paper, isBookmarked = false, onToggle = {})
        }
        compose.onNodeWithContentDescription("Add bookmark").assertExists()
    }

    @Test fun filled_whenBookmarked_hasRemoveDescription() {
        // Bookmarked → the a11y action FLIPS to "Remove bookmark" (the filled icon state).
        compose.setContent {
            BookmarkToggleButton(theme = ReaderTheme.Paper, isBookmarked = true, onToggle = {})
        }
        compose.onNodeWithContentDescription("Remove bookmark").assertExists()
    }

    @Test fun contentDescription_flipsWithState() {
        // The SAME button announces the OTHER action once the bookmarked flag flips — so the a11y label
        // reflects what the NEXT tap will do (add vs remove), matching the filled/outline icon swap. This
        // proves the flip on ONE live node (a hoisted state the recomposition reads), not two independent
        // static snapshots — so setContent is called EXACTLY ONCE (a second call throws
        // IllegalStateException: has already set content).
        var isBookmarked by mutableStateOf(false)
        compose.setContent {
            BookmarkToggleButton(theme = ReaderTheme.Dark, isBookmarked = isBookmarked, onToggle = {})
        }
        // Outline state: the a11y label announces the create action.
        compose.onNodeWithContentDescription("Add bookmark").assertExists()

        // Flip the hoisted state → the same button recomposes into the filled state.
        compose.runOnIdle { isBookmarked = true }
        compose.waitForIdle()

        // The label FLIPPED on the same node: "Add bookmark" is gone, "Remove bookmark" is now present.
        compose.onNodeWithContentDescription("Remove bookmark").assertExists()
        compose.onAllNodesWithContentDescription("Add bookmark").assertCountEquals(0)
    }

    @Test fun meetsMinimumTouchTarget_unfilled() {
        compose.setContent {
            BookmarkToggleButton(theme = ReaderTheme.Paper, isBookmarked = false, onToggle = {})
        }
        compose.onNodeWithContentDescription("Add bookmark")
            .assertWidthIsAtLeast(48.dp)
            .assertHeightIsAtLeast(48.dp)
    }

    @Test fun meetsMinimumTouchTarget_filled() {
        compose.setContent {
            BookmarkToggleButton(theme = ReaderTheme.Paper, isBookmarked = true, onToggle = {})
        }
        compose.onNodeWithContentDescription("Remove bookmark")
            .assertWidthIsAtLeast(48.dp)
            .assertHeightIsAtLeast(48.dp)
    }
}
