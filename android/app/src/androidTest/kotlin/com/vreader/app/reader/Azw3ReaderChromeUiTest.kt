package com.vreader.app.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasNoClickAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.annotations.HighlightRecord
import com.vreader.app.annotations.NoteRecord
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderSheet
import com.vreader.app.reader.settings.ReaderTheme
import vreader.contracts.Locator
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #132 WI-7-hosts — the AZW3 host renders [ReaderChromeScaffold] (mirror of WI-6's TXT host, with
 * the AZW3 capability difference). This exercises the extracted [Azw3ReaderChrome] host-wiring composable
 * directly (no seeded book — the full-Activity WebView render defers to WI-9's connected acceptance
 * slice): the top bar (title + Library back) + a Notes bottom chrome (NO Contents — AZW3 has no reader
 * TOC yet; NO Display control — AZW3 applies CSS live from the store, no control surface, #129), the
 * Notes review sheet over THIS book's snapshot, and — the AZW3-specific gate — the review card is
 * NON-clickable (onJumpToAnnotation is null: review-only, no in-session goTo until #135).
 */
@RunWith(AndroidJUnit4::class)
class Azw3ReaderChromeUiTest {
    @get:Rule val compose = createComposeRule()

    private fun bookLocator(offset: Int) = Locator(
        contentSHA256 = "d".repeat(64), fileByteCount = 8192L, format = "azw3", charOffsetUTF16 = offset,
    )

    private fun highlight(id: String, text: String) = HighlightRecord(
        id = id, bookKey = bookLocator(0).fingerprintKey, color = AnnotationColor.DEFAULT,
        selectedText = text, note = null, locator = bookLocator(0), anchor = null,
        createdAt = 1L, updatedAt = 1L,
    )

    private fun note(id: String, content: String) = NoteRecord(
        id = id, bookKey = bookLocator(0).fingerprintKey, content = content,
        locator = bookLocator(0), anchor = null, createdAt = 2L, updatedAt = 2L,
    )

    private val emptySnapshot = AnnotationsSnapshot(highlights = emptyList(), notes = emptyList())

    @Composable
    private fun host(
        state: MutableState<ReaderChromeState>,
        snapshot: AnnotationsSnapshot,
    ) {
        Azw3ReaderChrome(
            theme = ReaderTheme.Paper,
            title = "My AZW3 Book",
            chromeState = state,
            annotations = snapshot,
            onBack = {},
            onShareAnnotations = {},
            body = { Box(Modifier.fillMaxSize().testTag("azw3-reader-body")) },
        )
    }

    @Test fun topBarAndBottomChrome_render_withNoContents_noDisplay() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, emptySnapshot) }
        compose.onNodeWithTag("reader-top-chrome", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).assertExists()
        // AZW3 has no reader TOC yet → Contents hidden (EmptyTocProvider). No Display control surface (#129).
        compose.onAllNodesWithText("Contents", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("Display", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun openingNotes_listsThisBooksAnnotations() {
        val snapshot = AnnotationsSnapshot(
            highlights = listOf(highlight("h1", "a kindle highlight")),
            notes = listOf(note("n1", "a kindle note")),
        )
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, snapshot) }
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("annotations-sheet", useUnmergedTree = true).assertExists()
        assertTrue(
            compose.onAllNodesWithText("a kindle highlight", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty(),
        )
        assertTrue(
            compose.onAllNodesWithText("a kindle note", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty(),
        )
    }

    @Test fun reviewCard_isNonClickable_capabilityGate() {
        // AZW3 tap-to-jump is NULL (no in-session goTo until #135) → the card is review-only, non-clickable.
        val snapshot = AnnotationsSnapshot(highlights = listOf(highlight("h1", "a kindle highlight")), notes = emptyList())
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Notes))
        compose.setContent { host(state, snapshot) }
        compose.onNodeWithTag("annot-card-h1", useUnmergedTree = true).assertHasNoClickAction()
    }

    @Test fun emptyAnnotations_showsEmptyReviewState_noCrash() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Notes))
        compose.setContent { host(state, emptySnapshot) }
        compose.onNodeWithTag("annot-empty", useUnmergedTree = true).assertExists()
    }

    @Test fun centerTapBody_togglesChromeVisibility() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, emptySnapshot) }
        assertTrue(state.value.chromeVisible)
        compose.onNodeWithTag("azw3-reader-body").performTouchInput { click() }
        assertFalse(state.value.chromeVisible)
    }
}
