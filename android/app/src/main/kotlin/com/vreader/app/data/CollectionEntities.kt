// Purpose: Room entities for user library collections — feature #127 WI-1 (#110 Phase 3).
// A collection is the Android mirror of the iOS `BookCollection` @Model + the shared backup contract
// `BackupCollection { name, createdAt, bookFingerprintKeys }`. The cross-platform IDENTITY is
// name + createdAt + membership; `id` here is an internal UUID PK (FK efficiency), NOT part of the
// backup identity (restore merges by `nameKey`, never by id, since ids differ across devices).
// `nameKey` = name.trim().lowercase(Locale.ROOT) — the locale-invariant case-insensitive unique key
// (iOS rejects duplicates case-insensitively). Membership is a many-to-many to `books` by fingerprintKey.
package com.vreader.app.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

/** A user collection. `nameKey` is the normalized case-insensitive unique key; `id` is internal-only. */
@Entity(
    tableName = "collections",
    indices = [Index(value = ["nameKey"], unique = true)],
)
data class CollectionEntity(
    @PrimaryKey val id: String,   // UUID string — internal PK, NOT the backup identity (name+createdAt is)
    val name: String,             // the display name (trimmed, ≤100 chars — enforced in the repository)
    val nameKey: String,          // name.trim().lowercase(Locale.ROOT) — locale-invariant unique key
    val createdAt: Long,          // epoch millis — part of the cross-platform identity
)

/**
 * The book↔collection membership join. Composite PK `(bookKey, collectionId)` (so a book can't be in the
 * same collection twice). Both FKs CASCADE: deleting a book OR a collection removes the membership row,
 * never the other parent. The composite PK indexes `bookKey` first; the explicit `collectionId` index
 * serves the reverse lookup ("books in collection X").
 */
@Entity(
    tableName = "book_collection",
    primaryKeys = ["bookKey", "collectionId"],
    foreignKeys = [
        ForeignKey(
            entity = BookEntity::class,
            parentColumns = ["fingerprintKey"],
            childColumns = ["bookKey"],
            onDelete = ForeignKey.CASCADE,
        ),
        ForeignKey(
            entity = CollectionEntity::class,
            parentColumns = ["id"],
            childColumns = ["collectionId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("collectionId")],
)
data class BookCollectionCrossRef(
    val bookKey: String,        // fingerprintKey (FK → books)
    val collectionId: String,   // CollectionEntity.id (FK → collections)
)
