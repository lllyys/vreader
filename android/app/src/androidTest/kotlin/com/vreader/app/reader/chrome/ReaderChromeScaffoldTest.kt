package com.vreader.app.reader.chrome

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
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.reader.details.BookDetailsUiModel
import com.vreader.app.reader.nav.TocEntry
import com.vreader.app.reader.settings.ReaderTheme
import vreader.contracts.Locator
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #132 WI-5 — the host-agnostic [ReaderChromeScaffold]: it stacks the top chrome, the body, the
 * bottom chrome, and hosts the Contents/Notes sheets driven by the hoisted [ReaderChromeState]. Center-
 * tapping the body toggles chrome visibility; opening Contents shows the Toc sheet, opening Notes shows
 * the annotations review sheet; an empty [tocEntries] hides the Contents control.
 */
@RunWith(AndroidJUnit4::class)
class ReaderChromeScaffoldTest {
    @get:Rule val compose = createComposeRule()

    private fun locator() = Locator(
        contentSHA256 = "a".repeat(64), fileByteCount = 1024L, format = "txt", charOffsetUTF16 = 0,
    )

    private fun tocEntry(title: String) = TocEntry(
        title = title, depth = 0, pageLabel = "1", canonicalLocator = locator(), epubReadiumLocator = null,
    )

    private val emptySnapshot = AnnotationsSnapshot(highlights = emptyList(), notes = emptyList())

    @Composable
    private fun scaffold(
        state: MutableState<ReaderChromeState>,
        tocEntries: List<TocEntry>,
    ) {
        ReaderChromeScaffold(
            theme = ReaderTheme.Paper,
            title = "The Book",
            chromeState = state,
            onBack = {},
            tocEntries = tocEntries,
            currentTocIndex = 0,
            annotations = emptySnapshot,
            onJumpToc = { true },
            onJumpToAnnotation = null,
            onShareAnnotations = {},
            bottomChrome = { onOpenContents, onOpenNotes ->
                ReaderBottomChrome(
                    ReaderTheme.Paper, progress = 0f, displayPage = 1, totalPages = 10,
                    onScrub = {}, onOpenDisplay = {}, onOpenContents = onOpenContents, onOpenNotes = onOpenNotes,
                )
            },
            body = {
                Box(Modifier.fillMaxSize().testTag("reader-body"))
            },
        )
    }

