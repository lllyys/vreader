// Purpose: Room DAO for library collections — feature #127 WI-2 (#110 Phase 3). The full transactional
// CRUD + membership + count surface behind CollectionRepository (rule 50 §2). An `abstract class` (not
// an interface) so the create/rename dedup can run as a @Transaction method calling the abstract
// queries (the AnnotationDao precedent). The create uses a strict @Insert so the unique nameKey index
// is the SQL backstop; the @Transaction check-then-insert is the primary dedup.
package com.vreader.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.Transaction
import kotlinx.coroutines.flow.Flow

/** A collection + its membership count (the LEFT-JOIN projection for the shelf-bar). */
data class CollectionWithCount(val id: String, val name: String, val createdAt: Long, val bookCount: Int)

/** Outcome of the transactional rename (so the repository maps it to a typed result). */
enum class RenameOutcome { Ok, Duplicate, NotFound }

@Dao
abstract class CollectionDao {

    @Insert
    abstract suspend fun insertCollection(collection: CollectionEntity)

    @Query("UPDATE collections SET name = :name, nameKey = :nameKey WHERE id = :id")
    abstract suspend fun updateName(id: String, name: String, nameKey: String): Int

    @Query("DELETE FROM collections WHERE id = :id")
    abstract suspend fun deleteCollection(id: String): Int

    @Query("SELECT * FROM collections WHERE nameKey = :nameKey LIMIT 1")
    abstract suspend fun findByNameKey(nameKey: String): CollectionEntity?

    @Query("SELECT EXISTS(SELECT 1 FROM collections WHERE id = :id)")
    abstract suspend fun existsById(id: String): Boolean

    @Query("SELECT * FROM collections ORDER BY createdAt ASC")
    abstract suspend fun getAllCollections(): List<CollectionEntity>

    @Query("SELECT * FROM collections ORDER BY createdAt ASC")
    abstract fun observeCollections(): Flow<List<CollectionEntity>>

    /** Each collection + its book count (empty collections show 0 via the LEFT JOIN), oldest first. */
    @Query(
        "SELECT c.id AS id, c.name AS name, c.createdAt AS createdAt, COUNT(bc.bookKey) AS bookCount " +
            "FROM collections c LEFT JOIN book_collection bc ON bc.collectionId = c.id " +
            "GROUP BY c.id ORDER BY c.createdAt ASC",
    )
    abstract fun observeCollectionsWithCount(): Flow<List<CollectionWithCount>>

    // --- membership ---

    /** Idempotent membership add — a duplicate (bookKey, collectionId) is ignored (composite PK). */
    @Query("INSERT OR IGNORE INTO book_collection (bookKey, collectionId) VALUES (:bookKey, :collectionId)")
    abstract suspend fun addMembership(bookKey: String, collectionId: String)

    @Query("DELETE FROM book_collection WHERE bookKey = :bookKey AND collectionId = :collectionId")
    abstract suspend fun removeMembership(bookKey: String, collectionId: String)

    @Query("SELECT bookKey FROM book_collection WHERE collectionId = :collectionId")
    abstract suspend fun bookKeysInCollection(collectionId: String): List<String>

    /** The book fingerprintKeys in a collection (reverse lookup, served by the collectionId index). */
    @Query("SELECT bookKey FROM book_collection WHERE collectionId = :collectionId")
    abstract fun observeBooksInCollection(collectionId: String): Flow<List<String>>

    @Query("SELECT collectionId FROM book_collection WHERE bookKey = :bookKey")
    abstract fun observeCollectionIdsForBook(bookKey: String): Flow<List<String>>

    // --- transactional dedup (check-then-write atomically) ---

    /** Atomic create-if-absent: inserts only when [nameKey] is free. Returns false on a duplicate. */
    @Transaction
    open suspend fun createIfAbsent(collection: CollectionEntity): Boolean {
        if (findByNameKey(collection.nameKey) != null) return false
        insertCollection(collection)
        return true
    }

    /** Atomic rename: NotFound if [id] is gone (checked FIRST), else Duplicate if the name is taken by
     *  ANOTHER collection, else update. The order matters — a gone id must report NotFound even when the
     *  target name exists elsewhere (Gate-4 WI-2 Medium). */
    @Transaction
    open suspend fun renameIfAbsent(id: String, name: String, nameKey: String): RenameOutcome {
        if (!existsById(id)) return RenameOutcome.NotFound
        val existing = findByNameKey(nameKey)
        if (existing != null && existing.id != id) return RenameOutcome.Duplicate
        updateName(id, name, nameKey)
        return RenameOutcome.Ok
    }
}
