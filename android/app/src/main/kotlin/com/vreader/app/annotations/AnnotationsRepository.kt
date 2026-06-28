// Purpose: feature #123 — the annotation repository (the DTO boundary over AnnotationDao; rule 50 §2).
// Process-singleton in AppContainer (the #122 statsRepository precedent). Exposes Flow reads mapping
// entities -> records (corrupt rows skipped, not crashed) + suspend CRUD that creates records and
// dedupes through the DAO's transactional upsert.
package com.vreader.app.annotations

import com.vreader.app.data.AnnotationDao
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import vreader.contracts.Locator

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

    suspend fun highlightCount(bookKey: String): Int = dao.highlightCount(bookKey)

    /** An annotation's locator must belong to the same book it's filed under — else backup/export and
     *  reader-restore assumptions are poisoned (the iOS persistence-boundary guard). */
    private fun requireSameBook(bookKey: String, locator: Locator) =
        require(locator.fingerprintKey == bookKey) {
            "annotation locator (${locator.fingerprintKey}) does not match bookKey ($bookKey)"
        }
}
