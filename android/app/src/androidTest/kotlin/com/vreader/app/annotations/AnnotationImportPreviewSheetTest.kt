package com.vreader.app.annotations

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator
import vreader.contracts.backup.BackupAnnotationsEnvelope
import vreader.contracts.backup.BackupBookmark
import vreader.contracts.backup.BackupHighlight
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupNote
import vreader.contracts.backup.BackupSchema
import java.io.ByteArrayInputStream
import java.time.Instant

/**
 * Feature #165 WI-5 — the designed annotations-import preview/confirm sheet
 * (`vreader-annotation-import.jsx:425-558` `ImportPreviewSheet`): file header + source badge
 * (`:449-475`), `Highlights` / `Notes` / `Skipped` count chips (`:488-492`), the
 * "Preview · first three" sample list (`:495-530`), the merge-policy line (`:531-533`), the
 * error blob (`:477-484`) and the `Cancel` / `Import N items` pair whose primary is **disabled**
 * when nothing will import (`:548-554`).
 *
 * Every preview under test is produced by the REAL [AnnotationsImportReader] from real bytes, so
 * the numbers asserted here are the ones WI-3 collapsed into `ImportPreview.envelope` — not
 * numbers this test invented. That is the point: the sheet must render the envelope's count, and
 * the fixtures are deliberately shaped so that any plausible re-derivation (raw file rows, the
 * highlight count alone, the skipped count, the sample size) yields a DIFFERENT number.
 *
 * Tests target [AnnotationImportPreviewSheetContent] directly (the
 * `AnnotationsReviewSheetContent` / `TocContentsSheetContent` precedent — a `ModalBottomSheet`'s
 * content renders in a separate window instrumented clicks reach unreliably). `setContent` is
 * called AT MOST ONCE per test method (#134 precedent: a second call throws
 * `IllegalStateException`, and only the connected run catches it).
 */
@RunWith(AndroidJUnit4::class)
class AnnotationImportPreviewSheetTest {
    @get:Rule val compose = createComposeRule()

    private val bookKey = "epub:" + "a".repeat(64) + ":1000"
    private val t0: Instant = Instant.parse("2026-08-05T10:00:00Z")

    private fun uuid(n: Int) = "00000000-0000-4000-8000-" + n.toString().padStart(12, '0')

    private fun locatorJson(offset: Int): String = BackupJson.encode(
        Locator(
            contentSHA256 = "a".repeat(64),
            fileByteCount = 1000,
            format = "epub",
            charOffsetUTF16 = offset,
        ),
    )

    private fun highlight(id: String, offset: Int, text: String = "quote $offset") = BackupHighlight(
        highlightId = id,
        bookFingerprintKey = bookKey,
        locatorJSON = locatorJson(offset),
        selectedText = text,
        color = "yellow",
        note = null,
        createdAt = t0,
        updatedAt = t0,
    )

    private fun note(id: String, offset: Int, content: String = "note $offset") = BackupNote(
        annotationId = id,
        bookFingerprintKey = bookKey,
        locatorJSON = locatorJson(offset),
        content = content,
        createdAt = t0,
        updatedAt = t0,
    )

    private fun bookmark(id: String, offset: Int, title: String? = "mark $offset") = BackupBookmark(
        bookmarkId = id,
        bookFingerprintKey = bookKey,
        locatorJSON = locatorJson(offset),
        title = title,
        createdAt = t0,
        updatedAt = t0,
    )

    private fun envelopeJson(
        highlights: List<BackupHighlight> = emptyList(),
        notes: List<BackupNote> = emptyList(),
        bookmarks: List<BackupBookmark> = emptyList(),
    ): String = BackupJson.encode(
        BackupAnnotationsEnvelope(
            schemaVersion = BackupSchema.CURRENT_SCHEMA_VERSION,
            highlights = highlights,
            bookmarks = bookmarks,
            notes = notes,
        ),
    )

