// Purpose: The cross-book search index DAO — feature #128 WI-4. Owns the FTS match queries
// (first-hit-per-book), the settled-completeness helper, the staging batch ops, and the single
// atomic staging→sections publish transaction. The repository (WI-6) is the boundary that turns
// these into observable TextHit results; the coordinator (WI-5) drives extraction → staging →
// publish. Feature #133 WI-1 additively adds the book-scoped in-book (TXT/MD) find surface
// (`matchingChunksPage` cursor page, `chunkAtOrAfter` inclusive resume, `matchingChunkCount`,
// `observeIndexState` Flow) over the SAME FTS4 tables — no schema change (DB stays v7). Views never
// touch this DAO directly (rule 50 §2).
//
// Design notes:
//  - No window functions (minSdk 26 = SQLite 3.18 has no ROW_NUMBER). First-hit-per-book is a
//    two-step query: distinct-bookKey LIMIT, then a per-book min-ordinal section (Gate-2 HIGH — one
//    heavily-matching book must not consume the whole limit and hide other books).
//  - Completeness is over SETTLED states (Gate-2 round-3 HIGH): "indexed" OR "skipped_unsupported"
//    both count; only a MISSING row or a retryable "failed" row holds completeness open.
//  - publishBook is @Transaction + bookExists-guarded (Gate-2 round-3 HIGH — a book deleted
//    mid-index no-ops the publish instead of an orphan/FK-failing insert).
package com.vreader.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import kotlinx.coroutines.flow.Flow

@Dao
abstract class SearchDao {

    // ---- staging batch ops (the bounded-memory extraction buffer; invisible to search) ----

    @Insert(onConflict = OnConflictStrategy.ABORT)
    abstract suspend fun insertStagingBatch(rows: List<SearchStagingEntity>)

    @Query("DELETE FROM search_sections_staging WHERE bookKey = :bookKey")
    abstract suspend fun clearStaging(bookKey: String)

    @Query("SELECT * FROM search_sections_staging WHERE bookKey = :bookKey ORDER BY chunkOrdinal")
    abstract suspend fun stagingFor(bookKey: String): List<SearchStagingEntity>

    // ---- published sections + index state ----

    @Query("DELETE FROM search_sections WHERE bookKey = :bookKey")
    abstract suspend fun deleteSections(bookKey: String)

    @Query("SELECT * FROM search_sections WHERE bookKey = :bookKey ORDER BY chunkOrdinal")
    abstract suspend fun sectionsFor(bookKey: String): List<SearchSectionEntity>

    /** Upsert the settled/retry state row for a book. */
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    abstract suspend fun markIndexed(state: SearchIndexStateEntity)

    @Query("SELECT * FROM search_index_state")
    abstract suspend fun indexStates(): List<SearchIndexStateEntity>

    @Query("SELECT bookKey FROM search_index_state WHERE status = 'indexed'")
    abstract suspend fun indexedBookKeys(): List<String>

    @Query("SELECT * FROM search_index_state WHERE bookKey = :bookKey")
    abstract suspend fun indexState(bookKey: String): SearchIndexStateEntity?

    /** Guard for the deletion-aware publish: has the parent book NOT been deleted mid-index? */
    @Query("SELECT EXISTS(SELECT 1 FROM books WHERE fingerprintKey = :bookKey)")
    abstract suspend fun bookExists(bookKey: String): Boolean

    // ---- completeness (settled: indexed | skipped_unsupported; unsettled: missing | failed) ----

    /**
     * The number of INDEXABLE books (format ∈ {epub,txt,md}) that lack a SETTLED index-state row —
     * i.e. no row at all, or a retryable "failed" row. `indexComplete == (this == 0)`. An "indexed"
     * or "skipped_unsupported" row is settled (does NOT count), so a no-content-service EPUB does not
     * block completeness forever; only a missing or a retrying-`failed` book keeps it open.
     */
    // NOTE: unsettled = a MISSING row OR any status that is NOT one of the two SETTLED terminals
    // (`indexed`, `skipped_unsupported`). Written as `NOT IN (…)` rather than `= 'failed'` so an
    // unexpected/typo status (`indexing`, `faild`, …) counts as unsettled and holds completeness open
    // rather than being silently treated as settled (Gate-4 Low).
    @Query(
        "SELECT COUNT(*) FROM books b " +
            "LEFT JOIN search_index_state s ON s.bookKey = b.fingerprintKey " +
            "WHERE b.originalFormat IN ('epub', 'txt', 'md') " +
            "AND (s.status IS NULL OR s.status NOT IN ('indexed', 'skipped_unsupported'))",
    )
    abstract suspend fun countUnsettledIndexable(): Int

