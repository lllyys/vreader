package com.vreader.app.reader.nav

import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator

/**
 * Feature #139 WI-6 — the Contents sheet at REAL TXT scale. The #132 sheet rendered its rows in a
 * non-lazy `Column(verticalScroll)`, which is fine for a 30-entry EPUB TOC and an ANR at the ~1 859
 * rows the real 14 MB CJK book produces. This suite pins the two halves of the fix:
 *
 * 1. **Laziness** — only the visible window is composed, for a 2 000-entry TOC.
 * 2. **Laziness survives the positioning pass** — opening at row 1 500 must compose ONE window; a
 *    measurement or animation pass that walked the intervening rows would silently defeat the whole
 *    WI. The assertions are mechanism-agnostic (they bound work, not API choice), so they hold for a
 *    seeded first-visible index and would equally catch a `scrollToItem`/`animateScrollToItem` that
 *    forced full composition.
 *
 * The oracle is deliberately NOT just a node count (a Compose assertion on a node that was never
 * composed passes trivially). [CountingEntries] counts every `List.get(index)` the composition
 * performs: the non-lazy `forEachIndexed` predecessor iterates the list and therefore reads all
 * 2 000 entries, while a `LazyColumn` reads only the window it composes. The bounds below sit an
 * order of magnitude under 2 000, so the two implementations cannot both pass.
 *
 * Contract preservation is checked here too (empty state, rule-51 no-error-surface on a failed
 * jump); the full #132 contract stays pinned by `TocContentsSheetTest`, which must pass UNMODIFIED.
 */
@RunWith(AndroidJUnit4::class)
class TocContentsLargeTocTest {
    @get:Rule val compose = createComposeRule()

    /** Matches any node whose test tag starts with `toc-row-` (the per-row tags, not the marker). */
    private val isTocRow = SemanticsMatcher("testTag starts with toc-row-") { node ->
        node.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("toc-row-") == true
    }

    /**
     * A `List<TocEntry>` that counts every element read. `kotlin.collections.AbstractList`'s own
     * iterator is implemented over `get(index)`, so an eager `forEachIndexed` over the whole list
     * registers one read per entry — that is what makes this a differential oracle for laziness and
     * not a restatement of the implementation.
     */
    private class CountingEntries(private val backing: List<TocEntry>) : AbstractList<TocEntry>() {
        val reads = AtomicInteger(0)
        override val size: Int get() = backing.size
        override fun get(index: Int): TocEntry {
            reads.incrementAndGet()
            return backing[index]
        }
    }

    private fun entry(title: String?, page: Int?, depth: Int = 0, sha: String = BOOK_A_SHA): TocEntry =
        TocEntry(
            title = title,
            depth = depth,
            pageLabel = page?.toString(),
            canonicalLocator = Locator(
                contentSHA256 = sha,
                fileByteCount = 14_000_000,
                format = "txt",
                page = page,
            ),
            epubReadiumLocator = null,
        )

    /** 2 000 flat entries — the shape `TxtMdTocProvider` produces for the real 14 MB CJK book. */
    private fun largeToc(count: Int = LARGE_COUNT): CountingEntries =
        CountingEntries(List(count) { entry("Chapter ${it + 1}", it + 1) })

    private fun composedRowCount(): Int =
        compose.onAllNodes(isTocRow, useUnmergedTree = true).fetchSemanticsNodes().size

    private fun nodeCount(tag: String): Int =
        compose.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().size

