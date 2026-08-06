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
    val author: String? = null,   // v6 (feature #128) — nullable; set by backfill/restore, never SAF import
    // v10 (feature #152) — the cover-state pair; written ONLY via [LibraryRepository.setCoverState],
    // never by an import DTO (the importer knows nothing about covers). See [BookEntity] for the
    // tri-state these two encode.
    val coverPath: String? = null,
    val coverExtractorVersion: Int? = null,
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

    /**
     * The SAF import path's upsert (feature #128 WI-1). On a duplicate import it updates only the
     * import-owned columns and leaves `author` (and `lastOpenedAt`) untouched — so a backfilled author
     * survives a re-import (Gate-2 Critical). A first import inserts the fresh (author-null) row.
     */
    suspend fun upsertBookPreservingAuthor(book: Book) = bookDao.upsertPreservingAuthor(book.toEntity())

    /**
     * Restore-path metadata apply (built here; wired by WI-2's RestoreImporter). Applies the manifest's
     * title/addedAt/lastOpenedAt and COALESCEs the author: a non-null [manifestAuthor] wins, a null one
     * preserves whatever author the coordinator backfilled onto the just-imported row.
     */
    suspend fun applyRestoredMetadata(
        key: String,
        title: String,
        addedAt: Long,
        lastOpenedAt: Long?,
        manifestAuthor: String?,
    ) = bookDao.applyRestoredMetadata(key, title, addedAt, lastOpenedAt, manifestAuthor)

    /**
     * Records a DEFINITE cover-extraction outcome (feature #152 WI-2): art was found at [coverPath].
     *
     * These three calls are deliberately separate rather than one nullable pair — see [BookDao] for
     * why — and are deliberately NOT folded into [upsertBookPreservingAuthor]: cover state is owned by
     * the extraction pipeline, not by an import, which is exactly why the import's UPDATE excludes
     * these columns. An extraction that FAILED to access the file calls none of them.
     */
    suspend fun setCoverArt(fingerprintKey: String, coverPath: String, extractorVersion: Int) =
        bookDao.setCoverArt(fingerprintKey, coverPath, extractorVersion)

    /** Records the other definite outcome: this book carries no art. Stamps the version so the
     *  backfill stops re-parsing it. */
    suspend fun setCoverAbsent(fingerprintKey: String, extractorVersion: Int) =
        bookDao.setCoverAbsent(fingerprintKey, extractorVersion)

    /** Makes the book eligible for extraction again (both columns NULL). */
    suspend fun clearCoverState(fingerprintKey: String) = bookDao.clearCoverState(fingerprintKey)

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
        author = e.author,
        coverPath = e.coverPath,
        coverExtractorVersion = e.coverExtractorVersion,
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
        author = author,
        // Mapped so the DTO⇄entity round-trip is lossless. This does NOT make an import able to write
        // cover state: the import path's UPDATE (updateImportedColumns) ignores these columns, and the
        // only caller that writes a whole row is the deliberate whole-row [upsertBook].
        coverPath = coverPath,
        coverExtractorVersion = coverExtractorVersion,
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
