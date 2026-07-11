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
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator

/**
 * Feature #135 WI-6 — the `TocBookmarksSheet` (vreader-panels.jsx `TOCSheet` — the promoted two-tab
 * `Contents | Bookmarks` sheet). The wrapper hosts a segmented tab bar and REUSES #132's
 * [TocContentsSheetContent] UNCHANGED as the Contents tab body (one-writer serialization — WI-6 does
 * NOT edit `TocContentsSheet.kt` in place). The Bookmarks tab renders rows from a
 * `List<BookmarkRowItem>` (bookmark icon · italic serif preview · `chapter · p.N · date` · chevron);
 * tapping a row calls `onJumpBookmark(record)` and dismisses ONLY on [JumpResult.Succeeded] (a
 * [JumpResult.Failed] keeps the sheet open — the #132 §navigation-outcome posture). Empty bookmarks →
 * the `bookmarks-empty` state. NO delete affordance (deferred — absence assertion).
 *
 * Tests target [TocBookmarksSheetContent] directly (the `AssignSheetContent`/`TocContentsSheetContent`
 * precedent — a `ModalBottomSheet`'s content renders in a separate window instrumented clicks reach
 * unreliably on a loaded host; the content composable is the testable seam).
 */
@RunWith(AndroidJUnit4::class)
class TocBookmarksSheetTest {
    @get:Rule val compose = createComposeRule()

    private val isTocRow = SemanticsMatcher("testTag starts with toc-row-") { node ->
        node.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("toc-row-") == true
    }
    private val isBookmarkRow = SemanticsMatcher("testTag starts with bookmark-row-") { node ->
        node.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("bookmark-row-") == true
    }

    private fun tocEntry(title: String?, page: Int?): TocEntry =
        TocEntry(
            title = title,
            depth = 0,
            pageLabel = page?.toString(),
            canonicalLocator = Locator(contentSHA256 = "a".repeat(64), fileByteCount = 1024, format = "epub", page = page),
            epubReadiumLocator = null,
        )

    private val threeContents = listOf(
        tocEntry("Chapter One", 1),
        tocEntry("Chapter Two", 17),
        tocEntry("Chapter Three", 42),
    )

    private fun bookmark(id: String, offset: Int = 0): BookmarkRecord =
        BookmarkRecord(
            id = id,
            bookKey = "book-1",
            title = null,
            locator = Locator(contentSHA256 = "a".repeat(64), fileByteCount = 1024, format = "epub", charOffsetUTF16 = offset),
            createdAt = 1_000L,
            updatedAt = 1_000L,
        )

    private fun row(id: String, preview: String?, chapter: String?, page: String?, date: String): BookmarkRowItem =
        BookmarkRowItem(
            record = bookmark(id),
            ui = BookmarkRowUi(preview = preview, chapter = chapter, pageLabel = page, dateLabel = date),
        )

    private val threeBookmarks = listOf(
        row("bm-1", "It is a truth universally acknowledged…", "Chapter 1", "p. 1", "Apr 12"),
        row("bm-2", "Charlotte's view on marriage", "Chapter 6", "p. 47", "Apr 18"),
        row("bm-3", "The Netherfield ball", "Chapter 11", "p. 89", "Yesterday"),
    )

    private fun setSheet(
        contents: List<TocEntry> = threeContents,
        bookmarks: List<BookmarkRowItem> = threeBookmarks,
        currentTocIndex: Int = 0,
        onJumpToc: (Int) -> Boolean = { true },
        onJumpBookmark: (BookmarkRecord) -> JumpResult = { JumpResult.Succeeded },
        onDismiss: () -> Unit = {},
        theme: ReaderTheme = ReaderTheme.Paper,
    ) {
        compose.setContent {
            TocBookmarksSheetContent(
                theme = theme,
                bookTitle = "Pride and Prejudice",
                entries = contents,
                currentTocIndex = currentTocIndex,
                bookmarks = bookmarks,
                onJumpToc = onJumpToc,
                onJumpBookmark = onJumpBookmark,
                onDismiss = onDismiss,
            )
        }
    }

    // ── tab bar + default tab ────────────────────────────────

