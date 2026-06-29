// Purpose: feature #127 WI-2 — the collection repository (the DTO boundary over CollectionDao;
// rule 50 §2). Process-singleton in AppContainer (the #122/#123 repository precedent). Owns the name
// normalization (trim → reject empty → truncate to 100 chars, iOS parity: iOS truncates, no length
// error) + the locale-invariant case-insensitive uniqueness (`nameKey` = name.lowercase(Locale.ROOT)),
// delegating the atomic check-then-write to the DAO's @Transaction methods. The cross-platform IDENTITY
// is name + createdAt (the `BackupCollection` contract); `id` is an internal UUID.
package com.vreader.app.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.text.BreakIterator
import java.util.Locale
import java.util.UUID

/** A collection as the library renders it (the design's shelf chip + its book count). */
data class Collection(val id: String, val name: String, val createdAt: Long, val bookCount: Int)

/** Why a collection create/rename was rejected (mirrors iOS `CollectionError`). */
enum class CollectionError { EmptyName, DuplicateName, NotFound }

/** The failure carried by a rejected [CollectionRepository] op's [Result]. */
class CollectionException(val error: CollectionError) : Exception(error.name)

class CollectionRepository(
    private val dao: CollectionDao,
    private val now: () -> Long = { System.currentTimeMillis() },
    private val newId: () -> String = { UUID.randomUUID().toString() },
) {
    fun observeCollections(): Flow<List<Collection>> =
        dao.observeCollectionsWithCount().map { rows ->
            rows.map { Collection(it.id, it.name, it.createdAt, it.bookCount) }
        }

    fun observeBookKeysInCollection(collectionId: String): Flow<List<String>> =
        dao.observeBooksInCollection(collectionId)

    fun observeCollectionIdsForBook(bookKey: String): Flow<List<String>> =
        dao.observeCollectionIdsForBook(bookKey)

    /** Create a collection; rejects empty / duplicate (case-insensitive) names; truncates to 100 chars. */
    suspend fun createCollection(rawName: String): Result<Collection> {
        val name = normalize(rawName) ?: return fail(CollectionError.EmptyName)
        val entity = CollectionEntity(id = newId(), name = name, nameKey = nameKey(name), createdAt = now())
        return if (dao.createIfAbsent(entity)) {
            Result.success(Collection(entity.id, entity.name, entity.createdAt, bookCount = 0))
        } else {
            fail(CollectionError.DuplicateName)
        }
    }

    /** Rename a collection; rejects empty / a name taken by ANOTHER collection; NotFound if gone. */
    suspend fun rename(id: String, rawName: String): Result<Unit> {
        val name = normalize(rawName) ?: return fail(CollectionError.EmptyName)
        return when (dao.renameIfAbsent(id, name, nameKey(name))) {
            RenameOutcome.Ok -> Result.success(Unit)
            RenameOutcome.Duplicate -> fail(CollectionError.DuplicateName)
            RenameOutcome.NotFound -> fail(CollectionError.NotFound)
        }
    }

    /** Delete a collection (idempotent — deleting a gone collection is a no-op; FK CASCADEs the join). */
    suspend fun delete(id: String) { dao.deleteCollection(id) }

    suspend fun assign(bookKey: String, collectionId: String) = dao.addMembership(bookKey, collectionId)
    suspend fun unassign(bookKey: String, collectionId: String) = dao.removeMembership(bookKey, collectionId)

    /** Trim → null if empty (→ EmptyName) → truncate to [MAX_NAME] GRAPHEME CLUSTERS (iOS `prefix(100)`
     *  counts Swift `Character`s = extended grapheme clusters, so a 101-emoji name keeps 100 emoji, not
     *  50 UTF-16-code-unit halves — Gate-4 WI-2 Medium). */
    private fun normalize(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        return truncateToGraphemes(trimmed, MAX_NAME)
    }

    /** The first [max] grapheme clusters of [s] (the whole string if it has fewer). */
    private fun truncateToGraphemes(s: String, max: Int): String {
        val bi = BreakIterator.getCharacterInstance()
        bi.setText(s)
        var boundary = bi.first()
        var count = 0
        while (count < max) {
            val next = bi.next()
            if (next == BreakIterator.DONE) return s   // fewer than [max] graphemes — nothing to cut
            boundary = next
            count++
        }
        return s.substring(0, boundary)
    }

    /** Locale-invariant lowercasing — Turkish-I / CJK normalize consistently across devices. */
    private fun nameKey(name: String): String = name.lowercase(Locale.ROOT)

    private fun <T> fail(error: CollectionError): Result<T> = Result.failure(CollectionException(error))

    companion object {
        const val MAX_NAME = 100
    }
}
