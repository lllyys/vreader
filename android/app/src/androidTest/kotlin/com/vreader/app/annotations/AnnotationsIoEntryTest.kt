package com.vreader.app.annotations

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.EpubReaderSheets
import com.vreader.app.reader.EpubTopBand
import com.vreader.app.reader.ReaderChromeModel
import com.vreader.app.reader.chrome.ReaderBottomChrome
import com.vreader.app.reader.chrome.ReaderChromeScaffold
import com.vreader.app.reader.chrome.ReaderChromeState
import com.vreader.app.reader.chrome.ReaderSheet
import com.vreader.app.reader.details.BookDetailsSheetContent
import com.vreader.app.reader.details.BookDetailsUiModel
import com.vreader.app.reader.settings.ReaderTheme
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #165 WI-6 — the designed **Import annotations…** `ActionList` row + B1's merge-policy footnote
 * on the Book Details sheet (`vreader-annotation-import.jsx:317-325` rows, `:332-339` footnote, variant
 * `B1-paired`), threaded through BOTH production chrome hosts.
 *
 * Two things this suite exists to pin, beyond "the row renders":
 *
 *  1. **Reachability through the REAL hosts.** [ReaderChromeScaffold] (TXT/PDF/AZW3) and
 *     [EpubReaderSheets] (the EPUB three-ComposeView host) are composed for real and driven to their
 *     `ReaderSheet.Details` route — a host that accepted `onImportAnnotations` and then DISCARDED it
 *     would still render the row but never fire the callback. That is the #140 WI-6 defect shape
 *     (`Azw3ReaderActivity` swallowing a chrome callback while every stub-backed test stayed green).
 *  2. **The Export row's ABSENCE is load-bearing, not filler.** `details-export-annotations` is
 *     `BLOCKED: needs-design (#2085)`; the `assertDoesNotExist` below is the only mechanical guard that
 *     a stray export row added during WI-7 wiring goes RED instead of quietly shipping undesigned UI.
 *     It is always asserted in a test that ALSO proves the Import row present, so it can never pass by
 *     virtue of the sheet having failed to render. WI-8 flips this set in the same commit that adds the
 *     row — never as an `@Ignore`.
 */
@RunWith(AndroidJUnit4::class)
class AnnotationsIoEntryTest {
    @get:Rule val compose = createComposeRule()

    /** The verbatim design copy (`vreader-annotation-import.jsx:336`) — asserted, never paraphrased. */
    private val footnoteCopy =
        "Imports merge into this book by passage match; existing notes are not overwritten."

    private fun detailsModel() = BookDetailsUiModel(
        title = "Pride and Prejudice",
        author = "Jane Austen",
        tags = emptyList(),
        formatLabel = "EPUB",
        sizeLabel = "1.2 MB",
        pagesLabel = null,
        fingerprintDisplay = "epub:8a4f2e91b7…9e1a2c1b",
        fingerprintFull = "epub:${"a".repeat(64)}:1258291",
        locationLabel = "Books/epub_a1b2c3",
    )

    private val emptySnapshot = AnnotationsSnapshot(highlights = emptyList(), notes = emptyList())

    // ── The designed row itself, on the production sheet content ────────────────────────────────

