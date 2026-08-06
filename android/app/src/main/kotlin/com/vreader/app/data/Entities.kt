// Purpose: Room entities for the Android library — feature #106 WI-3.
// BookEntity is the Android mirror of the iOS Book @Model; ReadingPositionEntity
// stores the VReaderLocator ENVELOPE (engine + readiumLocatorJSON + serialized
// canonical Locator), NOT a bare Locator (Gate-2 Critical) — so a saved position
// survives an engine swap / cross-device restore.
package com.vreader.app.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * A book in the Android library, keyed by its canonical fingerprint
 * (`DocumentFingerprint.canonicalKey`). `localFilePath`/`sourceUri` are nullable
 * until WI-4 wires SAF import → app-private-storage copy. `lastOpenedAt` is the
 * v2 schema addition (recents) — null until first open. `author` is the v6 addition
 * (feature #128 library search) — nullable, set by an author backfill or a restore,
 * NEVER by the SAF import path (a duplicate import must not null-clobber it: the import
 * path goes through [BookDao.upsertPreservingAuthor], not the whole-row `@Upsert`).
 *
 * `coverPath` + `coverExtractorVersion` are the v10 addition (feature #152 cover extraction) and
 * carry the SAME no-clobber contract as `author`: both are excluded from
 * [BookDao.updateImportedColumns], so a duplicate import cannot erase a cover pointer.
 *
 * The two columns together are a tri-state, and BOTH are needed — `coverPath` alone cannot
 * distinguish "no cover yet" from "already looked, this book has none", so a one-column design
 * re-parses every art-less book on every app start. `coverExtractorVersion` is that memo, modelled
 * on [SearchIndexStateEntity.indexerVersion]:
 *
 * | `coverExtractorVersion` | `coverPath` | meaning |
 * |---|---|---|
 * | `null` | `null` | never attempted, or a transient access failure — eligible, retry |
 * | current | `null` | attempted; this book genuinely carries no art — skip |
 * | current | set | have art |
 * | < current | either | the parser improved — re-attempt |
 *
 * `coverPath` exists for REACTIVITY, not lookup (the path is derivable from the key): the library
 * grid is driven by [BookDao.observeAll], and extraction finishes after the row insert, so without a
 * column write there is no signal to repaint.
 */
@Entity(tableName = "books")
data class BookEntity(
    @PrimaryKey val fingerprintKey: String,
    val title: String,
    val originalFormat: String,   // BookFormat raw value (epub/pdf/txt/md/azw3)
    val contentSHA256: String,
    val fileByteCount: Long,
    val localFilePath: String?,   // app-private storage path (set at import, WI-4)
    val sourceUri: String?,       // SAF source URI metadata (WI-4)
    val addedAt: Long,            // epoch millis
    val lastOpenedAt: Long?,      // v2 addition — epoch millis of last open, or null
    val author: String? = null,   // v6 addition (feature #128) — nullable; tail default so no positional site breaks
    // v10 additions (feature #152) — tail defaults, the `author` pattern; see the tri-state table above.
    val coverPath: String? = null,          // absolute path to the extracted cover file, or null
    val coverExtractorVersion: Int? = null, // stamped only on a DEFINITE outcome (art or no-art)
)

/**
 * The persisted reading position for a book — the WHOLE [VReaderLocator] envelope
 * serialized into a single `vreaderLocatorJSON` column (one position per book; PK =
 * fingerprintKey). Storing the entire envelope (not flattened columns) is the
 * iOS-parity contract: a new envelope field gated by its own `schemaVersion` evolves
 * WITHOUT a Room schema change (Gate-4 Medium — the iOS analog persists the envelope
 * as one `Data?` blob on `ReadingPosition`). `canonicalHash` is the only derived
 * column, kept for dedup/sync lookups. `fingerprintKey` is both PK and the FK child
 * column, so it is already indexed — no separate index needed.
 */
@Entity(
    tableName = "reading_positions",
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["fingerprintKey"],
            childColumns = ["fingerprintKey"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
)
data class ReadingPositionEntity(
    @PrimaryKey val fingerprintKey: String,
    val vreaderLocatorJSON: String,   // the FULL serialized VReaderLocator envelope
    val canonicalHash: String,        // derived dedup/sync key (locally deterministic)
    val updatedAt: Long,              // epoch millis of last save
)

/**
 * Per-day, per-book reading minutes — feature #122 (reading-stats). PK is the composite
 * `(date, bookKey)`; `date` is the LOCAL `yyyy-MM-dd`. Deliberately has NO ForeignKey to `books`:
 * stats for a since-deleted book are PRESERVED as orphans (they still count toward window totals; the
 * per-book dashboard table joins live titles and omits orphans). An `@Index("bookKey")` supports the
 * per-book aggregate.
 */
@Entity(tableName = "daily_reading", primaryKeys = ["date", "bookKey"], indices = [Index("bookKey")])
data class DailyReadingEntity(
    val date: String,      // yyyy-MM-dd (local)
    val bookKey: String,   // fingerprintKey
    val minutes: Int,
)

/**
 * A text highlight — feature #123 (EPUB highlights & notes). Mirrors the iOS `Highlight` @Model.
 * `locatorJSON` stores the FULL round-trippable `vreader.contracts.Locator` (the data-class JSON — a
 * PLAIN `Locator`, NEVER a `VReaderLocator` envelope or Readium JSON), the position-precedent of
 * keeping the round-trippable form in Room. **The on-wire `BackupHighlight.locatorJSON` is the SAME
 * plain form** — `AnnotationBackupMapper` emits `BackupJson.encode(locator)`, NOT `canonicalJson()`
 * (iOS parity; `contracts/identity/backup-format.md`). `canonicalJson()` appears below only as the
 * `profileKey` HASHING input; it is never a wire format. The engine-precise anchor (Readium CFI / TXT
 * range) lives ONLY in
 * `anchorJSON`. Dedupe is on the unique `(profileKey, anchorKey)` — `profileKey =
 * "$bookKey:${sha256(locator.canonicalJson())}"` (derived from the CANONICAL form so dedup is
 * cross-platform-stable regardless of the stored round-trip form), `anchorKey` is the NON-NULL
 * `anchorHash ?: "__nil_anchor__"` sentinel (SQLite treats NULLs as distinct in a unique index, so a
 * nullable column would let repeated null-anchor highlights bypass dedupe — the sentinel collapses
 * them per `profileKey`, matching iOS's nil-anchor-by-profileKey dedupe).
 */
@Entity(
    tableName = "highlights",
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["fingerprintKey"],
            childColumns = ["bookKey"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("bookKey"), Index(value = ["profileKey", "anchorKey"], unique = true)],
)
data class HighlightEntity(
    @PrimaryKey val highlightId: String,   // UUID string (iOS `highlightId: UUID` parity)
    val bookKey: String,                   // fingerprintKey (FK)
    val profileKey: String,                // "$bookKey:${locator.canonicalHash}"
    val anchorKey: String,                 // anchorHash ?: "__nil_anchor__" (non-null dedupe key)
    val color: String,                     // AnnotationColor.key (yellow/green/blue/pink/red) or hex
    val selectedText: String,
    val note: String?,                     // optional inline note on the highlight
    val locatorJSON: String,               // full round-trippable plain Locator JSON — the backup wire uses the SAME plain form
    val anchorJSON: String?,               // serialized AnnotationAnchor (engine-precise)
    val createdAt: Long,
    val updatedAt: Long,
)

/**
 * A standalone note — feature #123. Mirrors the iOS `AnnotationNote` @Model (the design's
 * "STANDALONE" card). Same `locatorJSON` (full round-trippable plain Locator — the backup wire uses
 * that SAME plain form, never `canonicalJson()`) + `anchorJSON` (precise) contract as
 * [HighlightEntity]. No range-dedupe (a reader may keep several notes at one spot).
 */
@Entity(
    tableName = "annotation_notes",
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
data class AnnotationNoteEntity(
    @PrimaryKey val noteId: String,
    val bookKey: String,
    val profileKey: String,
    val content: String,
    val locatorJSON: String,
    val anchorJSON: String?,
    val createdAt: Long,
    val updatedAt: Long,
)

/**
 * A bookmark — feature #123 (schema) + #135 (create/toggle/list). Mirrors the iOS `Bookmark` @Model.
 * `title` is the optional user/chapter label. The composite UNIQUE `(bookKey, profileKey)` index
 * (feature #135 WI-3) makes re-bookmarking the SAME position idempotent — the atomic toggle's
 * enforcer (`AnnotationDao.toggleBookmark` reuses `insertBookmarkIfAbsent` on this index, mirroring
 * the highlights `(profileKey, anchorKey)` dedupe precedent). `profileKey =
 * "$bookKey:${sha256(locator.canonicalJson())}"` already encodes the book; `bookKey` leads the index
 * so per-book presence/delete lookups (`isBookmarked`/`deleteBookmarkByProfile`) hit the index and
 * bug #356-style corrupt keys can't collide across books.
 */
@Entity(
    tableName = "bookmarks",
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["fingerprintKey"],
            childColumns = ["bookKey"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("bookKey"), Index(value = ["bookKey", "profileKey"], unique = true)],
)
data class BookmarkEntity(
    @PrimaryKey val bookmarkId: String,
    val bookKey: String,
    val profileKey: String,
    val title: String?,
    val locatorJSON: String,
    val createdAt: Long,
    val updatedAt: Long,
)
