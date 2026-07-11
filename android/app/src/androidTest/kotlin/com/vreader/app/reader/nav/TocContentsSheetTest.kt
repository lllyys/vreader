package com.vreader.app.reader.nav

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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator

/**
 * Feature #132 WI-3 — the `TocContentsSheet` (vreader-panels.jsx `TOCSheet` Contents tab): a
 * single-pane `ModalBottomSheet` of chapter rows (`ch` · title · `p.N`) over WI-1's [TocEntry].
 * The row at `currentTocIndex` is highlighted (accent + heavier weight). Tapping a row calls
 * `onJump(index)`; the sheet dismisses ONLY when `onJump` returns true (a successful jump) — a
 * failed jump (false) keeps the sheet open with NO invented error surface (rule 51
 * §nav-error-presentation). Empty entries → the `toc-empty` empty state, no rows.
 *
 * Tests target [TocContentsSheetContent] directly (the `ModalBottomSheet` chrome is exercised only
 * where its dismiss wiring matters — the content composable is the testable seam, matching the
 * `AssignSheetContent` precedent).
 */
@RunWith(AndroidJUnit4::class)
class TocContentsSheetTest {
    @get:Rule val compose = createComposeRule()

    /** Matches any node whose test tag starts with `toc-row-` (the per-row tags, not the marker). */
    private val isTocRow = SemanticsMatcher("testTag starts with toc-row-") { node ->
        node.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("toc-row-") == true
    }

    private fun entry(title: String?, page: Int?, depth: Int = 0): TocEntry =
        TocEntry(
            title = title,
            depth = depth,
            pageLabel = page?.toString(),
            canonicalLocator = Locator(
                contentSHA256 = "a".repeat(64),
                fileByteCount = 1024,
                format = "epub",
                page = page,
            ),
            epubReadiumLocator = null,
        )

    private val threeEntries = listOf(
        entry("Chapter One", 1),
        entry("Chapter Two", 17),
        entry("Chapter Three", 42),
    )

    @Test fun rendersAllContentsRows() {
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, entries = threeEntries, currentTocIndex = 0, onJump = { true })
        }
        compose.onAllNodes(isTocRow, useUnmergedTree = true).assertCountEquals(3)
        compose.onNodeWithText("Chapter One", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Chapter Two", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Chapter Three", useUnmergedTree = true).assertExists()
        // Page labels rendered as "p. N".
        compose.onNodeWithText("p. 17", useUnmergedTree = true).assertExists()
    }

    @Test fun currentRowIsHighlighted() {
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, entries = threeEntries, currentTocIndex = 1, onJump = { true })
        }
        // The highlighted row carries a stable "current" marker so the highlight is assertable without
        // reading pixels (the design's accent bg + accent/600 title is the visible form of this state).
        compose.onNodeWithTag("toc-current-marker", useUnmergedTree = true).assertExists()
        // Exactly one row is current.
        compose.onAllNodesWithTag("toc-current-marker", useUnmergedTree = true).assertCountEquals(1)
    }

    @Test fun tapRow_invokesOnJumpWithIndex() {
        var jumped: Int? = null
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, entries = threeEntries, currentTocIndex = 0, onJump = { jumped = it; true })
        }
        compose.onNodeWithTag("toc-row-2", useUnmergedTree = true).performClick()
        assertEquals(2, jumped)
    }

    // The dismiss-on-success decision lives in [TocContentsSheetContent] (the `ModalBottomSheet`
    // wrapper just passes it through) — driven directly here per the `AssignSheetContent` precedent,
    // since a `ModalBottomSheet`'s content renders in a separate window that instrumented clicks
    // reach unreliably on a loaded host.
    @Test fun successfulJump_dismissesSheet() {
        var dismissed = false
        compose.setContent {
            TocContentsSheetContent(
                theme = ReaderTheme.Paper,
                entries = threeEntries,
                currentTocIndex = 0,
                onJump = { true },
                onDismiss = { dismissed = true },
            )
        }
        compose.onNodeWithTag("toc-row-1", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        assertTrue("a successful jump (onJump=true) must dismiss the sheet", dismissed)
    }

    @Test fun failedJump_keepsSheetOpen_noErrorSurface() {
        var dismissed = false
        compose.setContent {
            TocContentsSheetContent(
                theme = ReaderTheme.Paper,
                entries = threeEntries,
                currentTocIndex = 0,
                onJump = { false },
                onDismiss = { dismissed = true },
            )
        }
        compose.onNodeWithTag("toc-row-1", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        // A failed jump keeps the sheet open (no dismiss) …
        assertFalse("a failed jump (onJump=false) must NOT dismiss the sheet", dismissed)
        // … the content + its rows are still present …
        compose.onNodeWithTag("toc-sheet-content", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("toc-row-1", useUnmergedTree = true).assertExists()
        // … and NO invented error surface was rendered (rule 51 §nav-error-presentation).
        compose.onAllNodesWithTag("toc-jump-error", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun emptyEntries_showsEmptyState_noRows() {
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, entries = emptyList(), currentTocIndex = -1, onJump = { true })
        }
        compose.onNodeWithTag("toc-empty", useUnmergedTree = true).assertExists()
        compose.onAllNodes(isTocRow, useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun untitledEntry_stillRendersRow() {
        // A null title (untitled TOC link) must not crash — the row still renders and is tappable.
        val entries = listOf(entry(null, 3), entry("Named", 9))
        var jumped: Int? = null
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Dark, entries = entries, currentTocIndex = 0, onJump = { jumped = it; true })
        }
        compose.onAllNodes(isTocRow, useUnmergedTree = true).assertCountEquals(2)
        compose.onNodeWithTag("toc-row-0", useUnmergedTree = true).performClick()
        assertEquals(0, jumped)
    }

    @Test fun entryWithoutPageLabel_omitsPageText() {
        // A null pageLabel must not render a stray "p. " — the row renders without the page span.
        val entries = listOf(entry("No Page", null))
        compose.setContent {
            TocContentsSheetContent(theme = ReaderTheme.Paper, entries = entries, currentTocIndex = 0, onJump = { true })
        }
        compose.onNodeWithText("No Page", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithTag("toc-page-0", useUnmergedTree = true).assertCountEquals(0)
    }

    // Smoke: the `ModalBottomSheet` wrapper renders its Contents content (rows land in the sheet's
    // window; asserting via the merged tree keeps this off the flaky click-into-sheet path).
    @Test fun modalBottomSheetWrapper_rendersContents() {
        compose.setContent {
            TocContentsSheet(
                theme = ReaderTheme.Paper,
                entries = threeEntries,
                currentTocIndex = 0,
                onJump = { true },
                onDismiss = {},
            )
        }
        compose.waitForIdle()
        compose.onNodeWithText("Contents").assertExists()
    }

    // Guards the local Locator shape the fixtures use (contracts type is the WI-1 dependency).
    @Test fun locatorFixtureIsWellFormed() {
        val e = entry("t", 5)
        assertEquals("epub", e.canonicalLocator.format)
        assertEquals(5, e.canonicalLocator.page)
        assertNull(e.epubReadiumLocator)
    }
}
