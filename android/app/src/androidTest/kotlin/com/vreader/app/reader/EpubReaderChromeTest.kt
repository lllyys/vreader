package com.vreader.app.reader

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderSheet
import com.vreader.app.reader.details.BookDetailsUiModel
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #134 WI-5 — the EPUB chrome's Book Details route + touch-through guard. The EPUB host is the
 * outlier (a Readium fragment under the chrome), so the full-screen [EpubReaderSheets] layer must stay
 * touch-through whenever no *renderable* sheet is up. The Gate-4 P1 regression: a [ReaderSheet.Details]
 * route with a NULL model renders no sheet yet would otherwise leave the invisible dismiss overlay
 * intercepting the fragment's input — so it must normalize back to [ReaderSheet.None] (no overlay). With a
 * model, the Details sheet renders. Live Compose execution rides WI-6 acceptance; this compiles + exercises
 * the pure guard.
 */
@RunWith(AndroidJUnit4::class)
class EpubReaderChromeTest {
    @get:Rule val compose = createComposeRule()

    private val model = MutableStateFlow(ReaderChromeModel(title = "The Book"))

    private fun detailsModel() = BookDetailsUiModel(
        title = "The Book",
        author = "An Author",
        tags = emptyList(),
        formatLabel = "EPUB",
        sizeLabel = "2 MB",
        pagesLabel = null,
        fingerprintDisplay = "epub:aaaa…bbbb",
        fingerprintFull = "epub:${"a".repeat(64)}:2097152",
        locationLabel = "Books/epub_a1b2",
    )

    @Test fun detailsRoute_withNullModel_normalizesToNone_noDismissOverlay() {
        // A Details route with no model must NOT leave the touch-blocking dismiss overlay up — the guard
        // normalizes the state back to None (touch-through preserved for the Readium fragment).
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Details))
        compose.setContent {
            EpubReaderSheets(
                model = model,
                theme = ReaderTheme.Paper,
                chromeState = state,
                onJumpToc = { true },
                onShareAnnotations = {},
                bookDetails = null,
            )
        }
        compose.onAllNodesWithTag("epub-sheet-dismiss-overlay", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("book-details-sheet-content", useUnmergedTree = true).assertCountEquals(0)
        assertEquals(ReaderSheet.None, state.value.sheet)
    }

    @Test fun detailsRoute_withModel_rendersBookDetailsSheet() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Details))
        compose.setContent {
            EpubReaderSheets(
                model = model,
                theme = ReaderTheme.Paper,
                chromeState = state,
                onJumpToc = { true },
                onShareAnnotations = {},
                bookDetails = detailsModel(),
                onShareBook = {},
                onCopyFingerprint = {},
            )
        }
        compose.onNodeWithTag("book-details-sheet-content", useUnmergedTree = true).assertExists()
    }

    @Test fun noneRoute_rendersNoOverlay() {
        // Baseline: the None route renders nothing (fully touch-through) — unchanged by WI-5.
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent {
            EpubReaderSheets(
                model = model,
                theme = ReaderTheme.Paper,
                chromeState = state,
                onJumpToc = { true },
                onShareAnnotations = {},
                bookDetails = detailsModel(),
            )
        }
        compose.onAllNodesWithTag("epub-sheet-dismiss-overlay", useUnmergedTree = true).assertCountEquals(0)
    }
}
