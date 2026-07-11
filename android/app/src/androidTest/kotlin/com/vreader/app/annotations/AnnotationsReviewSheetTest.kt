package com.vreader.app.annotations

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertHasNoClickAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator

/**
 * Feature #132 WI-4 — the `AnnotationsReviewSheet` (vreader-android-annotations.jsx `AnnotationsSheet`,
 * the "Notes" surface): a `ModalBottomSheet` over WI-6b's [AnnotationsSnapshot] with All/Highlights/Notes
 * filter chips (NO Bookmarks chip — that is #135), `HighlightCard` + `StandaloneNoteCard` (NO
 * `BookmarkCard` — #135), an empty state, a sheet-level trailing Share (`onShareAll`), and a
 * capability-based nullable `onJumpToAnnotation` tap-to-jump on the card body.
 *
 * Tests target [AnnotationsReviewSheetContent] directly (the `AssignSheetContent`/`TocContentsSheetContent`
 * precedent — a `ModalBottomSheet`'s content renders in a separate window instrumented clicks reach
 * unreliably on a loaded host; the content composable is the testable seam).
 */
@RunWith(AndroidJUnit4::class)
class AnnotationsReviewSheetTest {
    @get:Rule val compose = createComposeRule()

    private val isAnnotCard = SemanticsMatcher("testTag starts with annot-card-") { node ->
        node.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("annot-card-") == true
    }

    private fun locator(offset: Int): Locator =
        Locator(contentSHA256 = "a".repeat(64), fileByteCount = 1024, format = "txt", charOffsetUTF16 = offset)

    private fun highlight(id: String, text: String, note: String? = null, offset: Int = 0): HighlightRecord =
        HighlightRecord(
            id = id, bookKey = "book-1", color = AnnotationColor.yellow,
            selectedText = text, note = note, locator = locator(offset), anchor = null,
            createdAt = 1_000L, updatedAt = 1_000L,
        )

    private fun note(id: String, content: String, offset: Int = 0): NoteRecord =
        NoteRecord(
            id = id, bookKey = "book-1", content = content, locator = locator(offset), anchor = null,
            createdAt = 2_000L, updatedAt = 2_000L,
        )

    private val snapshot = AnnotationsSnapshot(
        highlights = listOf(
            highlight("hl-1", "She was a woman of mean understanding.", note = "Austen's irony.", offset = 10),
            highlight("hl-2", "It is a truth universally acknowledged.", offset = 20),
        ),
        notes = listOf(
            note("nt-1", "Track how often weather forces the plot.", offset = 30),
        ),
    )

    private fun setSheet(
        snap: AnnotationsSnapshot = snapshot,
        theme: ReaderTheme = ReaderTheme.Paper,
        onShareAll: () -> Unit = {},
        onJumpToAnnotation: ((AnnotationItem) -> Unit)? = {},
    ) {
        compose.setContent {
            AnnotationsReviewSheetContent(
                theme = theme,
                snapshot = snap,
                onShareAll = onShareAll,
                onJumpToAnnotation = onJumpToAnnotation,
            )
        }
    }

    // ── filters ──────────────────────────────────────────────

