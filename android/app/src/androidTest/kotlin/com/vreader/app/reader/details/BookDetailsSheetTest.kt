package com.vreader.app.reader.details

import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #134 WI-4 — the Book Details sheet (`vreader-book-details.jsx` `BookDetailsSheet`, Android
 * stacked layout only) over WI-1's [BookDetailsUiModel]. Non-interactive detail surface: the depicted
 * metadata rows Android has a data source for, a copy-fingerprint mini-action (payload = the FULL
 * canonical key), and a Share action — with the design's ABSENCE invariants held (Design-gate #1): NO
 * cover art, NO "Tap to add cover" placeholder, NO Export action; a row omitted when its model value is
 * null/empty; Location is a read-only label with no mini-action. Tests exercise the directly-composable
 * [BookDetailsSheetContent] (the modal sheet renders in a separate window instrumented clicks reach
 * unreliably — the AnnotationsReviewSheetContent precedent).
 */
@RunWith(AndroidJUnit4::class)
class BookDetailsSheetTest {
    @get:Rule val compose = createComposeRule()

    private fun model(
        title: String = "The Left Hand of Darkness",
        author: String? = "Ursula K. Le Guin",
        tags: List<String> = listOf("Sci-Fi", "Favorites"),
        formatLabel: String = "EPUB",
        sizeLabel: String = "2.1 MB",
        pagesLabel: String? = null,
        fingerprintDisplay: String = "epub:8a4f2e91b7…9e1a2c1b",
        fingerprintFull: String = "epub:8a4f2e91b7c3d56f9e1a4b2c8a4f2e91b7c3d56f9e1a2c1b:2097152",
        locationLabel: String? = "Books/epub_a1b2c3",
    ) = BookDetailsUiModel(
        title = title,
        author = author,
        tags = tags,
        formatLabel = formatLabel,
        sizeLabel = sizeLabel,
        pagesLabel = pagesLabel,
        fingerprintDisplay = fingerprintDisplay,
        fingerprintFull = fingerprintFull,
        locationLabel = locationLabel,
    )

