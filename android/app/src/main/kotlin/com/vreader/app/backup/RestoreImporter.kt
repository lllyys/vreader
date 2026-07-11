// Purpose: feature #116 WI-4 (#110 Phase 3) — the RESTORE half. Reads library-manifest.json +
// positions.json from a *.vreader.zip, fetches each (selected) book's blob from the content-
// addressed store, materializes it through BookImporter (re-fingerprints → canonical identity,
// idempotent @Upsert), verifies the computed key matches the manifest, restores the manifest's
// title/addedAt/lastOpenedAt/author via the single atomic applyRestoredMetadata seam (feature #128
// WI-2 — author COALESCEd: manifest non-null wins, null preserves a coordinator backfill), THEN
// restores the book's position (book-first so the position FK holds), then (when the matching dao/repo
// is wired) collections.json (feature #127) and annotations.json (feature #132 WI-8 — UUID-preserving,
// idempotent, scoped to the manifest's in-selection books). A per-book failure (blob 404 / fingerprint
// mismatch / import error) is collected and its position skipped — the rest restore. Mirrors the iOS
// materializing-restore (WebDAVProvider + BookFileMaterializer). Idempotent: same bytes ⇒ same key,
// no duplicate; a repeated restore of the same annotations applies 0.
package com.vreader.app.backup

import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.backup.archive.BackupArchiveReader
import com.vreader.app.data.BookImporter
import com.vreader.app.data.CollectionDao
import com.vreader.app.data.LibraryRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import vreader.contracts.Locator
import vreader.contracts.VReaderLocator
import vreader.contracts.backup.BackupAnnotationsEnvelope
import vreader.contracts.backup.BackupCollectionsEnvelope
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupLibraryEntry
import vreader.contracts.backup.BackupPosition
import vreader.contracts.backup.BackupPositionsEnvelope
import vreader.contracts.backup.BackupSchema
import java.io.InputStream
import java.util.Locale
import java.util.UUID

/** One book that failed to restore (the others still restore). */
data class RestoreBookFailure(val fingerprintKey: String, val reason: String)

/** Result of importing a backup: which books were restored, which failed, how many positions
 *  applied. (Distinct from the #114 UI `RestoreOutcome` enum — this is the backend importer's
 *  detailed result; WI-5 maps it to the UI types.) */
