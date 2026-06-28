// Purpose: Room DAOs — the Android analog of the iOS PersistenceActor CRUD
// extensions (feature #106 WI-3). DAOs expose suspend writes + Flow reads; Room
// serializes access off the main thread. Views never touch a DAO directly — the
// repository (DTOs) is the boundary (rule 50 §2: never return @Model/entity types
// across the layer).
package com.vreader.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface BookDao {
    // @Upsert (insert-or-UPDATE), NOT @Insert(REPLACE). REPLACE is delete-then-insert
    // in SQLite, which would fire reading_positions' ON DELETE CASCADE and silently
    // wipe a book's saved position on every re-import (Gate-4 Critical). @Upsert
    // updates in place, preserving the child row.
    @Upsert
    suspend fun upsert(book: BookEntity)

    @Query("SELECT * FROM books ORDER BY addedAt DESC")
    fun observeAll(): Flow<List<BookEntity>>

    @Query("SELECT * FROM books WHERE fingerprintKey = :key")
    suspend fun find(key: String): BookEntity?

    // feature #116 WI-3 — one-shot snapshot for the backup collector (not the observable Flow).
    // Ordered by fingerprintKey (NOT the library-display addedAt) so a repeat backup of unchanged
    // content yields a byte-stable manifest (matches the iOS projection ordering).
    @Query("SELECT * FROM books ORDER BY fingerprintKey")
    suspend fun getAll(): List<BookEntity>

    @Query("DELETE FROM books WHERE fingerprintKey = :key")
    suspend fun delete(key: String)

    @Query("UPDATE books SET lastOpenedAt = :openedAt WHERE fingerprintKey = :key")
    suspend fun markOpened(key: String, openedAt: Long)
}

@Dao
interface ReadingPositionDao {
    @Upsert
    suspend fun upsert(position: ReadingPositionEntity)

    @Query("SELECT * FROM reading_positions WHERE fingerprintKey = :key")
    suspend fun find(key: String): ReadingPositionEntity?

    // feature #116 WI-3 — all saved positions, for the backup collector. Ordered by fingerprintKey
    // for byte-stable repeat backups (positions.json array order is otherwise plan-dependent).
    @Query("SELECT * FROM reading_positions ORDER BY fingerprintKey")
    suspend fun getAll(): List<ReadingPositionEntity>

    @Query("DELETE FROM reading_positions WHERE fingerprintKey = :key")
    suspend fun delete(key: String)
}

@Dao
abstract class ReadingStatsDao {
    // feature #122 — minSdk-26-safe increment. NOT SQLite UPSERT (`INSERT … ON CONFLICT DO UPDATE` is
    // unreliable on API 26/27), and @Upsert can't increment. INSERT OR IGNORE a zero row, then UPDATE
    // += delta, wrapped in @Transaction so concurrent increments don't lose updates.
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    abstract suspend fun insertZeroIfAbsent(row: DailyReadingEntity)

    @Query("UPDATE daily_reading SET minutes = minutes + :delta WHERE date = :date AND bookKey = :bookKey")
    abstract suspend fun bump(date: String, bookKey: String, delta: Int)

    @Transaction
    open suspend fun addMinutes(date: String, bookKey: String, delta: Int) {
        if (delta == 0) return
        insertZeroIfAbsent(DailyReadingEntity(date = date, bookKey = bookKey, minutes = 0))
        bump(date, bookKey, delta)
    }

    @Query("SELECT * FROM daily_reading WHERE date >= :since ORDER BY date")
    abstract fun observeRowsSince(since: String): Flow<List<DailyReadingEntity>>

    @Query("SELECT * FROM daily_reading WHERE date >= :since ORDER BY date")
    abstract suspend fun rowsSince(since: String): List<DailyReadingEntity>

    @Query("SELECT * FROM daily_reading ORDER BY date")
    abstract suspend fun allRows(): List<DailyReadingEntity>

    /** DISTINCT active local dates (>= since), newest first — the streak/active-day source. */
    @Query("SELECT DISTINCT date FROM daily_reading WHERE date >= :since ORDER BY date DESC")
    abstract suspend fun activeDatesSince(since: String): List<String>
}

@Dao
abstract class AnnotationDao {
    // ---- highlights ----
    // Dedupe on the unique (profileKey, anchorKey): a re-highlight of the same range UPDATES in place
    // rather than inserting a duplicate (the iOS PersistenceActor+Highlights analog). @Insert(IGNORE)
    // returns -1 when the unique index rejects the row; then UPDATE the existing row by its key. The
    // whole thing is @Transaction so a concurrent re-highlight can't race insert-vs-update.
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    abstract suspend fun insertHighlightIfAbsent(highlight: HighlightEntity): Long

