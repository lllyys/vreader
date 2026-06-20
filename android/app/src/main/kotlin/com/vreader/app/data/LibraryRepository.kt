// Purpose: Library persistence boundary — feature #106 WI-3. The Android analog of
// the iOS PersistenceActor + its record DTOs: callers get value-type DTOs (Book /
// VReaderLocator), never Room entities (rule 50 §2). Maps the persisted columns to
// the shared :identity envelope types so saved positions round-trip through the
// engine-neutral contract.
package com.vreader.app.data

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import vreader.contracts.BookFormat
import vreader.contracts.VReaderLocator

/**
 * Value-type DTO for a library book (decoupled from [BookEntity], mirroring iOS
 * `BookRecord`). `fingerprintKey` is the canonical identity.
 */
data class Book(
    val fingerprintKey: String,
    val title: String,
    val originalFormat: BookFormat,
    val contentSHA256: String,
    val fileByteCount: Long,
    val localFilePath: String? = null,
    val sourceUri: String? = null,
    val addedAt: Long,
    val lastOpenedAt: Long? = null,
)

/**
 * A saved reading position paired with its book key + last-saved time — feature #116 WI-3.
 * The backup collector needs the whole [VReaderLocator] envelope plus `updatedAt`, which the
 * per-key [LibraryRepository.loadPosition] doesn't expose.
 */
data class ReadingPositionRecord(
    val fingerprintKey: String,
    val locator: VReaderLocator,
    val updatedAt: Long,
)

/**
 * The library/position persistence boundary. Suspends for writes, exposes a Flow
 * for the observable library list. `json` is injectable for tests.
 */
class LibraryRepository(
    private val bookDao: BookDao,
    private val positionDao: ReadingPositionDao,
    private val json: Json = DEFAULT_JSON,
) {
    fun observeLibrary(): Flow<List<Book>> = bookDao.observeAll().map { rows -> rows.map(::toBook) }

    /** One-shot snapshot of the library — feature #116 WI-3 backup collector (not the Flow). */
    suspend fun listBooks(): List<Book> = bookDao.getAll().map(::toBook)

    /** Every saved reading position as a record (envelope + updatedAt) — feature #116 WI-3. */
    suspend fun listPositions(): List<ReadingPositionRecord> =
        positionDao.getAll().map { e ->
            ReadingPositionRecord(e.fingerprintKey, e.toEnvelope(json), e.updatedAt)
        }

    suspend fun upsertBook(book: Book) = bookDao.upsert(book.toEntity())

    suspend fun findBook(fingerprintKey: String): Book? = bookDao.find(fingerprintKey)?.let(::toBook)

    suspend fun deleteBook(fingerprintKey: String) = bookDao.delete(fingerprintKey)

    suspend fun markOpened(fingerprintKey: String, openedAt: Long) =
        bookDao.markOpened(fingerprintKey, openedAt)

    /**
     * Persists the full [VReaderLocator] envelope as the book's current position.
     * Repairs a non-finite progression (iOS persistence-boundary parity) and REJECTS
     * a structurally-invalid legacy locator (negative page/offset, inverted range) —
     * an invalid position must never reach storage (Gate-4 High).
     */
    suspend fun savePosition(locator: VReaderLocator, updatedAt: Long) {
        val repaired = locator.repaired()
        repaired.legacyLocator?.validate()?.let { error ->
            throw IllegalArgumentException("cannot persist invalid locator: $error")
        }
        positionDao.upsert(repaired.toEntity(updatedAt, json))
    }

    /** Loads the saved position envelope, or null if none. */
    suspend fun loadPosition(fingerprintKey: String): VReaderLocator? =
        positionDao.find(fingerprintKey)?.toEnvelope(json)

    suspend fun clearPosition(fingerprintKey: String) = positionDao.delete(fingerprintKey)

    // MARK: - Mapping (entity <-> DTO)

    private fun toBook(e: BookEntity): Book = Book(
        fingerprintKey = e.fingerprintKey,
        title = e.title,
        originalFormat = BookFormat.valueOf(e.originalFormat),
        contentSHA256 = e.contentSHA256,
        fileByteCount = e.fileByteCount,
        localFilePath = e.localFilePath,
        sourceUri = e.sourceUri,
        addedAt = e.addedAt,
        lastOpenedAt = e.lastOpenedAt,
    )

    private fun Book.toEntity(): BookEntity = BookEntity(
        fingerprintKey = fingerprintKey,
        title = title,
        originalFormat = originalFormat.name,
        contentSHA256 = contentSHA256,
        fileByteCount = fileByteCount,
        localFilePath = localFilePath,
        sourceUri = sourceUri,
        addedAt = addedAt,
        lastOpenedAt = lastOpenedAt,
    )

    /** Nulls a non-finite progression in the legacy locator before storage. */
    private fun VReaderLocator.repaired(): VReaderLocator =
        legacyLocator?.let { copy(legacyLocator = it.repairedForCanonicalization()) } ?: this

    private fun VReaderLocator.toEntity(updatedAt: Long, json: Json): ReadingPositionEntity =
        ReadingPositionEntity(
            fingerprintKey = fingerprintKey,
            vreaderLocatorJSON = json.encodeToString(this),   // the WHOLE envelope
            canonicalHash = canonicalHash,
            updatedAt = updatedAt,
        )

    private fun ReadingPositionEntity.toEnvelope(json: Json): VReaderLocator =
        json.decodeFromString<VReaderLocator>(vreaderLocatorJSON)

    companion object {
        // encodeDefaults so schemaVersion is always serialized; ignoreUnknownKeys so a
        // newer app's extra envelope field decodes cleanly on an older build (forward
        // compat — the whole point of storing the envelope JSON, not flat columns).
        private val DEFAULT_JSON = Json {
            encodeDefaults = true
            ignoreUnknownKeys = true
        }
    }
}