    @Test fun twoThousandEntries_sheetOpensWithoutAnr() {
        // ANR avoidance is asserted STRUCTURALLY — bounded work to open — not as a wall-clock
        // threshold. A stopwatch around `setContent` on a shared emulator measures host load, font and
        // shader warm-up and instrumentation scheduling; it flakes above the bar without the main
        // thread ever being blocked, and passing under it proves nothing about frame time (Gate-4 R1
        // MEDIUM). What actually causes the ANR is composing all 2 000 rows to open, and that is
        // exactly what the read/row bounds below exclude.
        val entries = largeToc()
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, bookTitle = "黑暗血时代", entries = entries, currentTocIndex = 0, onJump = { true })
        }
        compose.waitForIdle()

        // The sheet is up and usable — header, rows, no empty state.
        compose.onNodeWithTag("toc-sheet-content", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("toc-title", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("toc-row-0", useUnmergedTree = true).assertExists()
        assertEquals("a non-empty TOC must not show the empty state", 0, nodeCount("toc-empty"))
        assertTrue("opening read ${entries.reads.get()} of $LARGE_COUNT entries", entries.reads.get() <= MAX_ENTRY_READS)
    }

    @Test fun twoThousandEntries_onlyVisibleRowsAreComposed() {
        val entries = largeToc()
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, bookTitle = "黑暗血时代", entries = entries, currentTocIndex = 0, onJump = { true })
        }
        compose.waitForIdle()

        val rows = composedRowCount()
        assertTrue("no rows composed at all — the assertion below would pass vacuously", rows >= 1)
        assertTrue("$rows of $LARGE_COUNT rows composed — the list is not lazy", rows <= MAX_COMPOSED_ROWS)
        val reads = entries.reads.get()
        assertTrue("read $reads of $LARGE_COUNT entries — the whole list was walked", reads <= MAX_ENTRY_READS)
    }

    @Test fun scrollToCurrent_doesNotForceFullComposition() {
        // THE TRAP: opening at a far-down index must not walk there. An animated scroll — or any
        // measurement pass over the intervening rows — composes all 1 500 rows on the way and makes
        // the LazyColumn pointless. Laziness has to hold END-TO-END, not just at first layout.
        // (Probed: `animateScrollToItem` fails this test at 1 390/2 000 entries read.)
        val entries = largeToc()
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, bookTitle = "黑暗血时代", entries = entries, currentTocIndex = FAR_INDEX, onJump = { true })
        }
        compose.waitForIdle()

        val reads = entries.reads.get()
        assertTrue("scroll-to-current read $reads of $LARGE_COUNT entries — it walked the list", reads <= MAX_ENTRY_READS)
        val rows = composedRowCount()
        assertTrue("no rows composed at all — the bound below would pass vacuously", rows >= 1)
        assertTrue("$rows rows composed after scroll-to-current — full composition", rows <= MAX_COMPOSED_ROWS)
        // … and the jump genuinely happened: the target is composed, the top of the list is not.
        compose.onNodeWithTag("toc-row-$FAR_INDEX", useUnmergedTree = true).assertExists()
        assertEquals("row 0 must be off-screen after jumping to $FAR_INDEX", 0, nodeCount("toc-row-0"))
    }

    @Test fun opensScrolledToCurrentEntry_whenCurrentIsFarDownTheList() {
        val entries = largeToc()
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, bookTitle = "黑暗血时代", entries = entries, currentTocIndex = FAR_INDEX, onJump = { true })
        }
        compose.waitForIdle()

        // The designed current-row highlight is actually on screen (that is the point of the scroll).
        compose.onNodeWithText("Chapter ${FAR_INDEX + 1}", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithTag("toc-current-marker", useUnmergedTree = true).assertCountEquals(1)
    }

    @Test fun emptyEntries_stillRendersDesignedEmptyState() {
        // Rule 51: the designed empty state must render exactly as before — no lazy list, no rows.
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, bookTitle = "黑暗血时代", entries = emptyList(), currentTocIndex = -1, onJump = { true })
        }
        compose.waitForIdle()
        compose.onNodeWithTag("toc-empty", useUnmergedTree = true).assertExists()
        assertEquals(0, composedRowCount())
        assertEquals("no scroll container is rendered for an empty TOC", 0, nodeCount("toc-list"))
    }

    @Test fun tapRow_returningFalse_keepsSheetOpen() {
        // The rule-51 no-error-surface contract survives the lazy conversion.
        val entries = largeToc()
        var dismissed = false
        var jumped: Int? = null
        compose.setContent {
            TocContentsSheetContent(
                theme = ReaderTheme.Paper,
                bookTitle = "黑暗血时代",
                entries = entries,
                currentTocIndex = FAR_INDEX,
                onJump = { jumped = it; false },
                onDismiss = { dismissed = true },
            )
        }
        compose.waitForIdle()
        compose.onNodeWithTag("toc-row-$FAR_INDEX", useUnmergedTree = true).performClick()
        compose.waitForIdle()

        assertEquals("the tapped row's index is reported", FAR_INDEX, jumped)
        assertFalse("a failed jump (onJump=false) must NOT dismiss the sheet", dismissed)
        compose.onNodeWithTag("toc-sheet-content", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("toc-row-$FAR_INDEX", useUnmergedTree = true).assertExists()
        assertEquals("no invented error surface", 0, nodeCount("toc-jump-error"))
    }

    @Test fun txtTitleWithEmbeddedNewline_hasLineBreaksRemoved() {
        // WI-2: a TXT rule can legitimately match ACROSS a line terminator, so a TXT chapter title can
        // carry an embedded newline (MD titles never can — WI-3). The presentation layer removes the
        // break, so the title does not spend one of the row's two wrap lines on it. This asserts the
        // STRING, not a rendered line count — the row's `maxLines = 2` wrapping is unchanged.
        val entries = listOf(entry("第一章\n黑暗降临", 1), entry("Second\r\n  Chapter", 2))
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, bookTitle = "黑暗血时代", entries = entries, currentTocIndex = 0, onJump = { true })
        }
        compose.waitForIdle()
        compose.onNodeWithText("第一章 黑暗降临", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Second Chapter", useUnmergedTree = true).assertExists()
        assertEquals(0, nodeCount("toc-empty"))
    }

    @Test fun cjkIdeographicSpaceInTitle_isPreserved() {
        // Guard against OVER-normalizing: U+3000 IDEOGRAPHIC SPACE is the author's spacing in CJK
        // titles (and the leading class every TXT rule consumes). Only line-breaking runs collapse;
        // leading/trailing whitespace is trimmed, interior ideographic spacing is untouched.
        val entries = listOf(entry("　第一章　黑暗降临　", 1))
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, bookTitle = "黑暗血时代", entries = entries, currentTocIndex = 0, onJump = { true })
        }
        compose.waitForIdle()
        compose.onNodeWithText("第一章　黑暗降临", useUnmergedTree = true).assertExists()
    }

    @Test fun noCurrentIndex_rendersFromTop_noMarker() {
        // A host that has entries but no resolved current chapter passes -1 (WI-5's contract).
        val entries = largeToc()
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, bookTitle = "黑暗血时代", entries = entries, currentTocIndex = -1, onJump = { true })
        }
        compose.waitForIdle()
        compose.onNodeWithTag("toc-row-0", useUnmergedTree = true).assertExists()
        assertEquals("no row is current when currentTocIndex is out of range", 0, nodeCount("toc-current-marker"))
        assertTrue(entries.reads.get() <= MAX_ENTRY_READS)
    }

    @Test fun staleCurrentIndexPastEnd_rendersFromTop_noMarker() {
        // The positive out-of-range half: a stale index left over from a longer TOC must not crash the
        // seeded scroll position, and must not mark any row current.
        val entries = largeToc()
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, bookTitle = "黑暗血时代", entries = entries, currentTocIndex = LARGE_COUNT + 5, onJump = { true })
        }
        compose.waitForIdle()
        compose.onNodeWithTag("toc-row-0", useUnmergedTree = true).assertExists()
        assertEquals(0, nodeCount("toc-current-marker"))
        assertTrue(entries.reads.get() <= MAX_ENTRY_READS)
    }

    @Test fun differentBookSameSize_opensAtTheNewBooksCurrentEntry() {
        // The content composable is reusable, so its scroll position must be keyed on the BOOK, not on
        // "whatever was here last". Identity is the contentSHA256 baked into WI-1's canonical locators
        // — O(1), unlike list equality. Swapping in another book's TOC of the SAME size must re-open at
        // the new book's current chapter instead of silently retaining the old position (Gate-4 R1).
        val bookA = List(LARGE_COUNT) { entry("A ${it + 1}", it + 1, sha = BOOK_A_SHA) }
        val bookB = List(LARGE_COUNT) { entry("B ${it + 1}", it + 1, sha = BOOK_B_SHA) }
        val shown = mutableStateOf(bookA)
        val current = mutableIntStateOf(0)
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, bookTitle = "黑暗血时代", entries = shown.value, currentTocIndex = current.intValue, onJump = { true })
        }
        compose.waitForIdle()
        compose.onNodeWithText("A 1", useUnmergedTree = true).assertExists()

        compose.runOnIdle {
            shown.value = bookB
            current.intValue = FAR_INDEX
        }
        compose.waitForIdle()
        compose.onNodeWithText("B ${FAR_INDEX + 1}", useUnmergedTree = true).assertExists()
        assertEquals("the new book must not open at the old book's position", 0, nodeCount("toc-row-0"))
    }

    @Test fun currentIndexChangeWhileOpen_doesNotMoveTheList() {
        // CONTRACT, defined at WI-6 (Gate-4 R1 asked for it to be explicit): the list is positioned
        // ONCE, at open. The sheet is modal over the reader, so the reading position cannot advance
        // behind it; re-positioning later could only yank a user who is browsing. A same-book index
        // change therefore moves the HIGHLIGHT and leaves the viewport where the user put it.
        val entries = largeToc()
        val current = mutableIntStateOf(0)
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, bookTitle = "黑暗血时代", entries = entries, currentTocIndex = current.intValue, onJump = { true })
        }
        compose.waitForIdle()
        compose.onNodeWithTag("toc-row-0", useUnmergedTree = true).assertExists()

        compose.runOnIdle { current.intValue = FAR_INDEX }
        compose.waitForIdle()
        compose.onNodeWithTag("toc-row-0", useUnmergedTree = true).assertExists()
        assertEquals("the viewport must not jump under the user", 0, nodeCount("toc-row-$FAR_INDEX"))
        assertEquals("the now-current row is off screen, so no marker composes", 0, nodeCount("toc-current-marker"))
        assertTrue(entries.reads.get() <= MAX_ENTRY_READS)
    }

    private companion object {
        const val BOOK_A_SHA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        const val BOOK_B_SHA = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

        /** The real 14 MB CJK book yields ~1 859 entries; 2 000 is the round number above it. */
        const val LARGE_COUNT = 2_000
        /** A current chapter deep in the list — far past anything a first layout would compose. */
        const val FAR_INDEX = 1_500

        /**
         * Bounds, deliberately generous (≈3–15 % of [LARGE_COUNT]) so they measure LAZINESS, not the
         * exact viewport arithmetic: a 560 dp viewport over ≥48 dp rows shows ~11 rows, plus Compose's
         * reuse pool and prefetch, times a handful of recomposition passes. The eager predecessor
         * reads/composes all 2 000, so nothing near these numbers is ambiguous.
         */
        const val MAX_COMPOSED_ROWS = 60
        const val MAX_ENTRY_READS = 300
    }
}