    @Query(
        "UPDATE highlights SET color = :color, note = :note, selectedText = :selectedText, " +
            "locatorJSON = :locatorJSON, anchorJSON = :anchorJSON, updatedAt = :updatedAt " +
            "WHERE profileKey = :profileKey AND anchorKey = :anchorKey",
    )
    abstract suspend fun updateHighlightByKey(
        profileKey: String,
        anchorKey: String,
        color: String,
        note: String?,
        selectedText: String,
        locatorJSON: String,
        anchorJSON: String?,
        updatedAt: Long,
    ): Int

    @Query("SELECT * FROM highlights WHERE profileKey = :profileKey AND anchorKey = :anchorKey")
    abstract suspend fun findHighlightByKey(profileKey: String, anchorKey: String): HighlightEntity?

    /** Insert-or-update on the unique (profileKey, anchorKey), then return the PERSISTED row. On a
     *  dedupe the persisted row keeps the EXISTING highlightId (the insert was ignored), so callers
     *  must use the returned row's id — not the id of the entity they passed in (which was discarded). */
    @Transaction
    open suspend fun upsertHighlight(highlight: HighlightEntity): HighlightEntity {
        val rowId = insertHighlightIfAbsent(highlight)
        if (rowId == -1L) {
            updateHighlightByKey(
                highlight.profileKey, highlight.anchorKey, highlight.color, highlight.note,
                highlight.selectedText, highlight.locatorJSON, highlight.anchorJSON, highlight.updatedAt,
            )
        }
        return findHighlightByKey(highlight.profileKey, highlight.anchorKey)!!
    }

    @Query("UPDATE highlights SET color = :color, note = :note, updatedAt = :updatedAt WHERE highlightId = :id")
    abstract suspend fun updateHighlightColorNote(id: String, color: String, note: String?, updatedAt: Long): Int

    @Query("SELECT * FROM highlights WHERE bookKey = :bookKey ORDER BY createdAt")
    abstract fun observeHighlights(bookKey: String): Flow<List<HighlightEntity>>

    @Query("SELECT * FROM highlights WHERE bookKey = :bookKey ORDER BY createdAt")
    abstract suspend fun highlightsForBook(bookKey: String): List<HighlightEntity>

    @Query("SELECT * FROM highlights ORDER BY bookKey, createdAt")
    abstract suspend fun allHighlights(): List<HighlightEntity>

    @Query("SELECT * FROM highlights WHERE highlightId = :id")
    abstract suspend fun findHighlight(id: String): HighlightEntity?

    @Query("DELETE FROM highlights WHERE highlightId = :id")
    abstract suspend fun deleteHighlight(id: String)

    @Query("SELECT COUNT(*) FROM highlights WHERE bookKey = :bookKey")
    abstract suspend fun highlightCount(bookKey: String): Int

    // ---- standalone notes ----
    @Upsert
    abstract suspend fun upsertNote(note: AnnotationNoteEntity)

    @Query("SELECT * FROM annotation_notes WHERE bookKey = :bookKey ORDER BY createdAt")
    abstract fun observeNotes(bookKey: String): Flow<List<AnnotationNoteEntity>>

    @Query("SELECT * FROM annotation_notes WHERE bookKey = :bookKey ORDER BY createdAt")
    abstract suspend fun notesForBook(bookKey: String): List<AnnotationNoteEntity>

    @Query("DELETE FROM annotation_notes WHERE noteId = :id")
    abstract suspend fun deleteNote(id: String)

    // ---- bookmarks (schema wired; create/list UI is item F) ----
    @Upsert
    abstract suspend fun upsertBookmark(bookmark: BookmarkEntity)

    @Query("SELECT * FROM bookmarks WHERE bookKey = :bookKey ORDER BY createdAt")
    abstract fun observeBookmarks(bookKey: String): Flow<List<BookmarkEntity>>

    @Query("SELECT * FROM bookmarks WHERE bookKey = :bookKey ORDER BY createdAt")
    abstract suspend fun bookmarksForBook(bookKey: String): List<BookmarkEntity>

    @Query("DELETE FROM bookmarks WHERE bookmarkId = :id")
    abstract suspend fun deleteBookmark(id: String)
}
