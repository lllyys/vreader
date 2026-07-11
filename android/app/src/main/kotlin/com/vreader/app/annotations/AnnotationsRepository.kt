// Purpose: feature #123 — the annotation repository (the DTO boundary over AnnotationDao; rule 50 §2).
// Process-singleton in AppContainer (the #122 statsRepository precedent). Exposes Flow reads mapping
// entities -> records (corrupt rows skipped, not crashed) + suspend CRUD that creates records and
// dedupes through the DAO's transactional upsert. Feature #132 WI-6b adds the review-sheet snapshot
// (annotationsForBook), the backup collector all-snapshot reads (allNotes/allBookmarks), and the
// UUID-preserving transactional restore seam (restoreAnnotations -> RestoreAnnotationsReport).
package com.vreader.app.annotations

import com.vreader.app.data.AnnotationDao
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import vreader.contracts.Locator
import vreader.contracts.backup.BackupAnnotationsEnvelope
import vreader.contracts.backup.BackupJson

/** The outcome of an atomic bookmark toggle (feature #135 WI-3): a create-or-remove decided by the
 *  presence of a bookmark at the same `(bookKey, profileKey)` — the top-bar toggle's semantics. */
enum class BookmarkToggleResult { Added, Removed }

class AnnotationsRepository(
    private val dao: AnnotationDao,
    private val now: () -> Long = { System.currentTimeMillis() },
) {
    // ---- highlights ----

    fun highlights(bookKey: String): Flow<List<HighlightRecord>> =
        dao.observeHighlights(bookKey).map { rows -> rows.mapNotNull { it.toRecordOrNull() } }

    suspend fun highlightsForBook(bookKey: String): List<HighlightRecord> =
        dao.highlightsForBook(bookKey).mapNotNull { it.toRecordOrNull() }

    suspend fun allHighlights(): List<HighlightRecord> =
        dao.allHighlights().mapNotNull { it.toRecordOrNull() }

    /** Create (or, for a re-highlight of the same range, update) a highlight. Returns the record.
     *  Dedupe is the DAO's transactional upsert on the unique (profileKey, anchorKey). */
    suspend fun addHighlight(
        bookKey: String,
        color: AnnotationColor,
        selectedText: String,
        locator: Locator,
        anchor: AnnotationAnchor?,
        note: String? = null,
    ): HighlightRecord {
        requireSameBook(bookKey, locator)
        val t = now()
        val record = HighlightRecord(
            id = newAnnotationId(), bookKey = bookKey, color = color, selectedText = selectedText,
            note = note, locator = locator, anchor = anchor, createdAt = t, updatedAt = t,
        )
        // return the PERSISTED row: on a dedupe the upsert keeps the existing id, so the freshly
        // generated id was never stored — returning it would hand callers a dead highlightId.
        val persisted = dao.upsertHighlight(record.toEntity())
        return persisted.toRecordOrNull() ?: record
    }

    suspend fun updateHighlight(id: String, color: AnnotationColor, note: String?) {
        dao.updateHighlightColorNote(id, color.key, note, now())
    }

    suspend fun removeHighlight(id: String) = dao.deleteHighlight(id)

    suspend fun findHighlight(id: String): HighlightRecord? = dao.findHighlight(id)?.toRecordOrNull()

    // ---- standalone notes ----

    fun notes(bookKey: String): Flow<List<NoteRecord>> =
        dao.observeNotes(bookKey).map { rows -> rows.mapNotNull { it.toRecordOrNull() } }

    suspend fun addNote(bookKey: String, content: String, locator: Locator, anchor: AnnotationAnchor? = null): NoteRecord {
        requireSameBook(bookKey, locator)
        val t = now()
        val record = NoteRecord(
            id = newAnnotationId(), bookKey = bookKey, content = content,
            locator = locator, anchor = anchor, createdAt = t, updatedAt = t,
        )
        dao.upsertNote(record.toEntity())
        return record
    }

    suspend fun removeNote(id: String) = dao.deleteNote(id)

    // ---- bookmarks (schema wired; create/list UI is item F) ----

    fun bookmarks(bookKey: String): Flow<List<BookmarkRecord>> =
        dao.observeBookmarks(bookKey).map { rows -> rows.mapNotNull { it.toRecordOrNull() } }

    suspend fun addBookmark(bookKey: String, title: String?, locator: Locator): BookmarkRecord {
        requireSameBook(bookKey, locator)
        val t = now()
        val record = BookmarkRecord(
            id = newAnnotationId(), bookKey = bookKey, title = title,
            locator = locator, createdAt = t, updatedAt = t,
        )
        dao.upsertBookmark(record.toEntity())
        return record
    }

    suspend fun removeBookmark(id: String) = dao.deleteBookmark(id)

    /**
     * Atomic bookmark toggle at `locator`'s position (feature #135 WI-3 — the top-bar toggle's
     * create/remove). Builds the entity via [BookmarkRecord.toEntity] (which derives the `profileKey`)
     * and delegates to the DAO's `@Transaction` toggle on the unique `(bookKey, profileKey)` index: no
     * bookmark there yet → `Added`; one already there → `Removed`. A toggle intentionally ALTERNATES
     * state — two serialized calls Add then Remove (they do not converge). The unique index guarantees
     * at most ONE row per position, so a concurrent repeat CREATE never produces a duplicate; whether
     * a rapid double-tap should leave a bookmark is a UI tap-coalescing concern (WI-5), not this seam.
     */
    suspend fun toggleBookmark(bookKey: String, title: String?, locator: Locator): BookmarkToggleResult {
        requireSameBook(bookKey, locator)
        val t = now()
        val record = BookmarkRecord(
            id = newAnnotationId(), bookKey = bookKey, title = title,
            locator = locator, createdAt = t, updatedAt = t,
        )
        return dao.toggleBookmark(record.toEntity())
    }

    /** Is the given position bookmarked? (the top-bar toggle's filled/empty state). */
    suspend fun isBookmarked(bookKey: String, locator: Locator): Boolean {
        requireSameBook(bookKey, locator)
        return dao.isBookmarked(bookKey, profileKeyFor(bookKey, locator)) > 0
    }

    suspend fun highlightCount(bookKey: String): Int = dao.highlightCount(bookKey)

    // ---- feature #132 WI-6b: review-sheet snapshot + backup collector reads + restore seam ----

    /** A deterministic one-shot of this book's highlights + notes for the review sheet's non-Flow
     *  open (complements the observable Flows). Corrupt rows are dropped (`toRecordOrNull`); each
     *  kind is sorted by (createdAt, id) so repeated reads and the sheet's initial render are stable. */
    suspend fun annotationsForBook(bookKey: String): AnnotationsSnapshot {
        val highlights = dao.highlightsForBook(bookKey)
            .mapNotNull { it.toRecordOrNull() }
            .sortedWith(compareBy({ it.createdAt }, { it.id }))
        val notes = dao.notesForBook(bookKey)
            .mapNotNull { it.toRecordOrNull() }
            .sortedWith(compareBy({ it.createdAt }, { it.id }))
        return AnnotationsSnapshot(highlights = highlights, notes = notes)
    }

    /** All standalone notes across every book — the backup collector read (WI-8). Corrupt rows dropped. */
    suspend fun allNotes(): List<NoteRecord> = dao.allNotes().mapNotNull { it.toRecordOrNull() }

    /** All bookmarks across every book — the backup collector read (WI-8). Corrupt rows dropped. */
    suspend fun allBookmarks(): List<BookmarkRecord> = dao.allBookmarks().mapNotNull { it.toRecordOrNull() }

    /**
     * Restore annotations from a backup envelope, PRESERVING each row's backed-up UUID + timestamps
     * (never minting a fresh id — the create methods would). Per kind:
     *  - a row whose `bookFingerprintKey` ∉ [allowedBookKeys] is dropped, counted `skipped`
     *    (annotations for a book that wasn't restored are dropped — iOS parity);
     *  - a row whose `locatorJSON` can't parse to a `Locator`, or whose parsed `fingerprintKey`
     *    ≠ `bookFingerprintKey`, is dropped, counted `failed` (poisoning the persistence boundary
     *    is worse than dropping one row);
     *  - an in-scope, valid row is inserted-if-absent under its preserved UUID → counted `applied`
     *    on a fresh insert, `skipped` when the UUID (or a same-anchor highlight guarded by the
     *    (profileKey, anchorKey) unique index) already exists — so a repeated restore applies 0.
     * All inserts run in ONE DAO @Transaction. `locatorJSON` is the PLAIN `Locator` JSON
     * (`BackupJson`-decodable), the same decodable form positions use.
     */
    suspend fun restoreAnnotations(
        env: BackupAnnotationsEnvelope,
        allowedBookKeys: Set<String>,
    ): RestoreAnnotationsReport {
        var hSkipped = 0
        var hFailed = 0
        val highlightEntities = env.highlights.mapNotNull { row ->
            when (val v = validate(row.bookFingerprintKey, row.locatorJSON, allowedBookKeys)) {
                Validity.OUT_OF_SCOPE -> { hSkipped++; null }
                Validity.INVALID -> { hFailed++; null }
                else -> HighlightRecord(
                    id = row.highlightId, bookKey = row.bookFingerprintKey,
                    color = AnnotationColor.from(row.color) ?: AnnotationColor.DEFAULT,
                    selectedText = row.selectedText, note = row.note,
                    locator = (v as Validity.Valid).locator, anchor = null,
                    createdAt = row.createdAt.toEpochMilli(), updatedAt = row.updatedAt.toEpochMilli(),
                ).toEntity()
            }
        }

        var nSkipped = 0
        var nFailed = 0
        val noteEntities = env.notes.mapNotNull { row ->
            when (val v = validate(row.bookFingerprintKey, row.locatorJSON, allowedBookKeys)) {
                Validity.OUT_OF_SCOPE -> { nSkipped++; null }
                Validity.INVALID -> { nFailed++; null }
                else -> NoteRecord(
                    id = row.annotationId, bookKey = row.bookFingerprintKey, content = row.content,
                    locator = (v as Validity.Valid).locator, anchor = null,
                    createdAt = row.createdAt.toEpochMilli(), updatedAt = row.updatedAt.toEpochMilli(),
                ).toEntity()
            }
        }

        var bSkipped = 0
        var bFailed = 0
        val bookmarkEntities = env.bookmarks.mapNotNull { row ->
            when (val v = validate(row.bookFingerprintKey, row.locatorJSON, allowedBookKeys)) {
                Validity.OUT_OF_SCOPE -> { bSkipped++; null }
                Validity.INVALID -> { bFailed++; null }
                else -> BookmarkRecord(
                    id = row.bookmarkId, bookKey = row.bookFingerprintKey, title = row.title,
                    locator = (v as Validity.Valid).locator,
                    createdAt = row.createdAt.toEpochMilli(), updatedAt = row.updatedAt.toEpochMilli(),
                ).toEntity()
            }
        }

        val (hApplied, nApplied, bApplied) =
            dao.restoreAnnotationEntities(highlightEntities, noteEntities, bookmarkEntities)

        return RestoreAnnotationsReport(
            highlights = KindCounts(hApplied, hSkipped + (highlightEntities.size - hApplied), hFailed),
            notes = KindCounts(nApplied, nSkipped + (noteEntities.size - nApplied), nFailed),
            bookmarks = KindCounts(bApplied, bSkipped + (bookmarkEntities.size - bApplied), bFailed),
        )
    }

    private sealed interface Validity {
        data class Valid(val locator: Locator) : Validity
        data object OUT_OF_SCOPE : Validity
        data object INVALID : Validity
    }

    /** Allowed-book scope + locator-parses + fingerprint-matches gate for one restore row. */
    private fun validate(bookKey: String, locatorJSON: String, allowedBookKeys: Set<String>): Validity {
        if (bookKey !in allowedBookKeys) return Validity.OUT_OF_SCOPE
        val locator = runCatching { BackupJson.decode<Locator>(locatorJSON) }.getOrNull()
            ?: return Validity.INVALID
        if (locator.fingerprintKey != bookKey) return Validity.INVALID
        return Validity.Valid(locator)
    }

    /** An annotation's locator must belong to the same book it's filed under — else backup/export and
     *  reader-restore assumptions are poisoned (the iOS persistence-boundary guard). */
    private fun requireSameBook(bookKey: String, locator: Locator) =
        require(locator.fingerprintKey == bookKey) {
            "annotation locator (${locator.fingerprintKey}) does not match bookKey ($bookKey)"
        }
}
