// Purpose: Room entities for the Android library — feature #106 WI-3.
// BookEntity is the Android mirror of the iOS Book @Model; ReadingPositionEntity
// stores the VReaderLocator ENVELOPE (engine + readiumLocatorJSON + serialized
// canonical Locator), NOT a bare Locator (Gate-2 Critical) — so a saved position
// survives an engine swap / cross-device restore.
package com.vreader.app.data

import androidx.room.Entity
import androidx.room.ForeignKey
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