    private fun previewOf(
        json: String,
        fileName: String = "pride-and-prejudice.annotations.json",
        bookTitle: String = "Pride and Prejudice",
        existing: ExistingAnnotationState = ExistingAnnotationState.EMPTY,
    ): ImportPreview {
        val result = AnnotationsImportReader.parse(
            ByteArrayInputStream(json.toByteArray(Charsets.UTF_8)),
            fileName,
            bookKey,
            bookTitle,
            existing,
        )
        assertTrue("fixture must parse: $result", result is ImportParseResult.Ok)
        return (result as ImportParseResult.Ok).preview
    }

    /**
     * 5 good highlights + 7 rows that fail the UUID gate, 3 notes, 2 bookmarks.
     *
     * Raw rows 17 · highlights 5 · notes 3 · bookmarks 2 · skipped 7 · sample 3 · importable 10.
     * Every one of those numbers is distinct, so an implementation that renders any of them in the
     * primary button's place is caught by name.
     */
    private fun mixedPreview(): ImportPreview {
        val good = (1..5).map { highlight(uuid(it), offset = it * 10, text = "highlight $it") }
        val badIds = (1..7).map { highlight("not-a-uuid-$it", offset = 500 + it) }
        return previewOf(
            envelopeJson(
                highlights = good + badIds,
                notes = (1..3).map { note(uuid(100 + it), offset = 1000 + it) },
                bookmarks = (1..2).map { bookmark(uuid(200 + it), offset = 2000 + it) },
            ),
        )
    }

    /** 12 raw rows, 3 of which collide intra-file (F-1 duplicate ids) → 9 importable. */
    private fun duplicatePreview(): ImportPreview = previewOf(
        envelopeJson(
            highlights = listOf(
                highlight(uuid(1), 10), highlight(uuid(2), 20),
                highlight(uuid(3), 30), highlight(uuid(4), 40),
                highlight(uuid(1), 50), highlight(uuid(2), 60),
            ),
            notes = listOf(
                note(uuid(11), 110), note(uuid(12), 120),
                note(uuid(13), 130), note(uuid(11), 140),
            ),
            bookmarks = listOf(bookmark(uuid(21), 210), bookmark(uuid(22), 220)),
        ),
    )

    private fun setSheet(
        state: AnnotationImportSheetState,
        theme: ReaderTheme = ReaderTheme.Paper,
        onCancel: () -> Unit = {},
        onConfirm: (ImportPreview) -> Unit = {},
    ) {
        compose.setContent {
            AnnotationImportPreviewSheetContent(
                theme = theme,
                state = state,
                onCancel = onCancel,
                onConfirm = onConfirm,
            )
        }
    }

    // ── the counts come from the envelope, not from a re-derivation ──────────────────────

    @Test fun populatedPreview_chipsShowTheEnvelopeCounts() {
        val preview = mixedPreview()
        // Guard the fixture itself, so a reader change that shifts these numbers fails HERE and
        // not as a mysterious UI assertion.
        assertEquals(5, preview.highlights)
        assertEquals(3, preview.notes)
        assertEquals(2, preview.bookmarks)
        assertEquals(7, preview.skipped)
        assertEquals(10, preview.importable)

        setSheet(AnnotationImportSheetState.Ready(preview))

        compose.onNodeWithTag("annot-import-chip-highlights-value", useUnmergedTree = true)
            .assertTextEquals("5")
        compose.onNodeWithTag("annot-import-chip-notes-value", useUnmergedTree = true)
            .assertTextEquals("3")
        compose.onNodeWithTag("annot-import-chip-skipped-value", useUnmergedTree = true)
            .assertTextEquals("7")
    }

    @Test fun populatedPreview_confirmReadsImportableNotAnyOtherCount() {
        setSheet(AnnotationImportSheetState.Ready(mixedPreview()))

        compose.onNodeWithText("Import 10 items", useUnmergedTree = true).assertExists()
        // The discriminating half: every number a re-derivation could plausibly reach.
        listOf(
            "Import 17 items", // raw file rows
            "Import 5 items", // highlights only
            "Import 8 items", // highlights + notes (bookmarks forgotten)
            "Import 7 items", // skipped
            "Import 3 items", // the sample size
            "Import 0 items", // the disabled label leaking into a populated preview
        ).forEach { wrong ->
            compose.onAllNodesWithText(wrong, useUnmergedTree = true).assertCountEquals(0)
        }
    }