    @Test fun sheetContentRendersWithTestTag() {
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = model(),
                onCopyFingerprint = {},
                onShare = {},
            )
        }
        compose.onNodeWithTag("book-details-sheet-content", useUnmergedTree = true).assertExists()
    }

    @Test fun metaRowsRenderFromModel() {
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = model(pagesLabel = "312"),
                onCopyFingerprint = {},
                onShare = {},
            )
        }
        // Title + author block.
        compose.onNodeWithText("The Left Hand of Darkness", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Ursula K. Le Guin", useUnmergedTree = true).assertExists()
        // Tag chips.
        compose.onNodeWithText("Sci-Fi", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Favorites", useUnmergedTree = true).assertExists()
        // Meta rows present (by their stable per-label testTag).
        compose.onNodeWithTag("details-meta-format", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("details-meta-size", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("details-meta-pages", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("details-meta-fingerprint", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("details-meta-location", useUnmergedTree = true).assertExists()
        // The values are the model's.
        compose.onNodeWithText("EPUB", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("2.1 MB", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("312", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("epub:8a4f2e91b7…9e1a2c1b", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Books/epub_a1b2c3", useUnmergedTree = true).assertExists()
    }

    @Test fun copyFingerprintInvokesCallbackWithFullKey() {
        // The copy-button payload is the FULL canonical fingerprintKey, NOT the truncated display.
        var copied: String? = null
        val m = model()
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = m,
                onCopyFingerprint = { copied = it },
                onShare = {},
            )
        }
        compose.onNodeWithTag("details-copy-fingerprint", useUnmergedTree = true)
            .assertHasClickAction()
            .performClick()
        assertEquals(m.fingerprintFull, copied)
    }

    @Test fun shareInvokesOnShare() {
        var shared = false
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = model(),
                onCopyFingerprint = {},
                onShare = { shared = true },
            )
        }
        compose.onNodeWithTag("details-share", useUnmergedTree = true)
            .assertHasClickAction()
            .performClick()
        assertTrue(shared)
    }

    @Test fun longTitleWrapsWithoutCrash() {
        val longTitle =
            "The Strange Case of the Astonishingly Long Title and Its Even Longer Subtitle About Everything"
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = model(title = longTitle),
                onCopyFingerprint = {},
                onShare = {},
            )
        }
        compose.onNodeWithText(longTitle, useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("book-details-sheet-content", useUnmergedTree = true).assertExists()
    }

    @Test fun noAuthorLineWhenAuthorNull() {
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = model(author = null),
                onCopyFingerprint = {},
                onShare = {},
            )
        }
        // The author line is OMITTED (no dangling "· " separator / placeholder) when author is null.
        compose.onAllNodesWithTag("details-author", useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithText("The Left Hand of Darkness", useUnmergedTree = true).assertExists()
    }

    @Test fun noTagRowWhenTagsEmpty() {
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = model(tags = emptyList()),
                onCopyFingerprint = {},
                onShare = {},
            )
        }
        compose.onAllNodesWithTag("details-tags", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun noPagesRowWhenPagesLabelNull() {
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = model(pagesLabel = null),
                onCopyFingerprint = {},
                onShare = {},
            )
        }
        // Pages row absent (§page-count — non-PDF hosts have no page count).
        compose.onAllNodesWithTag("details-meta-pages", useUnmergedTree = true).assertCountEquals(0)
        // The other meta rows still render.
        compose.onNodeWithTag("details-meta-format", useUnmergedTree = true).assertExists()
    }

    @Test fun noLocationRowWhenLocationNull() {
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = model(locationLabel = null),
                onCopyFingerprint = {},
                onShare = {},
            )
        }
        compose.onAllNodesWithTag("details-meta-location", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun noCoverArtNorAddCoverPlaceholder() {
        // Design-gate #1 (rule 51): Android ships NO cover art and NO interactive "Tap to add cover"
        // placeholder in the details sheet — the title/author block leads.
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = model(),
                onCopyFingerprint = {},
                onShare = {},
            )
        }
        compose.onAllNodesWithTag("details-cover", useUnmergedTree = true).assertCountEquals(0)
        compose.onNodeWithText("Tap to add cover", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithText("Replace cover", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithText("Add cover…", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test fun noExportAction() {
        // No Android annotation-export subsystem — the Export action is never present (absence).
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = model(),
                onCopyFingerprint = {},
                onShare = {},
            )
        }
        compose.onNodeWithText("Export annotations…", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithText("Export annotations", useUnmergedTree = true).assertDoesNotExist()
        compose.onAllNodesWithTag("details-export", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun locationIsReadOnlyLabelWithNoMiniAction() {
        // The Location row is a plain read-only label (no reveal/download mini-action — §location).
        compose.setContent {
            BookDetailsSheetContent(
                theme = ReaderTheme.Paper,
                model = model(),
                onCopyFingerprint = {},
                onShare = {},
            )
        }
        compose.onNodeWithTag("details-meta-location", useUnmergedTree = true).assertExists()
        compose.onNodeWithText("Books/epub_a1b2c3", useUnmergedTree = true).assertExists()
        // No mini-action buttons on the Location row.
        compose.onAllNodesWithTag("details-location-reveal", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("details-location-download", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun rendersAcrossThemes() {
        // Pure function of the theme tokens — renders in every theme (light + dark) without crash.
        for (theme in ReaderTheme.values()) {
            compose.setContent {
                BookDetailsSheetContent(theme = theme, model = model(), onCopyFingerprint = {}, onShare = {})
            }
            compose.onNodeWithTag("book-details-sheet-content", useUnmergedTree = true).assertExists()
        }
    }

    @Test fun modelExposesFullFingerprintDistinctFromDisplay() {
        // The FULL canonical key (the copy payload) is distinct from the truncated display key
        // (§fingerprint). WI-1's model carries NO year/coverPath fields to render (§details-source
        // ALWAYS-absent invariant) — this test also documents that the default pagesLabel is null.
        val m = model()
        assertNull(m.pagesLabel)
        assertEquals("epub:8a4f2e91b7c3d56f9e1a4b2c8a4f2e91b7c3d56f9e1a2c1b:2097152", m.fingerprintFull)
        assertTrue(m.fingerprintFull != m.fingerprintDisplay)
    }
}
