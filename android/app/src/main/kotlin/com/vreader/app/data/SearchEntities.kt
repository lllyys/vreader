// Purpose: Room entities for the cross-book library search index — feature #128 WI-4.
// All four tables live in the SINGLE vreader.db (Gate-2 round-2 CRITICAL — SQLite forbids a
// cross-schema FK, and a Room @Transaction spans exactly one DB instance; the atomic
// staging→sections publish + the completeness join both need one database).
//
// The pipeline:
//   1. The coordinator (WI-5) STREAMS extracted sections into [SearchStagingEntity] in bounded
//      batches (invisible to search — not in an FTS content table).
//   2. A single short @Transaction (SearchDao.publishBook) copies staging→[SearchSectionEntity]
//      (which populates [SearchSectionFtsEntity] via Room's content-table triggers), clears
//      staging, writes the [SearchIndexStateEntity] row, and backfills books.author.
//
// FK→books ON DELETE CASCADE on search_sections, search_index_state, AND search_sections_staging
// (all legal in one schema) makes a book delete clean all four tables. The staging FK is load-bearing
// (Gate-2 round-3 HIGH): with `collect` (not `collectLatest`), a book deleted mid-index leaves the
// in-flight extraction running; the CASCADE removes its staging rows so the deletion-aware publish
// no-ops instead of hitting a double FK-constraint failure.
package com.vreader.app.data

import androidx.room.Entity
import androidx.room.Fts4
import androidx.room.FtsOptions
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * One indexed section (or ~4 KB chunk of a long section) of a book. The FTS-searchable
 * [indexedText] is the normalized form (NFKC + full case fold + diacritic fold + CJK per-char
 * segmentation, produced by [com.vreader.app.search.SearchTextNormalizer]); [text] is the RAW display
 * text the snippet builder highlights. `chunkOrdinal` is a UNIQUE monotonic ordinal within a book
 * (WI-3 chunk identity), so the first-hit-per-book query's `(sectionIndex, chunkOrdinal, id)` order
 * has no ties. FK→books ON DELETE CASCADE.
 */
@Entity(
    tableName = "search_sections",
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["fingerprintKey"],
            childColumns = ["bookKey"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("bookKey")],
)
data class SearchSectionEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val bookKey: String,
    val sectionIndex: Int,       // per-book reading-order/section index (chapter attribution + tie-break)
    val chunkOrdinal: Int,       // UNIQUE monotonic ordinal within (bookKey) — deterministic first-hit tie-break
    val sectionTitle: String?,   // chapter label for the snippet attribution; null for TXT/MD
    val text: String,            // RAW display text (snippet source)
    val indexedText: String,     // normalized: NFKC + full case fold + diacritic fold + CJK per-char segmented (FTS column)
)

/**
 * The FTS4 shadow of [SearchSectionEntity] over its normalized [indexedText] column, using the
 * unicode61 tokenizer (CJK is pre-segmented per-char, so we never depend on an ICU tokenizer being
 * present — Gate-2 rejected-alternative #1). Room generates the content-table (`content=…`) DDL +
 * the INSERT/UPDATE/DELETE sync triggers, so writing a [SearchSectionEntity] row makes it MATCHable
 * automatically; `search_sections_fts.rowid` == `search_sections.id`.
 */
@Fts4(contentEntity = SearchSectionEntity::class, tokenizer = FtsOptions.TOKENIZER_UNICODE61)
@Entity(tableName = "search_sections_fts")
data class SearchSectionFtsEntity(val indexedText: String)

/**
 * Which books are indexed, at which extractor version, and whether indexing SETTLED — the
 * backfill/diff seam + the completeness source of truth. FK→books ON DELETE CASCADE.
 *
 * `status` semantics (see plan §1 completeness):
 *  - SETTLED (counts toward completeness): "indexed" (has text) OR "skipped_unsupported" (terminal,
 *    honestly metadata-only — e.g. a no-content-service EPUB).
 *  - NON-SETTLED (holds completeness open): a MISSING row (unvisited) or "failed" (a RETRY marker,
 *    still eligible for reindex — NOT a suppress-forever sentinel).
 */
@Entity(
    tableName = "search_index_state",
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["fingerprintKey"],
            childColumns = ["bookKey"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
)
data class SearchIndexStateEntity(
    @PrimaryKey val bookKey: String,
    val indexerVersion: Int,
    val indexedAt: Long,
    val status: String,   // "indexed" | "skipped_unsupported" | "failed"
)

/**
 * The bounded-memory extraction buffer (Gate-2 round-2 HIGH — genuine streaming for EPUB). The
 * coordinator flushes batches of extracted sections here, then the short publish transaction swaps
 * them into [SearchSectionEntity]. Staging rows are NEVER in an FTS content table, so they are
 * invisible to search until published. FK→books ON DELETE CASCADE (Gate-2 round-3 HIGH — a book
 * deleted mid-index cascades its in-flight staging rows away).
 */
@Entity(
    tableName = "search_sections_staging",
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["fingerprintKey"],
            childColumns = ["bookKey"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("bookKey")],
)
data class SearchStagingEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val bookKey: String,
    val sectionIndex: Int,
    val chunkOrdinal: Int,
    val sectionTitle: String?,
    val text: String,
    val indexedText: String,
)
