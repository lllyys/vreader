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
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderSheet
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #133 WI-12 — the negative-assertion regression backing the "PDF/AZW3 show NO Search icon"
 * acceptance criterion. In-book search is UNSUPPORTED for the rasterized PDF host and the foliate-js
 * AZW3 host (WI-7's `IndexStateGate` returns `Unsupported`), so neither [PdfReaderChrome] nor
 * [Azw3ReaderChrome] forwards an `onOpenSearch` into [com.vreader.app.reader.chrome.ReaderChromeScaffold]
 * — the scaffold's `onSearch` stays null and [com.vreader.app.reader.chrome.ReaderTopChrome] never renders
 * its `chrome-search` control (the #129 no-dead-control rule). This test renders each host chrome directly
 * (mirroring the sibling [PdfReaderChromeUiTest] / [Azw3ReaderChromeUiTest] setup — same theme, same empty
 * snapshot, same host params) and asserts the `chrome-search` node is ABSENT on both. A set of positive
 * controls (`reader-top-chrome` + `chrome-back` + `chrome-notes`) is asserted PRESENT in the same pass so
 * the absence is proven specific — the chrome genuinely rendered, it just omits Search — not a blank render.
 */
@RunWith(AndroidJUnit4::class)
class SearchHiddenOnPdfAzw3Test {
    @get:Rule val compose = createComposeRule()

    private val emptySnapshot = AnnotationsSnapshot(highlights = emptyList(), notes = emptyList())

    @Composable
    private fun pdfHost(state: MutableState<ReaderChromeState>) {
        PdfReaderChrome(
            theme = ReaderTheme.Paper,
            title = "My PDF Book",
            chromeState = state,
            annotations = emptySnapshot,
            onBack = {},
            onJumpToAnnotation = {},
            onShareAnnotations = {},
            body = { Box(Modifier.fillMaxSize().testTag("pdf-reader-body")) },
        )
    }

    @Composable
    private fun azw3Host(state: MutableState<ReaderChromeState>) {
        Azw3ReaderChrome(
            theme = ReaderTheme.Paper,
            title = "My AZW3 Book",
            chromeState = state,
            annotations = emptySnapshot,
            onBack = {},
            onShareAnnotations = {},
            onOpenDisplay = {},
            body = { Box(Modifier.fillMaxSize().testTag("azw3-reader-body")) },
        )
    }

    /** The chrome rendered (top bar + back + Notes) but the Search control is absent — PDF is unsupported. */
    @Test fun pdfTopChrome_rendersWithoutSearchIcon() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { pdfHost(state) }
        // Positive controls prove the top chrome actually rendered (not a blank / no-op render).
        compose.onNodeWithTag("reader-top-chrome", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-back", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).assertExists()
        // The negative assertion: NO in-book Search control on the PDF host (IndexStateGate Unsupported).
        compose.onAllNodesWithTag("chrome-search", useUnmergedTree = true).assertCountEquals(0)
    }

    /** The chrome rendered (top bar + back + Notes) but the Search control is absent — AZW3 is unsupported. */
    @Test fun azw3TopChrome_rendersWithoutSearchIcon() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { azw3Host(state) }
        // Positive controls prove the top chrome actually rendered (not a blank / no-op render).
        compose.onNodeWithTag("reader-top-chrome", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-back", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).assertExists()
        // The negative assertion: NO in-book Search control on the AZW3 host (IndexStateGate Unsupported).
        compose.onAllNodesWithTag("chrome-search", useUnmergedTree = true).assertCountEquals(0)
    }
}