    @Test fun bothTabsPresent_contentsSelectedByDefault() {
        setSheet()
        compose.onNodeWithTag("toc-tab-contents", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("toc-tab-bookmarks", useUnmergedTree = true).assertExists()
        // Contents tab is the default → the reused Contents rows render, no bookmark rows yet.
        compose.onAllNodes(isTocRow, useUnmergedTree = true).assertCountEquals(3)
        compose.onAllNodes(isBookmarkRow, useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun contentsTab_reusesTocContentsSheet() {
        // The Contents tab body IS #132's TocContentsSheet — its content tag + a chapter row prove it.
        setSheet()
        compose.onNodeWithTag("toc-sheet-content", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Chapter Two", useUnmergedTree = true).assertExists()
    }

    // ── tab switch ───────────────────────────────────────────

    @Test fun switchToBookmarksTab_showsBookmarkRows() {
        setSheet()
        compose.onNodeWithTag("toc-tab-bookmarks", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        compose.onAllNodes(isBookmarkRow, useUnmergedTree = true).assertCountEquals(3)
        // The italic serif preview + the `chapter · p.N · date` meta render.
        compose.onNodeWithText("It is a truth universally acknowledged…", useUnmergedTree = true).assertExists()
        // No Contents rows while the Bookmarks tab is active.
        compose.onAllNodes(isTocRow, useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun switchBackToContents_showsChaptersAgain() {
        setSheet()
        compose.onNodeWithTag("toc-tab-bookmarks", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("toc-tab-contents", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        compose.onAllNodes(isTocRow, useUnmergedTree = true).assertCountEquals(3)
        compose.onAllNodes(isBookmarkRow, useUnmergedTree = true).assertCountEquals(0)
    }

    // ── empty state ──────────────────────────────────────────

    @Test fun emptyBookmarks_showsEmptyState_noRows() {
        setSheet(bookmarks = emptyList())
        compose.onNodeWithTag("toc-tab-bookmarks", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("bookmarks-empty", useUnmergedTree = true).assertExists()
        compose.onAllNodes(isBookmarkRow, useUnmergedTree = true).assertCountEquals(0)
    }

    // ── tap-to-jump + dismiss-on-Succeeded ───────────────────

    @Test fun tapBookmarkRow_invokesOnJumpBookmarkWithRecord() {
        var jumped: BookmarkRecord? = null
        setSheet(onJumpBookmark = { jumped = it; JumpResult.Succeeded })
        compose.onNodeWithTag("toc-tab-bookmarks", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("bookmark-row-bm-2", useUnmergedTree = true).performClick()
        assertEquals("bm-2", jumped?.id)
    }

    @Test fun succeededJump_dismissesSheet() {
        var dismissed = false
        setSheet(onJumpBookmark = { JumpResult.Succeeded }, onDismiss = { dismissed = true })
        compose.onNodeWithTag("toc-tab-bookmarks", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("bookmark-row-bm-1", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        assertTrue("a Succeeded jump must dismiss the sheet", dismissed)
    }

    @Test fun failedJump_keepsSheetOpen_noErrorSurface() {
        var dismissed = false
        setSheet(onJumpBookmark = { JumpResult.Failed }, onDismiss = { dismissed = true })
        compose.onNodeWithTag("toc-tab-bookmarks", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("bookmark-row-bm-1", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        assertFalse("a Failed jump must NOT dismiss the sheet", dismissed)
        // The bookmark rows are still present, and no invented error surface was rendered.
        compose.onNodeWithTag("bookmark-row-bm-1", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithTag("bookmark-jump-error", useUnmergedTree = true).assertCountEquals(0)
    }

    // ── design gate: NO delete affordance (deferred) ─────────

    @Test fun noDeleteAffordance_onAnyBookmarkRow() {
        // Bookmark row DELETION is deferred to a follow-up WI (rule 51 — the delete surface is not
        // built in #135). No swipe/long-press/confirm delete control is rendered on any row.
        setSheet()
        compose.onNodeWithTag("toc-tab-bookmarks", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        compose.onAllNodesWithTag("bookmark-delete-bm-1", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("bookmark-delete-bm-2", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("bookmark-delete-bm-3", useUnmergedTree = true).assertCountEquals(0)
    }

    // ── Contents-tab jump still works (reuse is live, not decorative) ──

    @Test fun contentsTab_tapRow_invokesOnJumpToc() {
        var jumped: Int? = null
        setSheet(onJumpToc = { jumped = it; true })
        compose.onNodeWithTag("toc-row-2", useUnmergedTree = true).performClick()
        assertEquals(2, jumped)
    }

    // ── the JumpResult model ─────────────────────────────────

    @Test fun jumpResult_hasSucceededAndFailed() {
        assertEquals(JumpResult.Succeeded, JumpResult.Succeeded)
        assertEquals(JumpResult.Failed, JumpResult.Failed)
        assertFalse(JumpResult.Succeeded == JumpResult.Failed)
    }

    // Smoke: the ModalBottomSheet wrapper renders the two-tab content (merged tree, off the flaky
    // click-into-sheet path — the TocContentsSheet precedent).
    @Test fun modalBottomSheetWrapper_rendersTwoTabContent() {
        compose.setContent {
            TocBookmarksSheet(
                theme = ReaderTheme.Paper,
                bookTitle = "Pride and Prejudice",
                entries = threeContents,
                currentTocIndex = 0,
                bookmarks = threeBookmarks,
                onJumpToc = { true },
                onJumpBookmark = { JumpResult.Succeeded },
                onDismiss = {},
            )
        }
        compose.waitForIdle()
        compose.onNodeWithText("Pride and Prejudice").assertExists()
    }
}
