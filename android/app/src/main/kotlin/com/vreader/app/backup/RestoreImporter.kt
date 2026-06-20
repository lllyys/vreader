// Purpose: feature #116 WI-4 (#110 Phase 3) — the RESTORE half. Reads library-manifest.json +
// positions.json from a *.vreader.zip, fetches each (selected) book's blob from the content-
// addressed store, materializes it through BookImporter (re-fingerprints → canonical identity,
// idempotent @Upsert), verifies the computed key matches the manifest, restores the manifest's
// title/addedAt/lastOpenedAt, THEN restores the book's position (book-first so the position FK
// holds). A per-book failure (blob 404 / fingerprint mismatch / import error) is collected and its
// position skipped — the rest restore. Mirrors the iOS materializing-restore (WebDAVProvider +
// BookFileMaterializer). Idempotent: same bytes ⇒ same key, no duplicate.
package com.vreader.app.backup

import com.vreader.app.backup.archive.BackupArchiveReader
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import vreader.contracts.Locator
import vreader.contracts.VReaderLocator
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupLibraryEntry
import vreader.contracts.backup.BackupPosition
import vreader.contracts.backup.BackupPositionsEnvelope
import vreader.contracts.backup.BackupSchema
import java.io.InputStream

/** One book that failed to restore (the others still restore). */
data class RestoreBookFailure(val fingerprintKey: String, val reason: String)

/** Result of importing a backup: which books were restored, which failed, how many positions
 *  applied. (Distinct from the #114 UI `RestoreOutcome` enum — this is the backend importer's
 *  detailed result; WI-5 maps it to the UI types.) */
data class RestoreImportResult(
    val restored: List<String>,
    val failed: List<RestoreBookFailure>,
    val positionsRestored: Int,
)

/**
 * Restores books + positions from a parsed backup archive. `fetchBlob` opens a STREAM for a blob
 * by its server-relative path (WI-5 passes `webDavClient::getStream` — never the whole-body `get`,
 * so a large book isn't buffered in memory); tests pass a fake. `progress(done, total)` is invoked
 * per book.
 */
class RestoreImporter(
    private val bookImporter: BookImporter,
    private val repository: LibraryRepository,
    private val fetchBlob: suspend (String) -> InputStream,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) {
    suspend fun restore(
        reader: BackupArchiveReader,
        selection: Set<String>? = null,
        progress: suspend (Int, Int) -> Unit = { _, _ -> },
    ): RestoreImportResult = withContext(ioDispatcher) {
        val books = reader.manifest.books.filter { selection == null || it.fingerprintKey in selection }
        val positions = decodePositions(reader)

        val restored = ArrayList<String>()
        val failed = ArrayList<RestoreBookFailure>()
        var positionsRestored = 0

        books.forEachIndexed { index, entry ->
            try {
                restoreBook(entry)
                restored += entry.fingerprintKey
                if (restorePosition(entry.fingerprintKey, positions[entry.fingerprintKey])) positionsRestored++
            } catch (e: CancellationException) {
                throw e  // never swallow coroutine cancellation as a per-book failure
            } catch (e: Exception) {
                failed += RestoreBookFailure(entry.fingerprintKey, e.message ?: e.javaClass.simpleName)
            }
            progress(index + 1, books.size)
        }
        RestoreImportResult(restored, failed, positionsRestored)
    }

    /** Fetch the blob, import it (re-fingerprint), verify identity, restore manifest metadata. */
    private suspend fun restoreBook(entry: BackupLibraryEntry) {
        // Import under the manifest's CANONICAL format extension so the computed key uses the same
        // format the manifest declares (originalExtension may be a remapped Kindle ext like .mobi).
        // `expectedKey` makes BookImporter verify the identity BEFORE any artifact promotion / DB
        // write, so a blob that doesn't match the manifest never touches the library — no
        // wrongly-keyed import, no rollback that could delete a different pre-existing book.
        val imported = fetchBlob(entry.blobPath).use { stream ->  // throws (e.g. 404) → caught by caller
            bookImporter.importStream(
                sourceUri = "restore://${entry.blobPath}",
                displayName = "restore.${entry.format}",
                input = stream,
                expectedKey = entry.fingerprintKey,
            )
        }
        // Restore the manifest's title/addedAt/lastOpenedAt (BookImporter set title from the
        // synthetic display name + addedAt=now). @Upsert keeps the just-saved file + any position.
        repository.upsertBook(
            imported.copy(
                title = entry.title ?: imported.title,
                addedAt = entry.addedAt.toEpochMilli(),
                lastOpenedAt = entry.lastOpenedAt?.toEpochMilli(),
            )
        )
    }

    /** Decode + validate the position's plain Locator, wrap it, and save it. Book already exists
     *  (restored above) so the FK holds. Returns true iff a position was applied. */
    private suspend fun restorePosition(fingerprintKey: String, position: BackupPosition?): Boolean {
        if (position == null) return false
        val locator = runCatching { BackupJson.decode<Locator>(position.locatorJSON) }.getOrNull() ?: return false
        if (locator.validate() != null) return false  // structurally invalid — skip, keep the book
        if (locator.fingerprintKey != fingerprintKey) return false  // position points elsewhere
        return try {
            repository.savePosition(VReaderLocator.wrapLegacy(locator), updatedAt = position.updatedAt.toEpochMilli())
            true
        } catch (e: CancellationException) {
            throw e  // never swallow coroutine cancellation
        } catch (e: Exception) {
            false  // a position write failure degrades to "position skipped"; the book is kept
        }
    }

    /** positions.json (absent or wrong-schema → no positions) → bookFingerprintKey → BackupPosition. */
    private fun decodePositions(reader: BackupArchiveReader): Map<String, BackupPosition> {
        val json = reader.sectionJson(BackupCollector.POSITIONS_SECTION) ?: return emptyMap()
        val env = runCatching { BackupJson.decode<BackupPositionsEnvelope>(json) }.getOrNull() ?: return emptyMap()
        if (env.schemaVersion !in BackupSchema.ACCEPTED_SCHEMA_VERSIONS) return emptyMap()
        return env.positions.associateBy { it.bookFingerprintKey }
    }
}
