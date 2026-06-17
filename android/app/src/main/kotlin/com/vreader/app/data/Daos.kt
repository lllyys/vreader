// Purpose: Room DAOs — the Android analog of the iOS PersistenceActor CRUD
// extensions (feature #106 WI-3). DAOs expose suspend writes + Flow reads; Room
// serializes access off the main thread. Views never touch a DAO directly — the
// repository (DTOs) is the boundary (rule 50 §2: never return @Model/entity types
// across the layer).
package com.vreader.app.data

import androidx.room.Dao
import androidx.room.Query
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

    @Query("DELETE FROM reading_positions WHERE fingerprintKey = :key")
    suspend fun delete(key: String)
}
