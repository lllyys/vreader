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
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.click
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.annotations.AnnotationsSnapshot
import com.vreader.app.reader.nav.TocEntry
import com.vreader.app.reader.settings.ReaderTheme
import vreader.contracts.Locator
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
}