    @Test fun centerTapBody_togglesChromeVisibility() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { scaffold(state, listOf(tocEntry("Ch 1"))) }
        assertTrue(state.value.chromeVisible)
        compose.onNodeWithTag("reader-body").performTouchInput { click() }
        assertFalse(state.value.chromeVisible)
    }

    @Test fun openingContents_showsTocSheet() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { scaffold(state, listOf(tocEntry("Ch 1"))) }
        compose.onNodeWithTag("chrome-contents", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("toc-sheet", useUnmergedTree = true).assertExists()
    }

    @Test fun openingNotes_showsAnnotationsSheet() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { scaffold(state, listOf(tocEntry("Ch 1"))) }
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("annotations-sheet", useUnmergedTree = true).assertExists()
    }

    @Test fun emptyToc_hidesContentsControl() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { scaffold(state, emptyList()) }
        compose.onAllNodesWithText("Contents", useUnmergedTree = true).assertCountEquals(0)
    }

    // --- feature #134 WI-5: the top-bar More button + Book Details route ---

    private fun detailsModel() = BookDetailsUiModel(
        title = "The Book",
        author = "An Author",
        tags = emptyList(),
        formatLabel = "TXT",
        sizeLabel = "1 KB",
        pagesLabel = null,
        fingerprintDisplay = "txt:aaaa…bbbb",
        fingerprintFull = "txt:${"a".repeat(64)}:1024",
        locationLabel = "Books/txt_a1b2",
    )

    @Composable
    private fun moreScaffold(
        state: MutableState<ReaderChromeState>,
        bookDetails: BookDetailsUiModel?,
        onShareBook: () -> Unit = {},
        onCopyFingerprint: (String) -> Unit = {},
    ) {
        ReaderChromeScaffold(
            theme = ReaderTheme.Paper,
            title = "The Book",
            chromeState = state,
            onBack = {},
            tocEntries = emptyList(),
            currentTocIndex = 0,
            annotations = emptySnapshot,
            onJumpToc = { true },
            onJumpToAnnotation = null,
            onShareAnnotations = {},
            bookDetails = bookDetails,
            onShareBook = onShareBook,
            onCopyFingerprint = onCopyFingerprint,
            bottomChrome = { onOpenContents, onOpenNotes ->
                ReaderBottomChrome(
                    ReaderTheme.Paper, progress = 0f, displayPage = 1, totalPages = 10,
                    onScrub = {}, onOpenDisplay = {}, onOpenContents = onOpenContents, onOpenNotes = onOpenNotes,
                )
            },
            body = { Box(Modifier.fillMaxSize().testTag("reader-body")) },
        )
    }

    @Test fun moreButtonShown_whenBookDetailsSupplied() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { moreScaffold(state, detailsModel()) }
        compose.onNodeWithTag("chrome-more", useUnmergedTree = true).assertExists()
    }

    @Test fun tappingMore_showsPopupWithDetailsAndShareOnly() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { moreScaffold(state, detailsModel()) }
        compose.onNodeWithTag("chrome-more", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("more-popup", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("more-row-details", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("more-row-share", useUnmergedTree = true).assertExists()
        // No dead TTS / Auto-turn / Bilingual / Export rows.
        compose.onAllNodesWithTag("more-row-tts", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("more-row-auto_turn", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("more-row-bilingual", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("more-row-export", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun tappingDetailsRow_opensBookDetailsSheet() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { moreScaffold(state, detailsModel()) }
        compose.onNodeWithTag("chrome-more", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("more-row-details", useUnmergedTree = true).performClick()
        assertEquals(ReaderSheet.Details, state.value.sheet)
    }

    @Test fun tappingShareRow_firesOnShareBook() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        var shared = false
        compose.setContent { moreScaffold(state, detailsModel(), onShareBook = { shared = true }) }
        compose.onNodeWithTag("chrome-more", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("more-row-share", useUnmergedTree = true).performClick()
        assertTrue(shared)
    }

    @Test fun detailsRoute_rendersBookDetailsSheet() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Details))
        compose.setContent { moreScaffold(state, detailsModel()) }
        compose.onNodeWithTag("book-details-sheet-content", useUnmergedTree = true).assertExists()
    }

    @Test fun moreButtonHidden_whenNoBookDetails() {
        // No data source → no More button (the #129 no-dead-control rule).
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { moreScaffold(state, bookDetails = null) }
        compose.onAllNodesWithTag("chrome-more", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun detailsRoute_withNullBookDetails_showsNothing() {
        // Defensive: a Details route with no model (should not happen, but must not crash / NPE).
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Details))
        compose.setContent { moreScaffold(state, bookDetails = null) }
        compose.onAllNodesWithTag("book-details-sheet-content", useUnmergedTree = true).assertCountEquals(0)
    }

    // --- feature #135 WI-5: the top-bar bookmark toggle slot + the Bookmarks route ---

    @Composable
    private fun bookmarkScaffold(
        state: MutableState<ReaderChromeState>,
        isCurrentBookmarked: Boolean = false,
        onToggleBookmark: (() -> Unit)? = null,
    ) {
        ReaderChromeScaffold(
            theme = ReaderTheme.Paper,
            title = "The Book",
            chromeState = state,
            onBack = {},
            tocEntries = emptyList(),
            currentTocIndex = 0,
            annotations = emptySnapshot,
            onJumpToc = { true },
            onJumpToAnnotation = null,
            onShareAnnotations = {},
            isCurrentBookmarked = isCurrentBookmarked,
            onToggleBookmark = onToggleBookmark,
            bottomChrome = { onOpenContents, onOpenNotes ->
                ReaderBottomChrome(
                    ReaderTheme.Paper, progress = 0f, displayPage = 1, totalPages = 10,
                    onScrub = {}, onOpenDisplay = {}, onOpenContents = onOpenContents, onOpenNotes = onOpenNotes,
                )
            },
            body = { Box(Modifier.fillMaxSize().testTag("reader-body")) },
        )
    }

    @Test fun bookmarkSlotAbsent_whenNoToggleCallback() {
        // #132 Contents/Notes-only back-compat: a host that does NOT opt into the bookmark toggle sees no
        // dead bookmark control in the top bar (the #129 no-dead-control rule).
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { bookmarkScaffold(state, onToggleBookmark = null) }
        compose.onAllNodesWithTag("chrome-bookmark-slot", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun bookmarkSlotPresent_whenToggleCallbackSupplied() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { bookmarkScaffold(state, onToggleBookmark = {}) }
        compose.onNodeWithTag("chrome-bookmark-slot", useUnmergedTree = true).assertExists()
    }

    @Test fun tappingBookmarkSlot_firesOnToggleBookmark() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        var toggled = false
        compose.setContent {
            bookmarkScaffold(state, isCurrentBookmarked = false, onToggleBookmark = { toggled = true })
        }
        compose.onNodeWithContentDescription("Add bookmark").performClick()
        assertTrue(toggled)
    }

    @Test fun bookmarkSlot_reflectsBookmarkedState() {
        // isCurrentBookmarked=true → the filled/Remove state is rendered in the slot.
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent {
            bookmarkScaffold(state, isCurrentBookmarked = true, onToggleBookmark = {})
        }
        compose.onNodeWithContentDescription("Remove bookmark").assertExists()
    }

    @Test fun bookmarksRoute_rendersNoUndesignedSurface() {
        // WI-5 adds the Bookmarks ROUTE only; the designed Bookmarks LIST surface is WI-6's
        // TocBookmarksSheet (rule 51). The route must be a safe no-op here — no invented list, no crash,
        // and (unlike Details) no full-screen dismiss scrim to intercept touch.
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Bookmarks))
        compose.setContent { bookmarkScaffold(state, onToggleBookmark = {}) }
        // No designed sheet is shown; the body is still present (the route rendered nothing).
        compose.onNodeWithTag("reader-body").assertExists()
        compose.onAllNodesWithTag("toc-sheet", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("book-details-sheet-content", useUnmergedTree = true).assertCountEquals(0)
    }
}
