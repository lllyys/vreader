package com.vreader.app.reader.chrome

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #132 WI-5 — the additive Contents/Notes slot extension of [ReaderBottomChrome]. The new slots
 * render ONLY when their nullable callback is non-null (the #129 no-dead-controls rule); a #129-era
 * Display-only caller (both callbacks null) still compiles + renders (back-compat); AI is never rendered.
 */
@RunWith(AndroidJUnit4::class)
class ReaderBottomChromeSlotsTest {
    @get:Rule val compose = createComposeRule()

    @Test fun contentsRenders_onlyWithCallback_andInvokesIt() {
        var opened = false
        compose.setContent {
            ReaderBottomChrome(
                ReaderTheme.Paper, progress = 0.4f, displayPage = 5, totalPages = 100,
                onScrub = {}, onOpenDisplay = {}, onOpenContents = { opened = true }, onOpenNotes = {},
            )
        }
        compose.onNodeWithText("Contents", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-contents", useUnmergedTree = true).performClick()
        assertTrue(opened)
    }

    @Test fun notesRenders_onlyWithCallback_andInvokesIt() {
        var opened = false
        compose.setContent {
            ReaderBottomChrome(
                ReaderTheme.Paper, progress = 0.4f, displayPage = 5, totalPages = 100,
                onScrub = {}, onOpenDisplay = {}, onOpenContents = {}, onOpenNotes = { opened = true },
            )
        }
        compose.onNodeWithText("Notes", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).performClick()
        assertTrue(opened)
    }

    @Test fun displayOnlyCaller_stillRenders_slotsAbsent_backCompat() {
        // A #129-era caller passing no Contents/Notes callbacks must compile + render Display only.
        compose.setContent {
            ReaderBottomChrome(
                ReaderTheme.Dark, progress = 0.4f, displayPage = 5, totalPages = 100,
                onScrub = {}, onOpenDisplay = {},
            )
        }
        compose.onNodeWithTag("reader-bottom-chrome").assertExists()
        compose.onNodeWithText("Display", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithText("Contents", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("Notes", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("AI", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun aiNeverRenders_evenWithBothNewSlots() {
        compose.setContent {
            ReaderBottomChrome(
                ReaderTheme.Paper, progress = 0.4f, displayPage = 5, totalPages = 100,
                onScrub = {}, onOpenDisplay = {}, onOpenContents = {}, onOpenNotes = {},
            )
        }
        compose.onAllNodesWithText("AI", useUnmergedTree = true).assertCountEquals(0)
    }
}
