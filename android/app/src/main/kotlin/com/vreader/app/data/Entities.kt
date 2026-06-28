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
 * v2 schema addition (recents) — null until first open.
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
 * `locatorJSON` is the canonical `vreader.contracts.Locator.canonicalJson()` (NOT a `VReaderLocator`
 * envelope or Readium JSON — the #113 backup contract requires plain `Locator`); the engine-precise
 * anchor (Readium CFI / TXT range) lives ONLY in `anchorJSON`. Dedupe is on the unique
 * `(profileKey, anchorKey)` — `profileKey = "$bookKey:${locator.canonicalHash}"`, `anchorKey` is the
 * NON-NULL `anchorHash ?: "__nil_anchor__"` sentinel (SQLite treats NULLs as distinct in a unique
 * index, so a nullable column would let repeated null-anchor highlights bypass dedupe — the sentinel
 * collapses them per `profileKey`, matching iOS's nil-anchor-by-profileKey dedupe).
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
    val locatorJSON: String,               // canonical Locator.canonicalJson()
    val anchorJSON: String?,               // serialized AnnotationAnchor (engine-precise)
    val createdAt: Long,
    val updatedAt: Long,
)

/**
 * A standalone note — feature #123. Mirrors the iOS `AnnotationNote` @Model (the design's
 * "STANDALONE" card). Same `locatorJSON` (canonical) + `anchorJSON` (precise) contract as
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
 * A bookmark — feature #123 (schema only; the create/list UI is item F, which owns the reader
 * chrome entry). Mirrors the iOS `Bookmark` @Model. `title` is the optional user/chapter label.
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
    indices = [Index("bookKey")],
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
