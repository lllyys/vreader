package com.vreader.app.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasNoClickAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
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
 * Feature #132 WI-7-hosts, extended by **feature #140 WI-6** — the AZW3 host's chrome wiring.
 *
 * #132 shipped the shared [com.vreader.app.reader.chrome.ReaderChromeScaffold] on this host with NO
 * Contents control: the host passed `tocEntries = emptyList()` **and** the bottom-chrome slot threw the
 * scaffold's Contents open-callback away (`bottomChrome = { _, onOpenNotes -> … }`). #140 WI-6 feeds a
 * real TOC **and** wires that callback, which is what actually makes the control appear — a non-empty
 * `tocEntries` alone would light up nothing.
 *
 * Every assertion here is made against the **real** [Azw3ReaderChrome] → `ReaderChromeScaffold` →
 * `Azw3BottomChrome` stack (no stubbed bottom chrome). That is deliberate: a test that supplied its own
 * bottom chrome would pass with the discarded `_` still in place, i.e. it would pass on exactly the
 * defect this WI exists to fix.
 *
 * Two shapes this suite deliberately avoids:
 *  - **Depth-field assertions are not indentation assertions.** [nestedEntry_isIndentedPastItsParent]
 *    measures the laid-out left edge of a depth-1 title against a depth-0 one (the #139 acceptance-
 *    criterion-7 technique); asserting `TocEntry.depth` would pass on a sheet that ignored it.
 *  - **Ack is not motion.** The two `tappingRow_*` cases are about SHEET BEHAVIOUR (dismiss-on-success /
 *    stay-open-on-failure) only. Whether the reader actually moved is WI-7's real-book connected
 *    round-trip — foliate's `view.goTo` swallows a failed resolution and still acks `ok:true`, so no
 *    assertion here may be read as proof of navigation.
 *
 * No seeded book — the full-Activity WebView render is WI-7's connected slice.
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

    // ---- the TOC fixture -----------------------------------------------------------------------

    /** A TOC row shaped exactly as [com.vreader.app.reader.nav.FoliateTocProvider] emits one: an
     *  href-bearing canonical locator with NO progression, no page label, no Readium locator. */
    private fun tocEntry(title: String, depth: Int, href: String) = TocEntry(
        title = title,
        depth = depth,
        pageLabel = null,
        canonicalLocator = Locator(
            contentSHA256 = "d".repeat(64), fileByteCount = 8192L, format = "azw3", href = href,
        ),
        epubReadiumLocator = null,
    )

    /**
     * Two parts, each with one nested chapter — the common Kindle NCX shape. Rows 2 and 3 are the
     * depth-0/depth-1 pair the indentation test measures: keeping them OFF index 0 matters, because the
     * current row carries a zero-size marker child that still consumes the row's arrangement spacing and
     * would shift its title right by more than a depth step (the #139 finding).
     */
    private val chapters = listOf(
        tocEntry("Part One", 0, "text/part0001.html"),
        tocEntry("Chapter One", 1, "text/part0001.html#c1"),
        tocEntry("Part Two", 0, "text/part0002.html"),
        tocEntry("Chapter Two", 1, "text/part0002.html#c2"),
    )

    // ---- harness -------------------------------------------------------------------------------

    @Composable
    private fun host(
        state: MutableState<ReaderChromeState>,
        snapshot: AnnotationsSnapshot,
        tocEntries: List<TocEntry> = emptyList(),
        currentTocIndex: Int = 0,
        onJumpToc: (Int) -> Boolean = { false },
    ) {
        Azw3ReaderChrome(
            theme = ReaderTheme.Paper,
            title = "My AZW3 Book",
            chromeState = state,
            annotations = snapshot,
            onBack = {},
            onShareAnnotations = {},
            tocEntries = tocEntries,
            currentTocIndex = currentTocIndex,
            onJumpToc = onJumpToc,
            body = { Box(Modifier.fillMaxSize().testTag("azw3-reader-body")) },
        )
    }

    private fun nodeCount(tag: String) =
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().size

    private fun textExists(text: String) =
        compose.onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    /** The laid-out left edge of the title `Text` inside a Contents row — the indentation a reader
     *  actually sees, as opposed to the `depth` field that produced it. */
    private fun titleLeftInRow(rowTag: String, title: String): Float {
        val row = compose.onNodeWithTag(rowTag, useUnmergedTree = true).fetchSemanticsNode()
        val child = row.children.firstOrNull { node ->
            node.config.getOrNull(SemanticsProperties.Text)?.any { it.text.contains(title) } == true
        } ?: throw AssertionError("no '$title' title text inside $rowTag")
        return child.positionInRoot.x
    }

    /** Whether the zero-size `toc-current-marker` (the highlighted-row state's assertable form) sits
     *  inside [rowTag] — i.e. whether THAT row is the current chapter, not merely that some row is. */
    private fun rowIsCurrent(rowTag: String): Boolean {
        val row = compose.onNodeWithTag(rowTag, useUnmergedTree = true).fetchSemanticsNode()
        fun walk(node: SemanticsNode): Boolean =
            node.config.getOrNull(SemanticsProperties.TestTag) == "toc-current-marker" ||
                node.children.any(::walk)
        return row.children.any(::walk)
    }

    private fun openContentsSheet() {
        compose.onNodeWithTag("chrome-contents", useUnmergedTree = true).performClick()
        compose.waitUntil(10_000) { nodeCount("toc-sheet-content") > 0 }
    }

    // ---- the control ---------------------------------------------------------------------------

    /**
     * The pre-#140 posture, kept as the regression: a book with NO usable TOC keeps the Contents
     * control hidden (the scaffold's `tocEntries.isEmpty()` rule), and the rest of the toolbar is
     * unaffected — Notes is still there. AZW3 also has no Display control surface (#129 applies CSS
     * live from the store), so "Display" stays absent too.
     */
    @Test fun emptyToc_hidesContents_notesStillPresent() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, emptySnapshot) }
        compose.onNodeWithTag("reader-top-chrome", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithText("Contents", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("Display", useUnmergedTree = true).assertCountEquals(0)
        assertEquals("no Contents control with an empty TOC", 0, nodeCount("chrome-contents"))
    }

    /**
     * THE user-visible delta of this WI. Every build before it hid the Contents control on AZW3 twice
     * over — an empty `tocEntries` AND a discarded open-callback — so this must be asserted through the
     * real bottom chrome or it proves nothing.
     */
    @Test fun nonEmptyToc_showsContentsControl() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, emptySnapshot, tocEntries = chapters) }
        compose.onNodeWithTag("azw3-bottom-chrome", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("chrome-contents", useUnmergedTree = true).assertExists()
        assertTrue("the designed 'Contents' label renders", textExists("Contents"))
        // Notes survives the change; Display is still absent (AZW3 has no Display control surface).
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithText("Display", useUnmergedTree = true).assertCountEquals(0)
    }

    /** The designed toolbar order is Contents · Notes · Display · AI; AZW3 renders the first two, in
     *  that order. Measured on the laid-out x positions, not on declaration order. */
    @Test fun contentsAndNotes_bothRenderInTheDesignedOrder() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, emptySnapshot, tocEntries = chapters) }
        val contentsX = compose.onNodeWithTag("chrome-contents", useUnmergedTree = true)
            .fetchSemanticsNode().positionInRoot.x
        val notesX = compose.onNodeWithTag("chrome-notes", useUnmergedTree = true)
            .fetchSemanticsNode().positionInRoot.x
        assertTrue("Contents precedes Notes (was $contentsX vs $notesX)", contentsX < notesX)
    }

    // ---- the sheet -----------------------------------------------------------------------------

    @Test fun tappingContents_opensSheet_listingEveryChapterTitle() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, emptySnapshot, tocEntries = chapters) }
        openContentsSheet()
        assertEquals(ReaderSheet.Toc, state.value.sheet)
        for (entry in chapters) {
            assertTrue("the Contents sheet lists '${entry.title}'", textExists(entry.title!!))
        }
        assertEquals("no empty state for a book that HAS a TOC", 0, nodeCount("toc-empty"))
        assertEquals("one row per entry", chapters.size, nodeCount("toc-row-0") + nodeCount("toc-row-1") + nodeCount("toc-row-2") + nodeCount("toc-row-3"))
    }

    /**
     * The nesting is VISIBLE, not merely modelled: the depth-1 title is laid out to the right of its
     * depth-0 sibling. Rows 2/3 are compared (never row 0) because the current row's zero-size marker
     * child consumes the row's arrangement spacing and would shift its title by more than a depth step.
     */
    @Test fun nestedEntry_isIndentedPastItsParent() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Toc))
        compose.setContent { host(state, emptySnapshot, tocEntries = chapters, currentTocIndex = 0) }
        compose.waitUntil(10_000) { nodeCount("toc-row-3") > 0 }
        val parent = titleLeftInRow("toc-row-2", "Part Two")
        val child = titleLeftInRow("toc-row-3", "Chapter Two")
        assertTrue("depth 1 indents past depth 0 (was $child vs $parent)", child > parent)
    }

    /**
     * The current-chapter highlight lands on the row the host named — asserted at a NON-ZERO index on
     * purpose: `foliateTocIndexFor` returns 0 both for "row 0 is current" and for "nothing matched", so
     * a zero-index fixture cannot tell a working highlight from a broken one.
     */
    @Test fun currentChapterRow_carriesTheCurrentMarker_atANonZeroIndex() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Toc))
        compose.setContent { host(state, emptySnapshot, tocEntries = chapters, currentTocIndex = 2) }
        compose.waitUntil(10_000) { nodeCount("toc-row-3") > 0 }
        assertEquals("exactly one row is current", 1, nodeCount("toc-current-marker"))
        assertTrue("row 2 is the current chapter", rowIsCurrent("toc-row-2"))
        assertFalse("row 0 is NOT current", rowIsCurrent("toc-row-0"))
    }

    // ---- row taps: SHEET behaviour only (not navigation — see the class KDoc) -------------------

    /**
     * A row whose jump reports failure leaves the sheet open — no invented error surface (rule 51).
     * This asserts the sheet's dismiss decision ONLY; it says nothing about whether the reader moved.
     */
    @Test fun tappingRow_whenJumpReportsFailure_keepsSheetOpen() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Toc))
        var tapped = -1
        compose.setContent {
            host(state, emptySnapshot, tocEntries = chapters, currentTocIndex = 0) { index ->
                tapped = index; false
            }
        }
        compose.waitUntil(10_000) { nodeCount("toc-row-1") > 0 }
        compose.onNodeWithTag("toc-row-1", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        assertEquals("the tapped row's index reached the host", 1, tapped)
        assertEquals(ReaderSheet.Toc, state.value.sheet)
        assertTrue("the sheet is still on screen", nodeCount("toc-sheet-content") > 0)
    }

    /** A row whose jump reports success dismisses the sheet (the designed dismiss-on-success). Again:
     *  sheet behaviour only — an ack is not motion. */
    @Test fun tappingRow_whenJumpReportsSuccess_dismissesSheet() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Toc))
        var tapped = -1
        compose.setContent {
            host(state, emptySnapshot, tocEntries = chapters, currentTocIndex = 0) { index ->
                tapped = index; true
            }
        }
        compose.waitUntil(10_000) { nodeCount("toc-row-2") > 0 }
        compose.onNodeWithTag("toc-row-2", useUnmergedTree = true).performClick()
        compose.waitUntil(10_000) { nodeCount("toc-sheet-content") == 0 }
        assertEquals("the tapped row's index reached the host", 2, tapped)
        assertEquals(ReaderSheet.None, state.value.sheet)
    }

    // ---- unchanged #132 behaviour ---------------------------------------------------------------

    @Test fun openingNotes_listsThisBooksAnnotations() {
        val snapshot = AnnotationsSnapshot(
            highlights = listOf(highlight("h1", "a kindle highlight")),
            notes = listOf(note("n1", "a kindle note")),
        )
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent { host(state, snapshot) }
        compose.onNodeWithTag("chrome-notes", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("annotations-sheet", useUnmergedTree = true).assertExists()
        assertTrue(textExists("a kindle highlight"))
        assertTrue(textExists("a kindle note"))
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