    /** Observable form of [countUnsettledIndexable] — re-emits when books/index-state change so the
     *  UI's definitive no-results copy un-gates automatically as indexing settles. */
    @Query(
        "SELECT COUNT(*) FROM books b " +
            "LEFT JOIN search_index_state s ON s.bookKey = b.fingerprintKey " +
            "WHERE b.originalFormat IN ('epub', 'txt', 'md') " +
            "AND (s.status IS NULL OR s.status NOT IN ('indexed', 'skipped_unsupported'))",
    )
    abstract fun observeUnsettledIndexableCount(): Flow<Int>

    /** True iff every indexable book is settled (indexed | skipped_unsupported). */
    suspend fun isIndexComplete(): Boolean = countUnsettledIndexable() == 0

    /**
     * Observable count of PUBLISHED search sections — the index-generation signal the repository
     * (WI-6) flatMapLatest/combines over so a HELD query re-runs and GROWS as the coordinator publishes
     * more books mid-indexing (fix #1 — live result growth). Every `publishBook` adds rows, so this
     * Flow re-emits and the repository re-queries with the same query string.
     */
    @Query("SELECT COUNT(*) FROM search_sections")
    abstract fun observeSearchSectionsCount(): Flow<Int>

    // ---- first-hit-per-book FTS match (two-step, both minSdk-26-safe; NO window functions) ----

    /**
     * Step 1: the DISTINCT book keys with at least one FTS match, LIMITed by book count (not raw
     * rows) so one heavily-matching book can't crowd out others (Gate-2 HIGH). Ordered by bookKey for
     * deterministic paging.
     */
    @Query(
        "SELECT DISTINCT s.bookKey FROM search_sections_fts f " +
            "JOIN search_sections s ON s.id = f.rowid " +
            "WHERE search_sections_fts MATCH :ftsQuery " +
            "ORDER BY s.bookKey LIMIT :limit",
    )
    abstract suspend fun matchingBookKeys(ftsQuery: String, limit: Int): List<String>

    /**
     * Step 2: the deterministic FIRST matching section of one book — ordered by the unique
     * `(sectionIndex, chunkOrdinal, id)` tuple so ties are impossible and the "first hit" is stable
     * across runs (chunkOrdinal is unique within a book — WI-3).
     */
    @Query(
        "SELECT s.* FROM search_sections_fts f " +
            "JOIN search_sections s ON s.id = f.rowid " +
            "WHERE search_sections_fts MATCH :ftsQuery AND s.bookKey = :bookKey " +
            "ORDER BY s.sectionIndex ASC, s.chunkOrdinal ASC, s.id ASC LIMIT 1",
    )
    abstract suspend fun firstMatchingSection(bookKey: String, ftsQuery: String): SearchSectionEntity?

    /** The first hit for up to [limit] distinct matching books — one row per book (Gate-2 HIGH). */
    suspend fun firstHitsPerBook(ftsQuery: String, limit: Int = 200): List<SearchSectionEntity> =
        matchingBookKeys(ftsQuery, limit).mapNotNull { firstMatchingSection(it, ftsQuery) }

    // ---- in-book (TXT/MD) find, book-scoped + cursor-paged (feature #133 WI-1) ----

    /**
     * One PAGE of matching chunks for a single TXT/MD book, reading-order-stable and cursor-paged.
     * Returns whole [SearchSectionEntity] chunks (per-occurrence expansion happens in the repository —
     * FTS4 has no per-occurrence row). Cursor = the `(sectionIndex, chunkOrdinal, id)` of the prior
     * page's last chunk; the first page passes `(-1, -1, -1)`. The bound is a STRICT `>` on the
     * `(sectionIndex, chunkOrdinal, id)` tuple, so consecutive pages are disjoint. `s.id = f.rowid`
     * (the live join shape) MATCHes `search_sections_fts`, book-scoped by `bookKey`, ordered by the
     * unique `(sectionIndex, chunkOrdinal, id)` tuple (reading order, deterministic — FTS4 has no bm25).
     */
    @Query(
        "SELECT s.* FROM search_sections_fts f " +
            "JOIN search_sections s ON s.id = f.rowid " +
            "WHERE search_sections_fts MATCH :ftsQuery AND s.bookKey = :bookKey " +
            "AND ( s.sectionIndex > :afterSectionIndex " +
            "   OR (s.sectionIndex = :afterSectionIndex AND s.chunkOrdinal > :afterChunkOrdinal) " +
            "   OR (s.sectionIndex = :afterSectionIndex AND s.chunkOrdinal = :afterChunkOrdinal AND s.id > :afterId) ) " +
            "ORDER BY s.sectionIndex ASC, s.chunkOrdinal ASC, s.id ASC " +
            "LIMIT :limit",
    )
    abstract suspend fun matchingChunksPage(
        bookKey: String,
        ftsQuery: String,
        afterSectionIndex: Int,
        afterChunkOrdinal: Int,
        afterId: Long,
        limit: Int,
    ): List<SearchSectionEntity>

