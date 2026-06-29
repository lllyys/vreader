// Purpose: Room DAO for library collections — feature #127 WI-1 (#110 Phase 3). WI-1 is the SKELETON
// (insert + basic queries, enough for the migration + entity tests); the full transactional CRUD +
// membership + count surface (CollectionRepository's seam) lands in WI-2. Mirrors the BookDao
// convention of explicit @Query SQL; the collection create uses a strict @Insert (ABORT on conflict)
// so the unique nameKey index rejects case-folded duplicates — NOT @Upsert, which would silently
// UPDATE the conflicting row.
package com.vreader.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface CollectionDao {
    /** Strict insert (default ABORT on conflict) — a duplicate `nameKey` throws, so the unique index is
     *  the SQL backstop behind the repository's transactional dedup check (WI-2). NOT `@Upsert`, which
     *  would silently UPDATE the conflicting row instead of rejecting the duplicate. */
    @Insert
    suspend fun insertCollection(collection: CollectionEntity)

    /** Idempotent membership add — a duplicate (bookKey, collectionId) is ignored (composite PK). */
    @Query(
        "INSERT OR IGNORE INTO book_collection (bookKey, collectionId) VALUES (:bookKey, :collectionId)",
    )
    suspend fun addMembership(bookKey: String, collectionId: String)

    @Query("DELETE FROM book_collection WHERE bookKey = :bookKey AND collectionId = :collectionId")
    suspend fun removeMembership(bookKey: String, collectionId: String)

    @Query("SELECT * FROM collections ORDER BY createdAt ASC")
    suspend fun getAllCollections(): List<CollectionEntity>

    @Query("SELECT * FROM collections WHERE nameKey = :nameKey LIMIT 1")
    suspend fun findByNameKey(nameKey: String): CollectionEntity?

    @Query("SELECT * FROM collections ORDER BY createdAt ASC")
    fun observeCollections(): Flow<List<CollectionEntity>>

    /** The book fingerprintKeys in a collection (reverse lookup served by the collectionId index). */
    @Query("SELECT bookKey FROM book_collection WHERE collectionId = :collectionId")
    suspend fun bookKeysInCollection(collectionId: String): List<String>
}
