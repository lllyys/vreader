// Purpose: feature #165 WI-1 — THE single record→wire mapping for the `annotations.json` contract
// section, lifted verbatim out of BackupCollector's privates so the backup collector (#132 WI-8) and
// the #165 per-book annotations exporter share ONE copy. Two copies of a versioned cross-platform
// contract mapping drift, and the drift is invisible until a file written by one path fails to
// restore through the other.
//
// Key decisions:
//  - `envelope`/`json` are the ONLY entry points; the three per-record mappers stay private. A caller
//    cannot reassemble the wire shape with a different sort or a different envelope — the sort IS
//    part of the contract's byte-stability guarantee, so it must not be separable from the mapping.
//  - Deterministic order: each kind sorted by (bookFingerprintKey, id), so the same logical store
//    serializes byte-identically regardless of Room row order.
//  - `locatorJSON` is the PLAIN serialized `Locator` (`BackupJson.encode(locator)` — matching iOS
//    `encoder.encode(locator)`, `contracts/vectors/backup-sections.json`, and the restore seam's
//    plain decode); NEVER `Locator.canonicalJson()`, whose flattened dotted keys are not
//    `Locator`-decodable.
//  - Each row's UUID and timestamps are PRESERVED (epoch-millis → Instant; BackupJson emits ISO8601
//    UTC at second precision). A null highlight note / bookmark title is OMITTED from the JSON by
//    BackupJson's explicitNulls=false (Swift Codable parity), never emitted as `null`.
//
// @coordinates-with BackupCollector (the annotations.json section), AnnotationsRepository (the
// record reads), vreader.contracts.backup.BackupSections (the wire DTOs).
package com.vreader.app.backup

import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.annotations.HighlightRecord
import com.vreader.app.annotations.NoteRecord
import vreader.contracts.backup.BackupAnnotationsEnvelope
import vreader.contracts.backup.BackupBookmark
import vreader.contracts.backup.BackupHighlight
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupNote
import vreader.contracts.backup.BackupSchema
import java.time.Instant

internal object AnnotationBackupMapper {

    /**
     * The `annotations.json` wire shape for the given records. Callers pass whatever slice they own
     * (the collector: every row filtered to the backed-up books; the exporter: one book's rows);
     * the deterministic sort and the record→wire mapping happen here, once.
     */
    fun envelope(
        highlights: List<HighlightRecord>,
        notes: List<NoteRecord>,
        bookmarks: List<BookmarkRecord>,
    ): BackupAnnotationsEnvelope = BackupAnnotationsEnvelope(
        schemaVersion = BackupSchema.CURRENT_SCHEMA_VERSION,
        highlights = highlights.sortedWith(compareBy({ it.bookKey }, { it.id })).map { it.toWire() },
        bookmarks = bookmarks.sortedWith(compareBy({ it.bookKey }, { it.id })).map { it.toWire() },
        notes = notes.sortedWith(compareBy({ it.bookKey }, { it.id })).map { it.toWire() },
    )

    /** [envelope] serialized — the exact `annotations.json` section text. */
    fun json(
        highlights: List<HighlightRecord>,
        notes: List<NoteRecord>,
        bookmarks: List<BookmarkRecord>,
    ): String = BackupJson.encode(envelope(highlights, notes, bookmarks))

    private fun HighlightRecord.toWire() = BackupHighlight(
        highlightId = id,
        bookFingerprintKey = bookKey,
        locatorJSON = BackupJson.encode(locator),
        selectedText = selectedText,
        color = color.key,
        note = note,
        createdAt = Instant.ofEpochMilli(createdAt),
        updatedAt = Instant.ofEpochMilli(updatedAt),
    )

    private fun NoteRecord.toWire() = BackupNote(
        annotationId = id,
        bookFingerprintKey = bookKey,
        locatorJSON = BackupJson.encode(locator),
        content = content,
        createdAt = Instant.ofEpochMilli(createdAt),
        updatedAt = Instant.ofEpochMilli(updatedAt),
    )

    private fun BookmarkRecord.toWire() = BackupBookmark(
        bookmarkId = id,
        bookFingerprintKey = bookKey,
        locatorJSON = BackupJson.encode(locator),
        title = title,
        createdAt = Instant.ofEpochMilli(createdAt),
        updatedAt = Instant.ofEpochMilli(updatedAt),
    )
}
