// Purpose: feature #116 WI-3 (#110 Phase 3) — collects the Room library + saved positions into
// the #113 contract DTOs for a backup: the library-manifest (each book → its content-addressed
// blob path) + the positions section, plus the list of book blobs the WebDavBackupService (WI-5)
// must upload to the shared blob store. Mirrors the iOS BackupDataCollector / WebDAVProvider
// collect step. v1 backs up books + positions; the iOS-only sections (annotations/settings/…)
// are valid-empty (absent), which an iOS restore tolerates.
package com.vreader.app.backup

import com.vreader.app.backup.archive.BackupArchiveEntries
import com.vreader.app.backup.archive.BlobPath
import com.vreader.app.data.Book
import com.vreader.app.data.LibraryRepository
import vreader.contracts.BookFormat
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupLibraryEntry
import vreader.contracts.backup.BackupLibraryManifestEnvelope
import vreader.contracts.backup.BackupMetadata
import vreader.contracts.backup.BackupPosition
import vreader.contracts.backup.BackupPositionsEnvelope
import vreader.contracts.backup.BackupSchema
import java.io.File
import java.time.Instant

/** One book blob to publish to the shared blob store (WI-5 drives the actual atomic PUT). */
data class BlobUpload(
    val blobPath: String,
    val localFilePath: String,
    val format: BookFormat,
    val sha256: String,
    val byteCount: Long,
)

/** The collected backup: the ZIP content (metadata + manifest + section JSONs, NO book bytes) plus
 *  the blobs to upload separately. WI-5's service writes the ZIP via [BackupArchiveWriter] and
 *  uploads the [blobs]. */
data class CollectedBackup(
    val metadata: BackupMetadata,
    val manifest: BackupLibraryManifestEnvelope,
    val sections: Map<String, String>,
    val blobs: List<BlobUpload>,
)

/** A backup could not be collected because a book's local file or position is unusable — fail
 *  loudly rather than ship a silently-incomplete backup. */
class BackupCollectionException(message: String) : Exception(message)

/**
 * Collects [LibraryRepository] state into a [CollectedBackup]. `fileChecker` is injected so tests
 * don't need real files on disk; production passes the default (exists + readable).
 */
class BackupCollector(
    private val repository: LibraryRepository,
    // isFile (not merely exists) — a readable directory must not masquerade as a backable book file.
    private val fileChecker: (String) -> Boolean = { File(it).let { f -> f.isFile && f.canRead() } },
) {
    suspend fun collect(
        deviceName: String,
        appVersion: String,
        backupId: String,
        now: Instant,
    ): CollectedBackup {
        val books = repository.listBooks()
        val positions = repository.listPositions()

        val manifestEntries = ArrayList<BackupLibraryEntry>(books.size)
        val blobs = ArrayList<BlobUpload>(books.size)
        for (book in books) {
            val path = book.localFilePath
                ?: throw BackupCollectionException("book ${book.fingerprintKey} has no local file to back up")
            if (!fileChecker(path)) {
                throw BackupCollectionException("book ${book.fingerprintKey} local file is missing or unreadable: $path")
            }
            val blobPath = BlobPath.make(book.originalFormat, book.contentSHA256, book.fileByteCount)
            manifestEntries += book.toManifestEntry(blobPath)
            blobs += BlobUpload(blobPath, path, book.originalFormat, book.contentSHA256, book.fileByteCount)
        }

        // Positions: the contract's locatorJSON is a PLAIN Locator (the canonical half). A Readium
        // envelope with a null legacyLocator has no canonical anchor to back up — fail loudly.
        // listBooks() and listPositions() are two snapshots; drop any position whose book was not
        // in the collected manifest (a book+position inserted between the two reads) so every
        // positions.json row has a matching manifest entry — no dangling backup reference.
        val collectedKeys = books.mapTo(HashSet()) { it.fingerprintKey }
        val lastOpenedByKey = books.associate { it.fingerprintKey to it.lastOpenedAt }
        val backupPositions = positions.filter { it.fingerprintKey in collectedKeys }.map { rec ->
            val legacy = rec.locator.legacyLocator
                ?: throw BackupCollectionException(
                    "position ${rec.fingerprintKey} has no canonical (legacy) locator to back up"
                )
            BackupPosition(
                bookFingerprintKey = rec.fingerprintKey,
                locatorJSON = BackupJson.encode(legacy),
                updatedAt = Instant.ofEpochMilli(rec.updatedAt),
                lastOpenedAt = lastOpenedByKey[rec.fingerprintKey]?.let(Instant::ofEpochMilli),
            )
        }

        val manifest = BackupLibraryManifestEnvelope(BackupSchema.MANIFEST_SCHEMA_VERSION, manifestEntries)
        val positionsJson = BackupJson.encode(
            BackupPositionsEnvelope(BackupSchema.CURRENT_SCHEMA_VERSION, backupPositions)
        )
        val sections = mapOf(POSITIONS_SECTION to positionsJson)

        // iOS computes totalSizeBytes as the sum of the section payload sizes (no blobs in the ZIP).
        val totalSize = sections.values.sumOf { it.toByteArray(Charsets.UTF_8).size.toLong() } +
            BackupJson.encode(manifest).toByteArray(Charsets.UTF_8).size.toLong()

        val metadata = BackupMetadata(
            id = backupId,
            createdAt = now,
            deviceName = deviceName,
            appVersion = appVersion,
            bookCount = books.size,
            totalSizeBytes = totalSize,
        )
        return CollectedBackup(metadata, manifest, sections, blobs)
    }

    /** The manifest entry: canonical identity + blob path + preserved title/dates. `author` and
     *  `sourceCanonicalKey` are null in v1 (Android `Book` carries neither). `originalExtension`
     *  derives from the format (BookFormat names = canonical exts; distinct .mobi/.prc is a
     *  follow-on if Android gains Kindle import). */
    private fun Book.toManifestEntry(blobPath: String) = BackupLibraryEntry(
        fingerprintKey = fingerprintKey,
        format = originalFormat.name,
        sha256 = contentSHA256,
        byteCount = fileByteCount,
        originalExtension = originalFormat.name,
        title = title,
        author = null,
        addedAt = Instant.ofEpochMilli(addedAt),
        lastOpenedAt = lastOpenedAt?.let(Instant::ofEpochMilli),
        blobPath = blobPath,
        sourceCanonicalKey = null,
    )

    companion object {
        const val POSITIONS_SECTION = "positions.json"

        // Re-exported for the WI-5 service so it doesn't reach into the archive package directly.
        val METADATA_ENTRY = BackupArchiveEntries.METADATA
        val MANIFEST_ENTRY = BackupArchiveEntries.MANIFEST
    }
}
