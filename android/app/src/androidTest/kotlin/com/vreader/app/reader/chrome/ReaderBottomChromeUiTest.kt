package com.vreader.app.reader.chrome

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #129 WI-3 — the `ReaderBottomChrome` shell: the Display slot opens settings, the scrubber tap
 * seeks (onScrub), the scrubber + page labels render, and the Contents/Notes/AI slots are OMITTED (no
 * dead placeholders — the LibraryScreen precedent + the Gate-2 ruling).
 */
@RunWith(AndroidJUnit4::class)
class ReaderBottomChromeUiTest {
    @get:Rule val compose = createComposeRule()

    @Test fun tappingDisplay_invokesOnOpenDisplay() {
        var opened = false
        compose.setContent {
            ReaderBottomChrome(ReaderTheme.Paper, progress = 0.4f, displayPage = 5, totalPages = 100, onScrub = {}, onOpenDisplay = { opened = true })
        }
        compose.onNodeWithTag("chrome-display", useUnmergedTree = true).performClick()
        assertTrue(opened)
    }

    @Test fun tappingScrubber_invokesOnScrub() {
        var scrubbed: Float? = null
        compose.setContent {
            ReaderBottomChrome(ReaderTheme.Paper, progress = 0.4f, displayPage = 5, totalPages = 100, onScrub = { scrubbed = it }, onOpenDisplay = {})
        }
        // The track has pointerInput gesture handlers (no semantics click action) — drive raw touch.
        compose.onNodeWithTag("scrubber-track", useUnmergedTree = true).performTouchInput { click() }
        assertNotNull("a tap on the scrubber seeks", scrubbed)
        assertTrue(scrubbed!! in 0f..1f)
    }

    @Test fun rendersScrubberAndDisplayOnly_omittedSlotsAbsent() {
        compose.setContent {
            ReaderBottomChrome(ReaderTheme.Dark, progress = 0.4f, displayPage = 5, totalPages = 100, onScrub = {}, onOpenDisplay = {})
        }
        compose.onNodeWithTag("reader-bottom-chrome").assertExists()
        compose.onNodeWithTag("scrubber-thumb", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Display", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Page 5", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("95 pages left in book", useUnmergedTree = true).assertExists()
        // The omitted slots must not ship as dead placeholders.
        compose.onAllNodesWithText("Contents", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("Notes", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("AI", useUnmergedTree = true).assertCountEquals(0)
    }
}
