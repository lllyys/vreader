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
    //
    // NOTE: the SAF import path does NOT use this whole-row @Upsert — it uses
    // [upsertPreservingAuthor] below, so a duplicate import can't null-clobber a
    // backfilled `author` (feature #128 WI-1 Gate-2 Critical). This whole-row upsert is
    // kept for callers (e.g. the restore path pre-#128) that intentionally write every
    // column, and is exercised by the reUpsert-preserves-position regression.
    //
    // WHOLE-ROW MEANS WHOLE-ROW: it overwrites `author`, `lastOpenedAt`, AND the #152 cover
    // columns with whatever the passed entity carries — so a caller that CONSTRUCTS a
    // BookEntity (rather than round-tripping one it read) silently erases all of them.
    // It has NO production caller today (every import goes through upsertPreservingAuthor);
    // it survives as a test/fixture seam, and `BookDaoCoverStateTest` pins the destructive
    // behaviour so it is documented rather than latent.
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

    // ---- feature #128 WI-1: author column + author-preserving persistence ----

    /** Set `author` ONLY when it's currently null (a backfill never overwrites a real author). */
    @Query("UPDATE books SET author = :author WHERE fingerprintKey = :key AND author IS NULL")
    suspend fun backfillAuthorIfNull(key: String, author: String?)

    /** Insert a fresh row iff absent; returns -1 (via OnConflictStrategy.IGNORE) when the PK already
     *  exists, signalling the caller to take the author-preserving UPDATE branch. */
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertIfAbsent(book: BookEntity): Long

    /** UPDATE only the IMPORT-owned columns. Deliberately excludes `author` AND `lastOpenedAt` so a
     *  duplicate SAF import refreshes the file/identity metadata without clobbering a backfilled author
     *  or the last-opened recency (feature #128 WI-1 Gate-2 Critical).
     *
     *  It ALSO excludes `coverPath` and `coverExtractorVersion` (feature #152 WI-2), for the same
     *  reason and one more: a cover may have been chosen by the USER (#153), which is not re-derivable
     *  from the file, and clobbering the version memo would put a known art-less book back into the
     *  backfill on every app start. **Anything added to this statement is, by construction, a column a
     *  re-import is allowed to overwrite** — that is the whole contract, so adding a column here is a
     *  deliberate act, never a completeness tidy-up. `BookDaoCoverStateTest` asserts the exclusion as
     *  behaviour (re-import, then read the columns back), not by reading this SQL. */
    @Query(
        "UPDATE books SET title = :title, originalFormat = :fmt, contentSHA256 = :sha, " +
            "fileByteCount = :bytes, localFilePath = :path, sourceUri = :uri, addedAt = :addedAt " +
            "WHERE fingerprintKey = :key",
    )
    suspend fun updateImportedColumns(
        key: String,
        title: String,
        fmt: String,
        sha: String,
        bytes: Long,
        path: String?,
        uri: String?,
        addedAt: Long,
    )

    /** Atomic insert-or-update-import-columns that leaves `author` (and `lastOpenedAt`) untouched on the
     *  update branch — the SAF import path's upsert. Mirrors [AnnotationDao.upsertHighlight]: an
     *  insert-if-absent returning -1 falls through to the column-scoped UPDATE, wrapped in @Transaction
     *  so a concurrent re-import can't race insert-vs-update. */
    @Transaction
    suspend fun upsertPreservingAuthor(book: BookEntity) {
        if (insertIfAbsent(book) == -1L) {
            updateImportedColumns(
                key = book.fingerprintKey,
                title = book.title,
                fmt = book.originalFormat,
                sha = book.contentSHA256,
                bytes = book.fileByteCount,
                path = book.localFilePath,
                uri = book.sourceUri,
                addedAt = book.addedAt,
            )
        }
    }

    /** Restore-path metadata apply (wired by WI-2's RestoreImporter): sets the manifest's
     *  title/addedAt/lastOpenedAt and COALESCEs the author — a non-null manifest author WINS, a null
     *  manifest author PRESERVES whatever the coordinator backfilled. Book row already exists (restored
     *  first, so the position FK holds). */
    @Query(
        "UPDATE books SET title = :title, addedAt = :addedAt, lastOpenedAt = :lastOpenedAt, " +
            "author = COALESCE(:manifestAuthor, author) WHERE fingerprintKey = :key",
    )
    suspend fun applyRestoredMetadata(
        key: String,
        title: String,
        addedAt: Long,
        lastOpenedAt: Long?,
        manifestAuthor: String?,
    )

    // ---- feature #152 WI-2: cover state ----

    // The cover columns are ONE tri-state and are never written apart, so there is no
    // `setCoverState(path: String?, version: Int?)` primitive: a nullable pair can express
    // `(path != null, version == null)`, which is not a state the tri-state defines, and it makes the
    // reset indistinguishable from a definite outcome at the call site (Gate-4 round-1 Medium). The
    // three legal transitions get three names instead, so the illegal fourth is unrepresentable.
    //
    // A `Failed` extraction calls NONE of them — leaving the row's existing state is what makes the
    // book retryable. All three are column-scoped: an unknown or already-deleted `key` updates zero
    // rows rather than inserting, and no other column is touched.

    /** Art was found: point at the file and stamp the version. */
    @Query("UPDATE books SET coverPath = :path, coverExtractorVersion = :version WHERE fingerprintKey = :key")
    suspend fun setCoverArt(key: String, path: String, version: Int)

    /** Reachable, parsed, genuinely no art: clear the pointer but STAMP the version anyway. The stamp
     *  is the whole point — it is what stops the backfill re-opening this book on every app start. */
    @Query("UPDATE books SET coverPath = NULL, coverExtractorVersion = :version WHERE fingerprintKey = :key")
    suspend fun setCoverAbsent(key: String, version: Int)

    /** Reset to eligible (both NULL) — a deliberate re-run lever, deliberately NOT reachable by
     *  passing nulls to one of the recording calls above. */
    @Query("UPDATE books SET coverPath = NULL, coverExtractorVersion = NULL WHERE fingerprintKey = :key")
    suspend fun clearCoverState(key: String)
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

    // feature #132 WI-6b — all notes snapshot for the backup collector (WI-8). Ordered by
    // (bookKey, createdAt) so a repeat backup of unchanged content is byte-stable.
    @Query("SELECT * FROM annotation_notes ORDER BY bookKey, createdAt")
    abstract suspend fun allNotes(): List<AnnotationNoteEntity>

    @Query("DELETE FROM annotation_notes WHERE noteId = :id")
    abstract suspend fun deleteNote(id: String)

    // ---- bookmarks (schema wired; create/list UI is item F) ----
    @Upsert
    abstract suspend fun upsertBookmark(bookmark: BookmarkEntity)

    @Query("SELECT * FROM bookmarks WHERE bookKey = :bookKey ORDER BY createdAt")
    abstract fun observeBookmarks(bookKey: String): Flow<List<BookmarkEntity>>

    @Query("SELECT * FROM bookmarks WHERE bookKey = :bookKey ORDER BY createdAt")
    abstract suspend fun bookmarksForBook(bookKey: String): List<BookmarkEntity>

    // feature #132 WI-6b — all bookmarks snapshot for the backup collector (WI-8). Ordered by
    // (bookKey, createdAt) for byte-stable repeat backups.
    @Query("SELECT * FROM bookmarks ORDER BY bookKey, createdAt")
    abstract suspend fun allBookmarks(): List<BookmarkEntity>

    @Query("DELETE FROM bookmarks WHERE bookmarkId = :id")
    abstract suspend fun deleteBookmark(id: String)

    // ---- feature #135 WI-3: atomic toggle + presence on the unique (bookKey, profileKey) ----
    // insertBookmarkIfAbsent (@Insert(IGNORE)) already exists below (added by #132 WI-6b for
    // restore); the toggle REUSES it as the create primitive. The toggle DECIDES add-vs-remove by the
    // position's actual presence (findBookmarkByProfile), NOT by the insert's -1 — because -1 is
    // ambiguous (unique-index conflict OR a bookmarkId PK collision at another position).

    @Query("SELECT * FROM bookmarks WHERE bookKey = :bookKey AND profileKey = :profileKey")
    abstract suspend fun findBookmarkByProfile(bookKey: String, profileKey: String): BookmarkEntity?

    @Query("DELETE FROM bookmarks WHERE bookKey = :bookKey AND profileKey = :profileKey")
    abstract suspend fun deleteBookmarkByProfile(bookKey: String, profileKey: String): Int

    /** Presence for the top-bar toggle: is the current position bookmarked? (>0 ⇒ yes). */
    @Query("SELECT COUNT(*) FROM bookmarks WHERE bookKey = :bookKey AND profileKey = :profileKey")
    abstract suspend fun isBookmarked(bookKey: String, profileKey: String): Int

    /**
     * Atomically toggle a bookmark at the entity's `(bookKey, profileKey)` position. The outcome is
     * decided by the POSITION's actual presence, not by an insert return code: if a row already
     * occupies `(bookKey, profileKey)` → DELETE it → [BookmarkToggleResult.Removed]; else INSERT the
     * entity → [BookmarkToggleResult.Added]. Wrapped in @Transaction so a concurrent toggle can't race
     * the presence-check-vs-mutate (the highlights `upsertHighlight` transactional-toggle precedent);
     * the unique `(bookKey, profileKey)` index is the hard backstop guaranteeing at most one row per
     * position even under interleaving. The caller supplies the entity via `BookmarkRecord.toEntity()`,
     * which derives the `profileKey`.
     *
     * Deciding by position presence (not by `@Insert(IGNORE)`'s -1) closes the phantom-`Removed` class:
     * -1 can also mean a `bookmarkId` primary-key collision at a DIFFERENT position (a caller passed a
     * colliding id — vanishingly rare via `newAnnotationId()`, but the DAO is a public boundary). On the
     * `Added` branch the insert is therefore VERIFIED: if the row didn't land (an ignored PK collision at
     * a free position), the bookmark is re-keyed with a fresh id and re-inserted so `Added` is truthful
     * — never a claimed create that didn't persist. (A concurrent insert-at-the-same-position that won
     * the race between the presence check and this insert is absorbed by the unique index: the ignore is
     * then correct — the position IS occupied — so no re-key happens; the position ends up bookmarked,
     * which is the intended `Added` outcome.)
     */
    @Transaction
    open suspend fun toggleBookmark(bookmark: BookmarkEntity): com.vreader.app.annotations.BookmarkToggleResult {
        if (findBookmarkByProfile(bookmark.bookKey, bookmark.profileKey) != null) {
            deleteBookmarkByProfile(bookmark.bookKey, bookmark.profileKey)
            return com.vreader.app.annotations.BookmarkToggleResult.Removed
        }
        // Position free → add. If the insert is ignored while the position is STILL free, the -1 was a
        // bookmarkId PK collision (not a position conflict): re-key and re-insert so `Added` truly
        // persists. (Accepted Low, Gate-4 round 3: a SECOND collision on a fresh v4 UUID is a ~1-in-2^122
        // event — not a reachable branch — so the single re-key is not itself re-verified; a bounded
        // retry loop would add complexity for an unreachable path.)
        if (insertBookmarkIfAbsent(bookmark) == -1L &&
            findBookmarkByProfile(bookmark.bookKey, bookmark.profileKey) == null
        ) {
            insertBookmarkIfAbsent(bookmark.copy(bookmarkId = java.util.UUID.randomUUID().toString()))
        }
        return com.vreader.app.annotations.BookmarkToggleResult.Added
    }

    // ---- feature #132 WI-6b: UUID-preserving restore (insert-if-absent per kind) ----
    // Each insert IGNOREs on any constraint conflict (PK/unique index), returning -1. A -1 means
    // the row already exists (a repeated restore of the same UUID, or a same-anchor different-UUID
    // highlight guarded by the (profileKey, anchorKey) unique index) → idempotent no-op. The whole
    // restore runs in ONE @Transaction so a concurrent restore/create can't half-apply.

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    abstract suspend fun insertHighlightForRestore(highlight: HighlightEntity): Long

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    abstract suspend fun insertNoteIfAbsent(note: AnnotationNoteEntity): Long

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    abstract suspend fun insertBookmarkIfAbsent(bookmark: BookmarkEntity): Long

    /** Insert the pre-validated entities preserving their backed-up UUIDs + timestamps, returning
     *  the count APPLIED (freshly inserted) per kind as `Triple(highlights, notes, bookmarks)`.
     *  A row already present (UUID collision or same-anchor duplicate) is IGNOREd (not counted).
     *  Wrapped in @Transaction so a repeated/concurrent restore can't half-apply. */
    @Transaction
    open suspend fun restoreAnnotationEntities(
        highlights: List<HighlightEntity>,
        notes: List<AnnotationNoteEntity>,
        bookmarks: List<BookmarkEntity>,
    ): Triple<Int, Int, Int> {
        val h = highlights.count { insertHighlightForRestore(it) != -1L }
        val n = notes.count { insertNoteIfAbsent(it) != -1L }
        val b = bookmarks.count { insertBookmarkIfAbsent(it) != -1L }
        return Triple(h, n, b)
    }
}
