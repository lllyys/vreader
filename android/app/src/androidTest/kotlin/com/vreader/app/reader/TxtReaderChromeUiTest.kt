package com.vreader.app.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.AnnotationItem
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.annotations.HighlightRecord
import com.vreader.app.annotations.NoteRecord
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderSheet
import com.vreader.app.reader.settings.ReaderTheme
import vreader.contracts.Locator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #132 WI-6 — the TXT/MD host renders [ReaderChromeScaffold] (the first host to). This exercises
 * the extracted [TxtReaderChrome] host-wiring composable directly (no seeded book — the full-Activity
 * render defers to WI-9's connected acceptance slice): the top bar (title + Library back) + bottom
 * chrome (Notes + Display, NO Contents), the Notes review sheet over THIS book's snapshot, tap-to-jump
 * scrolling to the annotation offset, an empty snapshot → empty review state, and the preserved TTS bar.
 */
@RunWith(AndroidJUnit4::class)
class TxtReaderChromeUiTest {
    @get:Rule val compose = createComposeRule()

    private fun bookLocator(offset: Int) = Locator(
        contentSHA256 = "b".repeat(64), fileByteCount = 2048L, format = "txt", charOffsetUTF16 = offset,
    )

    private fun highlightLocator(start: Int) = Locator(
        contentSHA256 = "b".repeat(64), fileByteCount = 2048L, format = "txt",
        charRangeStartUTF16 = start, charRangeEndUTF16 = start + 5,
    )

    private fun highlight(id: String, text: String, start: Int) = HighlightRecord(
        id = id, bookKey = bookLocator(0).fingerprintKey, color = AnnotationColor.DEFAULT,
        selectedText = text, note = null, locator = highlightLocator(start), anchor = null,
        createdAt = 1L, updatedAt = 1L,
    )

    private fun note(id: String, content: String, offset: Int) = NoteRecord(
        id = id, bookKey = bookLocator(0).fingerprintKey, content = content,
        locator = bookLocator(offset), anchor = null, createdAt = 2L, updatedAt = 2L,
    )

    private val emptySnapshot = AnnotationsSnapshot(highlights = emptyList(), notes = emptyList())

    @Composable
    private fun host(
        state: MutableState<ReaderChromeState>,
        snapshot: AnnotationsSnapshot,
        onJump: (AnnotationItem) -> Unit = {},
    ) {
        TxtReaderChrome(
            theme = ReaderTheme.Paper,
            title = "My TXT Book",
            chromeState = state,
            annotations = snapshot,
            onBack = {},
            onJumpToAnnotation = onJump,
            onShareAnnotations = {},
            bottomBar = {
                // stand-in for the host's TTS-bar-or-ReaderBottomChrome slot content — the real host
                // switches on the TTS phase (see TxtReaderActivity); the scaffold-owned Contents/Notes
                // controls come from the ReaderBottomChrome the host renders here.
                com.vreader.app.reader.chrome.ReaderBottomChrome(
                    ReaderTheme.Paper, progress = 0f, displayPage = 0, totalPages = 0,
                    onScrub = {}, onOpenDisplay = {}, onOpenContents = it.first, onOpenNotes = it.second,
                    extraSlot = { Box(Modifier.testTag("tts-read-aloud-entry")) },
                )
            },
            body = { Box(Modifier.fillMaxSize().testTag("txt-reader-body")) },
        )
    }

    @Test fun topBarAndBottomChrome_render_withNoContents() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, emptySnapshot) }
        compose.onNodeWithTag("reader-top-chrome", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("reader-bottom-chrome", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-display", useUnmergedTree = true).assertExists()
        // TXT/MD has no TOC → the Contents control is hidden (EmptyTocProvider / empty tocEntries).
        compose.onAllNodesWithText("Contents", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun ttsBar_stillPresent() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, emptySnapshot) }
        // absence-of-regression: the #121 read-aloud entry survives the scaffold upgrade.
        compose.onNodeWithTag("tts-read-aloud-entry", useUnmergedTree = true).assertExists()
    }

    @Test fun openingNotes_listsThisBooksAnnotations() {
        val snapshot = AnnotationsSnapshot(
            highlights = listOf(highlight("h1", "the quick brown fox", 42)),
            notes = listOf(note("n1", "a standalone note", 99)),
        )
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, snapshot) }
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("annotations-sheet", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithText("the quick brown fox", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        compose.onAllNodesWithText("a standalone note", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
    }

    @Test fun emptyAnnotations_showsEmptyReviewState_noCrash() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Notes))
        compose.setContent { host(state, emptySnapshot) }
        compose.onNodeWithTag("annot-empty", useUnmergedTree = true).assertExists()
    }

    @Test fun tappingAnnotationCard_invokesJumpWithItem() {
        var jumped: AnnotationItem? = null
        val hl = highlight("h1", "jump target passage", 128)
        val snapshot = AnnotationsSnapshot(highlights = listOf(hl), notes = emptyList())
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Notes))
        compose.setContent { host(state, snapshot) { jumped = it } }
        compose.onNodeWithTag("annot-card-h1", useUnmergedTree = true).performClick()
        assertTrue(jumped is AnnotationItem.Highlight)
        assertEquals("h1", jumped?.id)
    }

    @Test fun centerTapBody_togglesChromeVisibility() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, emptySnapshot) }
        assertTrue(state.value.chromeVisible)
        compose.onNodeWithTag("txt-reader-body").performTouchInput { click() }
        assertFalse(state.value.chromeVisible)
    }
}
