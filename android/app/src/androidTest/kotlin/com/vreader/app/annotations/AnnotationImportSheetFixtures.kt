package com.vreader.app.annotations

import org.junit.Assert.assertTrue
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
 * Feature #165 WI-5 — wire fixtures for `AnnotationImportPreviewSheetTest` (the
 * `AnnotationImportFixtures` / `AnnotationsImportApplierHarness` precedent on the JVM side).
 *
 * Previews are always produced by the REAL [AnnotationsImportReader] from real encoded bytes, never
 * by constructing an [ImportPreview] by hand: a hand-built preview could carry counts its envelope
 * does not support, which is precisely the divergence the sheet's tests exist to rule out.
 */
internal object SheetFx {

    val BOOK = "epub:" + "a".repeat(64) + ":1000"

    private val T0: Instant = Instant.parse("2026-08-05T10:00:00Z")

    /** A well-formed v4 UUID string, distinct per [n]. */
    fun uuid(n: Int): String = "00000000-0000-4000-8000-" + n.toString().padStart(12, '0')

    private fun locatorJson(offset: Int): String = BackupJson.encode(
        Locator(
            contentSHA256 = "a".repeat(64),
            fileByteCount = 1000,
            format = "epub",
            charOffsetUTF16 = offset,
        ),
    )

    fun highlight(id: String, offset: Int, text: String = "quote $offset") = BackupHighlight(
        highlightId = id,
        bookFingerprintKey = BOOK,
        locatorJSON = locatorJson(offset),
        selectedText = text,
        color = "yellow",
        note = null,
        createdAt = T0,
        updatedAt = T0,
    )

    fun note(id: String, offset: Int, content: String = "note $offset") = BackupNote(
        annotationId = id,
        bookFingerprintKey = BOOK,
        locatorJSON = locatorJson(offset),
        content = content,
        createdAt = T0,
        updatedAt = T0,
    )

    fun bookmark(id: String, offset: Int, title: String? = "mark $offset") = BackupBookmark(
        bookmarkId = id,
        bookFingerprintKey = BOOK,
        locatorJSON = locatorJson(offset),
        title = title,
        createdAt = T0,
        updatedAt = T0,
    )

    fun envelopeJson(
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

    fun previewOf(
        json: String,
        fileName: String = "pride-and-prejudice.annotations.json",
        bookTitle: String = "Pride and Prejudice",
        existing: ExistingAnnotationState = ExistingAnnotationState.EMPTY,
    ): ImportPreview {
        val result = AnnotationsImportReader.parse(
            ByteArrayInputStream(json.toByteArray(Charsets.UTF_8)),
            fileName,
            BOOK,
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
    fun mixedPreview(): ImportPreview {
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
    fun duplicatePreview(): ImportPreview = previewOf(
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
}
