package com.vreader.app.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.assertCountEquals
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
 * Feature #132 WI-7-hosts — the PDF host renders [ReaderChromeScaffold] (mirror of WI-6's TXT host). This
 * exercises the extracted [PdfReaderChrome] host-wiring composable directly (no seeded PDF — the
 * full-Activity render defers to WI-9's connected acceptance slice): the top bar (title + Library back) +
 * a Notes bottom chrome (NO Contents — PDF has no TOC; NO Display — PDF is rasterized, #129), the Notes
 * review sheet over THIS book's snapshot, tap-to-jump (PDF onJumpToAnnotation is NON-null → jumps to the
 * annotation's page), an empty snapshot → empty review state, and a center-tap toggling chrome.
 */
@RunWith(AndroidJUnit4::class)
class PdfReaderChromeUiTest {
    @get:Rule val compose = createComposeRule()

    private fun bookLocator(page: Int) = Locator(
        contentSHA256 = "c".repeat(64), fileByteCount = 4096L, format = "pdf", page = page,
    )

    private fun highlight(id: String, text: String, page: Int) = HighlightRecord(
        id = id, bookKey = bookLocator(0).fingerprintKey, color = AnnotationColor.DEFAULT,
        selectedText = text, note = null, locator = bookLocator(page), anchor = null,
        createdAt = 1L, updatedAt = 1L,
    )

    private fun note(id: String, content: String, page: Int) = NoteRecord(
        id = id, bookKey = bookLocator(0).fingerprintKey, content = content,
        locator = bookLocator(page), anchor = null, createdAt = 2L, updatedAt = 2L,
    )

    private val emptySnapshot = AnnotationsSnapshot(highlights = emptyList(), notes = emptyList())

    @Composable
    private fun host(
        state: MutableState<ReaderChromeState>,
        snapshot: AnnotationsSnapshot,
        onJump: (AnnotationItem) -> Unit = {},
    ) {
        PdfReaderChrome(
            theme = ReaderTheme.Paper,
            title = "My PDF Book",
            chromeState = state,
            annotations = snapshot,
            onBack = {},
            onJumpToAnnotation = onJump,
            onShareAnnotations = {},
            body = { Box(Modifier.fillMaxSize().testTag("pdf-reader-body")) },
        )
    }

    @Test fun topBarAndBottomChrome_render_withNoContents_noDisplay() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, emptySnapshot) }
        compose.onNodeWithTag("reader-top-chrome", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).assertExists()
        // PDF has no TOC → the Contents control is hidden (EmptyTocProvider / empty tocEntries).
        compose.onAllNodesWithText("Contents", useUnmergedTree = true).assertCountEquals(0)
        // PDF is rasterized — #129 gives it NO Display sheet / NO Aa slot; the bottom chrome omits Display.
        compose.onAllNodesWithText("Display", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun openingNotes_listsThisBooksAnnotations() {
        val snapshot = AnnotationsSnapshot(
            highlights = listOf(highlight("h1", "the quick brown fox", 4)),
            notes = listOf(note("n1", "a standalone note", 9)),
        )
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, snapshot) }
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("annotations-sheet", useUnmergedTree = true).assertExists()
        assertTrue(
            compose.onAllNodesWithText("the quick brown fox", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty(),
        )
        assertTrue(
            compose.onAllNodesWithText("a standalone note", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty(),
        )
    }

    @Test fun emptyAnnotations_showsEmptyReviewState_noCrash() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Notes))
        compose.setContent { host(state, emptySnapshot) }
        compose.onNodeWithTag("annot-empty", useUnmergedTree = true).assertExists()
    }

    @Test fun tappingAnnotationCard_invokesJumpWithItem() {
        var jumped: AnnotationItem? = null
        val hl = highlight("h1", "jump target passage", 6)
        val snapshot = AnnotationsSnapshot(highlights = listOf(hl), notes = emptyList())
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Notes))
        compose.setContent { host(state, snapshot) { jumped = it } }
        // PDF card IS clickable (onJumpToAnnotation non-null) → the callback carries the page-bearing item.
        compose.onNodeWithTag("annot-card-h1", useUnmergedTree = true).performClick()
        assertTrue(jumped is AnnotationItem.Highlight)
        assertEquals("h1", jumped?.id)
        assertEquals(6, jumped?.locator?.page)
    }

    @Test fun centerTapBody_togglesChromeVisibility() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, emptySnapshot) }
        assertTrue(state.value.chromeVisible)
        compose.onNodeWithTag("pdf-reader-body").performTouchInput { click() }
        assertFalse(state.value.chromeVisible)
    }
}