    /**
     * The current chunk INCLUSIVELY (round-3 completeness): the first matching chunk AT-OR-AFTER the
     * cursor tuple, so a partially-consumed chunk (whose `occurrenceIndex > 0` upstream) is RE-FETCHED
     * rather than skipped by [matchingChunksPage]'s strict `>`. Same MATCH/join/order shape, but `>=`
     * on the `id` leg of the `(sectionIndex, chunkOrdinal, id)` tuple, `LIMIT 1`.
     */
    @Query(
        "SELECT s.* FROM search_sections_fts f " +
            "JOIN search_sections s ON s.id = f.rowid " +
            "WHERE search_sections_fts MATCH :ftsQuery AND s.bookKey = :bookKey " +
            "AND ( s.sectionIndex > :atSectionIndex " +
            "   OR (s.sectionIndex = :atSectionIndex AND s.chunkOrdinal > :atChunkOrdinal) " +
            "   OR (s.sectionIndex = :atSectionIndex AND s.chunkOrdinal = :atChunkOrdinal AND s.id >= :atId) ) " +
            "ORDER BY s.sectionIndex ASC, s.chunkOrdinal ASC, s.id ASC LIMIT 1",
    )
    abstract suspend fun chunkAtOrAfter(
        bookKey: String,
        ftsQuery: String,
        atSectionIndex: Int,
        atChunkOrdinal: Int,
        atId: Long,
    ): SearchSectionEntity?

    /** Total matching CHUNK count for a book (the cheap aggregate; NOT a per-occurrence count). */
    @Query(
        "SELECT COUNT(*) FROM search_sections_fts f JOIN search_sections s ON s.id = f.rowid " +
            "WHERE search_sections_fts MATCH :ftsQuery AND s.bookKey = :bookKey",
    )
    abstract suspend fun matchingChunkCount(bookKey: String, ftsQuery: String): Int

    /**
     * Per-book index-state as an OBSERVABLE Flow (the existing [indexState] is one-shot) — re-emits so
     * a HELD in-book query un-gates when the current book settles. Null = MISSING (never indexed); the
     * repository distinguishes missing / indexing / failed / indexed / skipped_unsupported downstream.
     */
    @Query("SELECT * FROM search_index_state WHERE bookKey = :bookKey")
    abstract fun observeIndexState(bookKey: String): Flow<SearchIndexStateEntity?>

    // ---- the atomic staging→sections publish (Gate-2 HIGH atomicity + round-3 HIGH deletion-aware) ----

    @Query(
        "INSERT INTO search_sections (bookKey, sectionIndex, chunkOrdinal, sectionTitle, text, indexedText) " +
            "SELECT bookKey, sectionIndex, chunkOrdinal, sectionTitle, text, indexedText " +
            "FROM search_sections_staging WHERE bookKey = :bookKey ORDER BY chunkOrdinal",
    )
    abstract suspend fun copyStagingToSections(bookKey: String)

    /** Set books.author ONLY when it is currently null (mirrors [BookDao.backfillAuthorIfNull]) — a
     *  backfill never overwrites a restored/set author. Colocated here so publishBook runs it inside
     *  the same transaction (a @Dao can't call into another DAO). */
    @Query("UPDATE books SET author = :author WHERE fingerprintKey = :bookKey AND author IS NULL")
    abstract suspend fun backfillAuthorIfNull(bookKey: String, author: String)

    /**
     * Flip a book's staged extraction to searchable, atomically. Re-checks [bookExists] first: if the
     * parent book was deleted mid-index (the `collect`-not-`collectLatest` window), the FK CASCADE has
     * already removed the staging rows, so the whole publish no-ops (no orphan/FK-failing insert). Else,
     * in ONE short commit: clear any prior index → copy staging→sections (which populates the FTS shadow
     * via Room's content-table triggers) → clear staging → write the state row → (EPUB) backfill author
     * only if currently null.
     */
    @Transaction
    open suspend fun publishBook(
        bookKey: String,
        state: SearchIndexStateEntity,
        author: String? = null,
    ) {
        // The state row and the published sections MUST be for the same book — otherwise a caller
        // mistake could publish A's sections while writing B's state row (or FK-fail if B is absent)
        // (Gate-4 Medium).
        require(state.bookKey == bookKey) {
            "publishBook: state.bookKey (${state.bookKey}) must equal bookKey ($bookKey)"
        }
        if (!bookExists(bookKey)) return
        deleteSections(bookKey)
        copyStagingToSections(bookKey)
        clearStaging(bookKey)
        markIndexed(state)
        if (author != null) backfillAuthorIfNull(bookKey, author)
    }
}