    @Test fun intraFileDuplicates_confirmReadsTheCollapsedCount() {
        val preview = duplicatePreview()
        assertEquals(9, preview.importable)
        assertEquals(3, preview.skipped)

        setSheet(AnnotationImportSheetState.Ready(preview))

        compose.onNodeWithText("Import 9 items", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithText("Import 12 items", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun confirm_handsBackTheSamePreviewObject() {
        // The caller applies the preview it was handed, so it cannot rebuild a different envelope
        // from the numbers on screen (§6.4 "the number the user approves must be the number they
        // get").
        val preview = mixedPreview()
        var confirmed: ImportPreview? = null
        setSheet(AnnotationImportSheetState.Ready(preview), onConfirm = { confirmed = it })

        compose.onNodeWithTag("annot-import-confirm", useUnmergedTree = true).performClick()
        compose.waitForIdle()

        assertSame(preview, confirmed)
    }

    // ── the disabled primary (C-8) ───────────────────────────────────────────────────────

    @Test fun everythingAlreadyPresent_confirmIsDisabledAndInert() {
        // Every row's id is already in the database → importable 0, skipped 5.
        val ids = (1..5).map { uuid(it) }
        val preview = previewOf(
            envelopeJson(highlights = ids.mapIndexed { i, id -> highlight(id, offset = (i + 1) * 10) }),
            existing = ExistingAnnotationState(
                ids = ids.toSet(),
                highlightProfileKeys = emptySet(),
                bookmarkProfileKeys = emptySet(),
            ),
        )
        assertEquals(0, preview.importable)
        assertEquals(5, preview.skipped)

        var confirmed: ImportPreview? = null
        setSheet(AnnotationImportSheetState.Ready(preview), onConfirm = { confirmed = it })

        compose.onNodeWithText("Import 0 items", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("annot-import-confirm").assertIsNotEnabled()
        compose.onNodeWithTag("annot-import-confirm").performClick()
        compose.waitForIdle()
        assertNull("a disabled primary must not commit a no-op", confirmed)
        // The Skipped chip is what explains the zero — it stays on screen.
        compose.onNodeWithTag("annot-import-chip-skipped-value", useUnmergedTree = true)
            .assertTextEquals("5")
    }

    @Test fun emptyEnvelope_confirmIsDisabledAndTheEmptySampleSectionIsOmitted() {
        val preview = previewOf(envelopeJson())
        assertEquals(0, preview.importable)
        assertEquals(0, preview.sample.size)
        setSheet(AnnotationImportSheetState.Ready(preview))

        compose.onNodeWithText("Import 0 items", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("annot-import-confirm").assertIsNotEnabled()
        // Recorded absence (needs-design #2099): no "PREVIEW · FIRST THREE" heading over an empty
        // card. Pinned so the decision is visible rather than incidental.
        compose.onAllNodesWithTag("annot-import-sample-label", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("annot-import-sample", useUnmergedTree = true).assertCountEquals(0)
        // The chips and the merge line DO stay — they are what explains the zero.
        compose.onNodeWithTag("annot-import-chip-skipped-value", useUnmergedTree = true).assertTextEquals("0")
        compose.onNodeWithTag("annot-import-merge", useUnmergedTree = true).assertExists()
    }

    @Test fun populatedPreview_confirmIsEnabled() {
        setSheet(AnnotationImportSheetState.Ready(mixedPreview()))
        compose.onNodeWithTag("annot-import-confirm").assertIsEnabled()
    }

    // ── the failure state, across the WHOLE taxonomy ─────────────────────────────────────

    @Test fun everyFailure_showsItsShippedMessageAndADisabledPrimary() {
        // ONE setContent; the state is mutated in place so all ten enum values are exercised
        // without a second `setContent` (#134: a second call throws IllegalStateException).
        var state by mutableStateOf<AnnotationImportSheetState>(
            AnnotationImportSheetState.Failed("annotations.json", ImportFailure.Empty),
        )
        var confirmed: ImportPreview? = null
        compose.setContent {
            AnnotationImportPreviewSheetContent(
                theme = ReaderTheme.Paper,
                state = state,
                onCancel = {},
                onConfirm = { confirmed = it },
            )
        }

        ImportFailure.entries.forEach { reason ->
            compose.runOnUiThread { state = AnnotationImportSheetState.Failed("annotations.json", reason) }
            compose.waitForIdle()
            compose.onNodeWithTag("annot-import-error", useUnmergedTree = true).assertIsDisplayed()
            // Assert what the user actually SEES: four of the ten deliberately share the generic
            // shipped copy (AnnotationImportModels' header), so asserting distinct text per case
            // would assert a distinction that does not exist.
            compose.onNodeWithText(reason.userMessage, useUnmergedTree = true).assertExists()
            compose.onNodeWithText("Import 0 items", useUnmergedTree = true).assertExists()
            compose.onNodeWithTag("annot-import-confirm").assertIsNotEnabled()
        }
        compose.onNodeWithTag("annot-import-confirm").performClick()
        compose.waitForIdle()
        assertNull(confirmed)
    }

    @Test fun failure_hidesTheChipsAndTheSampleAndTheMergeLine() {
        // The design's error branch REPLACES the chips + sample + merge line (`:477-485`).
        setSheet(AnnotationImportSheetState.Failed("annotations.json", ImportFailure.NotJson))

        compose.onAllNodesWithTag("annot-import-chip-highlights", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("annot-import-chip-notes", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("annot-import-chip-skipped", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("annot-import-sample", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithTag("annot-import-merge", useUnmergedTree = true).assertCountEquals(0)
        // The file header and BOTH actions survive — they sit outside the artboard's branch.
        compose.onNodeWithText("annotations.json", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("annot-import-cancel").assertIsDisplayed()
        compose.onNodeWithTag("annot-import-confirm").assertIsDisplayed()
    }

    @Test fun failureState_sanitizesAProviderSuppliedFileName() {
        // A `Failed` state is built by the I/O layer from a name the reader may never have seen, so
        // the sheet sanitizes at the pixel. Traversal + a C0 control + a bidi override, all built
        // from code points so no raw control byte can end up in this source file.
        val hostile = "../../etc/anno" + 0x0000.toChar() + "tations" + 0x202E.toChar() + ".json"
        setSheet(AnnotationImportSheetState.Failed(hostile, ImportFailure.Unreadable))

        compose.onNodeWithTag("annot-import-filename", useUnmergedTree = true)
            .assertTextEquals("annotations.json")
        compose.onAllNodesWithText(hostile, useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun failureState_survivesAnAllStrippedFileName() {
        // Nothing usable left → the shared sanitizer's FALLBACK_NAME, not a blank header.
        setSheet(AnnotationImportSheetState.Failed(0x202E.toChar().toString(), ImportFailure.Busy))
        compose.onNodeWithTag("annot-import-filename", useUnmergedTree = true)
            .assertTextEquals("Untitled")
    }

    @Test fun populated_hasNoErrorBlob() {
        setSheet(AnnotationImportSheetState.Ready(mixedPreview()))
        compose.onAllNodesWithTag("annot-import-error", useUnmergedTree = true).assertCountEquals(0)
    }

    // ── Cancel ──────────────────────────────────────────────────────────────────────────

    @Test fun cancel_invokesOnCancelAndNeverConfirms() {
        var cancelled = false
        var confirmed: ImportPreview? = null
        setSheet(
            AnnotationImportSheetState.Ready(mixedPreview()),
            onCancel = { cancelled = true },
            onConfirm = { confirmed = it },
        )

        compose.onNodeWithTag("annot-import-cancel", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        assertEquals(true, cancelled)
        assertNull(confirmed)
    }

    @Test fun cancel_isPresentAndEnabledOnTheFailureState() {
        var cancelled = false
        setSheet(
            AnnotationImportSheetState.Failed("annotations.json", ImportFailure.Unreadable),
            onCancel = { cancelled = true },
        )
        compose.onNodeWithTag("annot-import-cancel").assertIsEnabled()
        compose.onNodeWithTag("annot-import-cancel", useUnmergedTree = true).performClick()
        compose.waitForIdle()
        assertEquals(true, cancelled)
    }

    // ── the depicted supporting elements ────────────────────────────────────────────────

    @Test fun sampleList_showsAtMostThreeRows() {
        val preview = mixedPreview()
        assertEquals(3, preview.sample.size)
        setSheet(AnnotationImportSheetState.Ready(preview))

        compose.onNodeWithTag("annot-import-sample", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithTag("annot-import-sample-row", useUnmergedTree = true).assertCountEquals(3)
        compose.onNodeWithText("PREVIEW " + "·" + " FIRST THREE", useUnmergedTree = true).assertExists()
        // The 4th and 5th highlights exist in the envelope but are NOT in the sample.
        compose.onAllNodesWithText("\"highlight 4\"", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun mergePolicyLine_namesTheBookAndTheNonOverwriteRule() {
        setSheet(AnnotationImportSheetState.Ready(mixedPreview()))
        compose.onNodeWithText(
            "Imports merge into Pride and Prejudice by passage match. " +
                "Existing notes are not overwritten.",
            useUnmergedTree = true,
        ).assertExists()
    }

    @Test fun header_showsTheSanitizedFileNameNotTheRawProviderString() {
        // §8.4 — the display name is provider-controlled. `AnnotationsImportReader.parse` runs it
        // through `IncomingBookResolver.sanitizeDisplayName`, so the sheet can only ever render
        // the leaf.
        val preview = previewOf(
            envelopeJson(highlights = listOf(highlight(uuid(1), 10))),
            fileName = "../../etc/annotations.json",
        )
        assertEquals("annotations.json", preview.fileName)
        setSheet(AnnotationImportSheetState.Ready(preview))

        compose.onNodeWithText("annotations.json", useUnmergedTree = true).assertExists()
        compose.onAllNodesWithText("../../etc/annotations.json", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun cjkPayloadRendersIntact() {
        val quote = "黑暗血时代的一段摘录"
        val title = "道诡异仙"
        val preview = previewOf(
            envelopeJson(highlights = listOf(highlight(uuid(1), 10, text = quote))),
            fileName = title + ".annotations.json",
            bookTitle = title,
        )
        setSheet(AnnotationImportSheetState.Ready(preview))

        compose.onNodeWithText("\"" + quote + "\"", useUnmergedTree = true).assertExists()
        compose.onNodeWithText(title + ".annotations.json", useUnmergedTree = true).assertExists()
        compose.onNodeWithText(
            "Imports merge into " + title + " by passage match. Existing notes are not overwritten.",
            useUnmergedTree = true,
        ).assertExists()
    }

    @Test fun theDesignedJsonGlyphActuallyDraws() {
        // The header glyph is the artboard's own `IconFileJson` path data stroked onto a Canvas.
        // A typo in the path string, a bad viewport scale, or a zero-size Canvas would all draw
        // NOTHING and every other assertion in this file would still pass — so assert pixels: a
        // glyph that drew nothing leaves the capture a single flat colour (the tinted badge).
        setSheet(AnnotationImportSheetState.Ready(mixedPreview()))

        val pixels = compose.onNodeWithTag("annot-import-file-icon", useUnmergedTree = true)
            .captureToImage()
            .toPixelMap()
        val distinct = HashSet<Int>()
        for (y in 0 until pixels.height) {
            for (x in 0 until pixels.width) distinct.add(pixels[x, y].toArgb())
        }
        assertTrue("the designed JSON glyph drew nothing (colours=$distinct)", distinct.size > 1)
    }

    // ── absence assertions (rule 51 — what was deliberately NOT drawn) ───────────────────

    @Test fun noBookmarksCountChip() {
        // The committed artboard draws exactly THREE chips (`:488-492`): Highlights, Notes,
        // Skipped. Bookmarks are counted in `Import N items` but have no depicted chip, and
        // inventing a fourth is prohibited. This assertion pins the absence so a stray addition
        // goes RED instead of quietly shipping undesigned UI.
        val preview = mixedPreview()
        assertEquals(2, preview.bookmarks)
        setSheet(AnnotationImportSheetState.Ready(preview))
        compose.onAllNodesWithTag("annot-import-chip-bookmarks", useUnmergedTree = true).assertCountEquals(0)
    }

    @Test fun theOnlyTwoActionsAreCancelAndImport() {
        // WI-8 / needs-design #2085 — nothing about export exists on the import surface. Asserting
        // the ABSENCE of one tag and one literal string would false-green on an icon-only or
        // differently-worded affordance, so this enumerates the whole clickable set instead.
        setSheet(AnnotationImportSheetState.Ready(mixedPreview()))

        val clickable = compose.onAllNodes(hasClickAction()).fetchSemanticsNodes()
        val tags = clickable.mapNotNull { it.config.getOrNull(SemanticsProperties.TestTag) }.toSet()
        assertEquals(setOf("annot-import-cancel", "annot-import-confirm"), tags)
        assertEquals(2, clickable.size)
    }

    @Test fun aVeryLongTitleCannotPushTheActionsOffTheSheet() {
        // The merge line interpolates the book title; the body scrolls and the actions are pinned,
        // so an unbounded title cannot bury the only way out of the sheet.
        val preview = previewOf(
            envelopeJson(highlights = (1..5).map { highlight(uuid(it), offset = it * 10) }),
            bookTitle = "書".repeat(4_000),
        )
        var confirmed: ImportPreview? = null
        setSheet(AnnotationImportSheetState.Ready(preview), onConfirm = { confirmed = it })

        compose.onNodeWithTag("annot-import-cancel").assertIsDisplayed()
        compose.onNodeWithTag("annot-import-confirm").assertIsDisplayed().assertIsEnabled()
        compose.onNodeWithTag("annot-import-confirm").performClick()
        compose.waitForIdle()
        assertSame(preview, confirmed)
    }

    @Test fun rtlPayloadRendersAndLeavesTheActionsReachable() {
        val arabic = "هذا اقتباس من الكتاب"
        val preview = previewOf(
            envelopeJson(highlights = listOf(highlight(uuid(1), 10, text = arabic))),
            bookTitle = arabic,
        )
        setSheet(AnnotationImportSheetState.Ready(preview))

        compose.onNodeWithText("\"" + arabic + "\"", useUnmergedTree = true).assertExists()
        compose.onNodeWithTag("annot-import-confirm").assertIsDisplayed().assertIsEnabled()
    }

    @Test fun anUnknownWireColorFallsBackInsteadOfDisappearing() {
        // The reader folds an unknown provider color to AnnotationColor.DEFAULT before it can drive
        // the dot; the row still renders.
        val preview = previewOf(
            envelopeJson(
                highlights = listOf(
                    highlight(uuid(1), 10, text = "unknown color").copy(color = "chartreuse"),
                ),
            ),
        )
        assertEquals(AnnotationColor.DEFAULT.key, preview.sample.single().colorKey)
        setSheet(AnnotationImportSheetState.Ready(preview))
        compose.onNodeWithText("\"unknown color\"", useUnmergedTree = true).assertExists()
    }

    @Test fun aBookmarkWithNoTitleStillProducesARenderableSampleRow() {
        val preview = previewOf(envelopeJson(bookmarks = listOf(bookmark(uuid(1), 10, title = null))))
        assertEquals(1, preview.importable)
        assertEquals("", preview.sample.single().text)
        setSheet(AnnotationImportSheetState.Ready(preview))

        compose.onAllNodesWithTag("annot-import-sample-row", useUnmergedTree = true).assertCountEquals(1)
        compose.onNodeWithText("Import 1 items", useUnmergedTree = true).assertExists()
    }

    // ── the ModalBottomSheet wrapper ────────────────────────────────────────────────────

    @Test fun modalWrapper_rendersItsContent() {
        compose.setContent {
            AnnotationImportPreviewSheet(
                theme = ReaderTheme.Paper,
                state = AnnotationImportSheetState.Ready(mixedPreview()),
                onCancel = {},
                onConfirm = {},
                onDismiss = {},
            )
        }
        compose.waitForIdle()
        compose.onNodeWithText("Import annotations").assertExists()
    }
}