    @Test fun allFilter_showsHighlightsAndNotes() {
        setSheet()
        // Default filter is All → 2 highlights + 1 note = 3 cards.
        compose.onAllNodes(isAnnotCard, useUnmergedTree = true).assertCountEquals(3)
        compose.onNodeWithText("She was a woman of mean understanding.", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Track how often weather forces the plot.", useUnmergedTree = true).assertExists()
    }

    @Test fun highlightsFilter_showsOnlyHighlightCards() {
        setSheet()
        compose.onNodeWithTag("annot-filter-highlights", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        // 2 highlight cards, no note card.
        compose.onAllNodes(isAnnotCard, useUnmergedTree = true).assertCountEquals(2)
        compose.onNodeWithText("She was a woman of mean understanding.", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithTag("annot-card-nt-1", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun notesFilter_showsOnlyNoteCards() {
        setSheet()
        compose.onNodeWithTag("annot-filter-notes", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        // 1 standalone-note card, no highlight card.
        compose.onAllNodes(isAnnotCard, useUnmergedTree = true).assertCountEquals(1)
        compose.onNodeWithTag("annot-card-nt-1", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithTag("annot-card-hl-1", useUnmergedTree = true).assertCountEquals(0)
    }

    // ── empty states ─────────────────────────────────────────

    @Test fun emptySnapshot_showsEmptyState_noCards() {
        setSheet(snap = AnnotationsSnapshot(highlights = emptyList(), notes = emptyList()))
        compose.onNodeWithTag("annot-empty", useUnmergedTree = true).assertExists()
        compose.onAllNodes(isAnnotCard, useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun notesFilterWithNoNotes_showsEmptyState() {
        // A snapshot with only highlights → the Notes filter yields nothing → empty state.
        setSheet(snap = AnnotationsSnapshot(highlights = listOf(highlight("hl-9", "only a highlight")), notes = emptyList()))
        compose.onNodeWithTag("annot-filter-notes", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        compose.onNodeWithTag("annot-empty", useUnmergedTree = true).assertExists()
        compose.onAllNodes(isAnnotCard, useUnmergedTree = true).assertCountEquals(0)
    }

    // ── sheet-level Share ────────────────────────────────────

    @Test fun sheetShare_invokesOnShareAll() {
        var shared = false
        setSheet(onShareAll = { shared = true })
        compose.onNodeWithTag("annot-share", useUnmergedTree = true).performClick()
        assertEquals(true, shared)
    }

    // ── tap-to-jump (capability gate) ────────────────────────

    @Test fun nonNullJump_cardTapInvokesJumpWithItem() {
        var jumped: AnnotationItem? = null
        setSheet(onJumpToAnnotation = { jumped = it })
        compose.onNodeWithTag("annot-card-hl-2", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        val item = jumped
        assertEquals("hl-2", (item as? AnnotationItem.Highlight)?.record?.id)
    }

    @Test fun nonNullJump_cardsAreClickable() {
        setSheet(onJumpToAnnotation = {})
        compose.onNodeWithTag("annot-card-hl-1", useUnmergedTree = true).assertHasClickAction()
        compose.onNodeWithTag("annot-card-nt-1", useUnmergedTree = true).assertHasClickAction()
    }

    @Test fun nullJump_cardsAreNotClickable() {
        // Capability gate: EPUB/AZW3 stand-in — null onJumpToAnnotation → the card is review-only,
        // NOT a silent clickable no-op.
        setSheet(onJumpToAnnotation = null)
        compose.onNodeWithTag("annot-card-hl-1", useUnmergedTree = true).assertHasNoClickAction()
        compose.onNodeWithTag("annot-card-nt-1", useUnmergedTree = true).assertHasNoClickAction()
    }

    // ── design gates (absence assertions) ────────────────────

    @Test fun noBookmarksFilterChip() {
        // #135, not #132 — the Bookmarks chip must NOT exist.
        setSheet()
        compose.onAllNodesWithTag("annot-filter-bookmarks", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun noPerCardCopyOrShareButtons() {
        // The Android review cards depict NO per-card Copy/Share (those live on the SelectionPopover).
        setSheet()
        compose.onAllNodesWithTag("annot-card-copy-hl-1", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("annot-card-share-hl-1", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("annot-card-copy-nt-1", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("annot-card-share-nt-1", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun noPerCardMoreMenu() {
        // The `⋯` Edit/Delete menu is the iOS notes-delete.jsx surface — NOT depicted on Android.
        setSheet()
        compose.onAllNodesWithTag("annot-more-hl-1", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("annot-more-nt-1", useUnmergedTree = true).assertCountEquals(0)
    }

    // ── AnnotationItem model ─────────────────────────────────

    @Test fun annotationItem_carriesLocatorAndId() {
        val hlItem = AnnotationItem.Highlight(highlight("hl-x", "quote", offset = 55))
        assertEquals("hl-x", hlItem.id)
        assertEquals(55, hlItem.locator.charOffsetUTF16)
        assertEquals("quote", hlItem.displayText)

        val ntItem = AnnotationItem.Note(note("nt-x", "body text", offset = 66))
        assertEquals("nt-x", ntItem.id)
        assertEquals(66, ntItem.locator.charOffsetUTF16)
        assertEquals("body text", ntItem.displayText)
    }

    // Smoke: the `ModalBottomSheet` wrapper renders its content (asserting via the merged tree keeps
    // this off the flaky click-into-sheet path — the TocContentsSheet precedent).
    @Test fun modalBottomSheetWrapper_rendersContent() {
        compose.setContent {
            AnnotationsReviewSheet(
                theme = ReaderTheme.Paper,
                snapshot = snapshot,
                onShareAll = {},
                onJumpToAnnotation = {},
                onDismiss = {},
            )
        }
        compose.waitForIdle()
        compose.onNodeWithText("She was a woman of mean understanding.").assertExists()
    }
}