data class RestoreImportResult(
    val restored: List<String>,
    val failed: List<RestoreBookFailure>,
    val positionsRestored: Int,
    val collectionsRestored: Int = 0,
    // feature #132 WI-8 — the count of annotations (highlights + notes + bookmarks) freshly applied.
    val annotationsRestored: Int = 0,
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
    // feature #127 WI-6 — when present, collections.json is restored (merge by nameKey, membership
    // union) AFTER books so the membership FK holds. Null (default) skips collections (pre-#127).
    private val collectionDao: CollectionDao? = null,
    // feature #132 WI-8 — when present, annotations.json is restored (UUID-preserving, idempotent,
    // scoped to the manifest's in-selection books) AFTER books so the book row exists. Null (default)
    // skips annotations (pre-#132).
    private val annotationsRepository: AnnotationsRepository? = null,
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
        // Collections restore AFTER all books so the membership FK (bookKey → books) holds for every key.
        // `selection` scopes it: a FULL restore (null) restores every collection + membership; a SELECTIVE
        // restore / retryBook restores only memberships for the selected books and skips collections with no
        // selected member (so a single-book retry can't materialize unrelated collections — Gate-4 High).
        val collectionsRestored = restoreCollections(reader, selection)
        // Annotations restore AFTER books (the annotation's bookKey references a restored book). Scope =
        // the manifest books in selection (all of them for a full restore) — WI-6b drops any row whose
        // book isn't in that allowed set. Uses the manifest scope (not just the books that actually
        // downloaded a blob) so an annotation for an already-local book still restores, iOS parity.
        val allowedBookKeys = books.mapTo(HashSet()) { it.fingerprintKey }
        val annotationsRestored = restoreAnnotations(reader, allowedBookKeys)
        RestoreImportResult(restored, failed, positionsRestored, collectionsRestored, annotationsRestored)
    }

    /** Restore annotations.json (feature #132 WI-8): decode the [BackupAnnotationsEnvelope] and hand it
     *  to WI-6b's UUID-preserving, idempotent [AnnotationsRepository.restoreAnnotations] scoped to
     *  [allowedBookKeys] (rows for a book outside the scope are dropped). Absent section (a pre-#132
     *  backup) / wrong-schema → 0, no crash — the same tolerance decodePositions has. Returns the total
     *  freshly-applied count across highlights + notes + bookmarks. */
    private suspend fun restoreAnnotations(reader: BackupArchiveReader, allowedBookKeys: Set<String>): Int {
        val repo = annotationsRepository ?: return 0
        val json = reader.sectionJson(BackupCollector.ANNOTATIONS_SECTION) ?: return 0
        val env = runCatching { BackupJson.decode<BackupAnnotationsEnvelope>(json) }.getOrNull() ?: return 0
        if (env.schemaVersion !in BackupSchema.ACCEPTED_SCHEMA_VERSIONS) return 0
        val report = repo.restoreAnnotations(env, allowedBookKeys)
        return report.highlights.applied + report.notes.applied + report.bookmarks.applied
    }

    /** Restore collections.json (feature #127 WI-6): merge each backed-up collection by nameKey
     *  (create-with-backup-createdAt if absent, else keep the existing collection + its createdAt) and
     *  union its membership (only for books that exist — FK-safe). [eligible] scopes a selective restore:
     *  null = full restore (every collection, including empty ones); non-null = restore only memberships for
     *  those keys and skip a collection with no eligible member. Names are trimmed before keying (parity with
     *  CollectionRepository's `name.trim().lowercase`), and an empty name is skipped. Each collection is one
     *  @Transaction; a single failure is swallowed. Absent / wrong-schema → 0. Returns the count merged. */
    private suspend fun restoreCollections(reader: BackupArchiveReader, eligible: Set<String>?): Int {
        val dao = collectionDao ?: return 0
        val json = reader.sectionJson(BackupCollector.COLLECTIONS_SECTION) ?: return 0
        val env = runCatching { BackupJson.decode<BackupCollectionsEnvelope>(json) }.getOrNull() ?: return 0
        if (env.schemaVersion !in BackupSchema.ACCEPTED_SCHEMA_VERSIONS) return 0
        var restored = 0
        for (c in env.collections) {
            val keys = if (eligible == null) c.bookFingerprintKeys else c.bookFingerprintKeys.filter { it in eligible }
            // Partial restore: a collection with no selected member is out of scope — don't materialize it.
            if (eligible != null && keys.isEmpty()) continue
            val name = c.name.trim()
            if (name.isEmpty()) continue  // a malformed all-whitespace name has no valid identity
            try {
                dao.restoreCollection(
                    id = UUID.randomUUID().toString(),
                    name = name,
                    nameKey = name.lowercase(Locale.ROOT),
                    createdAt = c.createdAt.toEpochMilli(),
                    bookKeys = keys,
                )
                restored++
            } catch (e: CancellationException) {
                throw e  // never swallow coroutine cancellation
            } catch (e: Exception) {
                // skip this collection (e.g. an unexpected constraint); the others still restore
            }
        }
        return restored
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
        // Restore the manifest's title/addedAt/lastOpenedAt/author through the single atomic seam
        // (feature #128 WI-2). BookImporter set title from the synthetic display name + addedAt=now +
        // a null author; a column-scoped UPDATE keeps the just-saved file + any position. The author
        // is COALESCEd — a non-null manifest author WINS; a null one PRESERVES whatever author a
        // coordinator already backfilled onto the just-imported row.
        repository.applyRestoredMetadata(
            key = entry.fingerprintKey,
            title = entry.title ?: imported.title,
            addedAt = entry.addedAt.toEpochMilli(),
            lastOpenedAt = entry.lastOpenedAt?.toEpochMilli(),
            manifestAuthor = entry.author,
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