    @Test fun importRowRendersInvokesCallback_andExportRowIsAbsent() {
        var imported = 0
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = detailsModel(),
                onCopyFingerprint = {},
                onShare = {},
                onImportAnnotations = { imported++ },
            )
        }
        // PRESENT: the Import row. Asserted in the SAME test as the absence below, so a sheet that
        // failed to render cannot make the negative assertion pass vacuously.
        compose.onNodeWithTag("details-import-annotations", useUnmergedTree = true)
            .assertExists()
            .assertHasClickAction()
            .performClick()
        assertEquals(1, imported)
        compose.onNodeWithText("Import annotations…", useUnmergedTree = true).assertExists()

        // ABSENT: the Export row — BLOCKED on needs-design #2085 (WI-8).
        compose.onNodeWithTag("details-export-annotations", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithText("Export annotations…", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test fun mergePolicyFootnoteRendersVerbatim() {
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = detailsModel(),
                onCopyFingerprint = {},
                onShare = {},
                onImportAnnotations = {},
            )
        }
        compose.onNodeWithTag("details-annotations-footnote", useUnmergedTree = true).assertExists()
        compose.onNodeWithText(footnoteCopy, useUnmergedTree = true).assertExists()
        // Still present alongside it — the footnote is not a substitute for the row.
        compose.onNodeWithTag("details-import-annotations", useUnmergedTree = true).assertExists()
    }

    @Test fun importRowHasNoSubLine() {
        // §3.3 A-2: the design's `sub="VReader JSON · Readwise · Apple Books"` is an ABSENCE — no
        // Readwise/Apple-Books importer is in scope and advertising one is a false affordance.
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = detailsModel(),
                onCopyFingerprint = {},
                onShare = {},
                onImportAnnotations = {},
            )
        }
        compose.onNodeWithTag("details-import-annotations", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("VReader JSON · Readwise · Apple Books", useUnmergedTree = true)
            .assertDoesNotExist()
        // Nor the Export row's sub-line (§3.3 A-1), which would imply an export affordance exists.
        compose.onNodeWithText("Markdown · JSON · VReader JSON", useUnmergedTree = true)
            .assertDoesNotExist()
    }

    @Test fun nullCallback_rendersNeitherRowNorFootnote_shareUnchanged() {
        // The capability gate (#134's nullable-callback pattern): a host that has not wired annotation
        // import shows exactly the Share-only card #134 shipped — no dead no-op row, no orphan footnote.
        var shared = false
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = detailsModel(),
                onCopyFingerprint = {},
                onShare = { shared = true },
                onImportAnnotations = null,
            )
        }
        compose.onAllNodesWithTag("details-import-annotations", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("details-annotations-footnote", useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithText(footnoteCopy, useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithTag("details-share", useUnmergedTree = true)
            .assertExists()
            .assertHasClickAction()
            .performClick()
        assertTrue(shared)
    }

    @Test fun shareRowStillWorksAlongsideImportRow() {
        var shared = false
        var imported = false
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = detailsModel(),
                onCopyFingerprint = {},
                onShare = { shared = true },
                onImportAnnotations = { imported = true },
            )
        }
        compose.onNodeWithTag("details-share", useUnmergedTree = true).performClick()
        assertTrue(shared)
        assertTrue("Share must not fire the import callback", !imported)
    }

    @Test fun rendersAcrossAllThemes() {
        // The Import row is accent-tinted (design `accent` BDRow), so it exercises a theme token the
        // Share row does not. setContent may be called only ONCE per test (#134 precedent) — render
        // every theme in one tree rather than looping setContent.
        compose.setContent {
            Column {
                for (theme in ReaderTheme.values()) {
                    BookDetailsSheetContent(
                        theme = theme,
                        model = detailsModel(),
                        onCopyFingerprint = {},
                        onShare = {},
                        onImportAnnotations = {},
                    )
                }
            }
        }
        compose.onAllNodesWithTag("details-import-annotations", useUnmergedTree = true)
            .assertCountEquals(ReaderTheme.values().size)
        compose.onAllNodesWithTag("details-export-annotations", useUnmergedTree = true)
            .assertCountEquals(0)
    }

    // ── Reachability through the REAL chrome hosts (the #140 WI-6 discarded-callback guard) ──────

    @Test fun scaffoldHost_detailsRoute_importRowFiresHostCallback() {
        var imported = 0
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Details))
        compose.setContent {
            ReaderChromeScaffold(
                theme = ReaderTheme.Paper,
                title = "Pride and Prejudice",
                chromeState = state,
                onBack = {},
                tocEntries = emptyList(),
                currentTocIndex = 0,
                annotations = emptySnapshot,
                onJumpToc = { true },
                onJumpToAnnotation = null,
                onShareAnnotations = {},
                bookDetails = detailsModel(),
                onImportAnnotations = { imported++ },
                bottomChrome = { onOpenContents, onOpenNotes ->
                    ReaderBottomChrome(
                        ReaderTheme.Paper, progress = 0f, displayPage = 1, totalPages = 10,
                        onScrub = {}, onOpenDisplay = {},
                        onOpenContents = onOpenContents, onOpenNotes = onOpenNotes,
                    )
                },
                body = { Box(Modifier.fillMaxSize().testTag("reader-body")) },
            )
        }
        compose.onNodeWithTag("book-details-sheet-content", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("details-annotations-footnote", useUnmergedTree = true).assertExists()
        // The click must reach the HOST's callback — a scaffold that accepted the parameter and dropped
        // it on the floor renders an identical row and fails right here.
        compose.onNodeWithTag("details-import-annotations", useUnmergedTree = true)
            .assertHasClickAction()
            .performClick()
        assertEquals(1, imported)
        compose.onNodeWithTag("details-export-annotations", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test fun scaffoldHost_withoutImportCallback_showsNoImportRow() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Details))
        compose.setContent {
            ReaderChromeScaffold(
                theme = ReaderTheme.Paper,
                title = "Pride and Prejudice",
                chromeState = state,
                onBack = {},
                tocEntries = emptyList(),
                currentTocIndex = 0,
                annotations = emptySnapshot,
                onJumpToc = { true },
                onJumpToAnnotation = null,
                onShareAnnotations = {},
                bookDetails = detailsModel(),
                bottomChrome = { onOpenContents, onOpenNotes ->
                    ReaderBottomChrome(
                        ReaderTheme.Paper, progress = 0f, displayPage = 1, totalPages = 10,
                        onScrub = {}, onOpenDisplay = {},
                        onOpenContents = onOpenContents, onOpenNotes = onOpenNotes,
                    )
                },
                body = { Box(Modifier.fillMaxSize().testTag("reader-body")) },
            )
        }
        compose.onNodeWithTag("book-details-sheet-content", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithTag("details-import-annotations", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("details-annotations-footnote", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun epubHost_detailsRoute_importRowFiresHostCallback() {
        var imported = 0
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Details))
        compose.setContent {
            EpubReaderSheets(
                model = MutableStateFlow(ReaderChromeModel(title = "Pride and Prejudice")),
                theme = ReaderTheme.Paper,
                chromeState = state,
                onJumpToc = { true },
                onShareAnnotations = {},
                bookDetails = detailsModel(),
                onImportAnnotations = { imported++ },
            )
        }
        compose.onNodeWithTag("book-details-sheet-content", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("details-annotations-footnote", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("details-import-annotations", useUnmergedTree = true)
            .assertHasClickAction()
            .performClick()
        assertEquals(1, imported)
        compose.onNodeWithTag("details-export-annotations", useUnmergedTree = true).assertDoesNotExist()
    }

    // ── The FULL production navigation, not a pre-opened sheet (Gate-4 round-1 Low) ──────────────
    //
    // The two tests above start with `sheet = ReaderSheet.Details` already set, which proves the row is
    // wired but assumes the More → Details transition works. These two start from `ReaderSheet.None` and
    // walk the real chain a user walks — top-bar `⋯` More → *Details* → **Import annotations…** — so a
    // broken More-menu transition cannot hide behind a pre-opened sheet.

    @Test fun scaffoldHost_fullMoreToDetailsToImport_firesHostCallback() {
        var imported = 0
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        compose.setContent {
            ReaderChromeScaffold(
                theme = ReaderTheme.Paper,
                title = "Pride and Prejudice",
                chromeState = state,
                onBack = {},
                tocEntries = emptyList(),
                currentTocIndex = 0,
                annotations = emptySnapshot,
                onJumpToc = { true },
                onJumpToAnnotation = null,
                onShareAnnotations = {},
                bookDetails = detailsModel(),
                onImportAnnotations = { imported++ },
                bottomChrome = { onOpenContents, onOpenNotes ->
                    ReaderBottomChrome(
                        ReaderTheme.Paper, progress = 0f, displayPage = 1, totalPages = 10,
                        onScrub = {}, onOpenDisplay = {},
                        onOpenContents = onOpenContents, onOpenNotes = onOpenNotes,
                    )
                },
                body = { Box(Modifier.fillMaxSize().testTag("reader-body")) },
            )
        }
        compose.onNodeWithTag("chrome-more", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("more-row-details", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("details-import-annotations", useUnmergedTree = true).performClick()
        assertEquals(1, imported)
        compose.onNodeWithTag("details-export-annotations", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test fun epubHost_fullMoreToDetailsToImport_firesHostCallback() {
        // The EPUB host splits the More button ([EpubTopBand]) and the sheets ([EpubReaderSheets]) into
        // two separate ComposeViews over the Readium fragment; they coordinate ONLY through the shared
        // hoisted [chromeState]. Composing both in one tree is what exercises that coordination.
        var imported = 0
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None))
        val model = MutableStateFlow(ReaderChromeModel(title = "Pride and Prejudice"))
        compose.setContent {
            Column {
                EpubTopBand(
                    model = model,
                    theme = ReaderTheme.Paper,
                    onBack = {},
                    chromeState = state,
                    bookDetails = detailsModel(),
                    onShareBook = {},
                )
                EpubReaderSheets(
                    model = model,
                    theme = ReaderTheme.Paper,
                    chromeState = state,
                    onJumpToc = { true },
                    onShareAnnotations = {},
                    bookDetails = detailsModel(),
                    onImportAnnotations = { imported++ },
                )
            }
        }
        compose.onNodeWithTag("chrome-more", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("more-row-details", useUnmergedTree = true).performClick()
        compose.onNodeWithTag("details-import-annotations", useUnmergedTree = true).performClick()
        assertEquals(1, imported)
        compose.onNodeWithTag("details-export-annotations", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test fun epubHost_withoutImportCallback_showsNoImportRow() {
        val state = mutableStateOf(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Details))
        compose.setContent {
            EpubReaderSheets(
                model = MutableStateFlow(ReaderChromeModel(title = "Pride and Prejudice")),
                theme = ReaderTheme.Paper,
                chromeState = state,
                onJumpToc = { true },
                onShareAnnotations = {},
                bookDetails = detailsModel(),
            )
        }
        compose.onNodeWithTag("book-details-sheet-content", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithTag("details-import-annotations", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("details-annotations-footnote", useUnmergedTree = true).assertCountEquals(0)
    }
}
