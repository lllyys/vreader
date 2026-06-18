// Purpose: EPUB import plumbing — feature #106 WI-4 (Gate-2 High-2). Copies the
// source bytes into app-private storage, fingerprints the LOCAL artifact
// (exact-match, converter-independent identity), and stores a BookEntity keyed by
// that fingerprint with the source URI kept only as metadata. The SAF picker launch
// + ContentResolver display-name/stream resolution live in the (design-blocked, #1744)
// UI layer; this is the testable, UI-free seam: stream in -> stored Book out.
package com.vreader.app.data

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import vreader.contracts.DocumentFingerprint
import java.io.File
import java.io.InputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Import failures surfaced to the (future) UI with a user-facing message. */
sealed class ImportException(message: String) : Exception(message) {
    /** The picked file's extension isn't a supported book format. */
    class UnsupportedFormat(val name: String) : ImportException("unsupported format: $name")
}

/**
 * Imports a book by copying its bytes into [booksDir] (app-private storage) and
 * recording it via [repository]. The blocking copy/hash/promote runs on
 * [ioDispatcher] (injected — rule 50 §12; never run large-file IO on Main). `clock`
 * is injectable for deterministic tests.
 */
class BookImporter(
    private val booksDir: File,
    private val repository: LibraryRepository,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    /**
     * Copies [input] into app-private storage, fingerprints the stored bytes
     * (exact-match identity — Gate-2 High-2), upserts the [Book], and returns it.
     * Idempotent: re-importing identical bytes yields the same `fingerprintKey` and
     * atomically replaces the file (the @Upsert preserves any saved position). The
     * caller (UI) resolves [displayName] + [input] from the SAF content URI;
     * [sourceUri] is persisted only as provenance metadata. [input] is always closed.
     *
     * @throws ImportException.UnsupportedFormat if [displayName]'s extension is unknown.
     */
    suspend fun importStream(sourceUri: String, displayName: String, input: InputStream): Book =
        withContext(ioDispatcher) {
            // Outer use closes [input] on EVERY exit (incl. unsupported-format /
            // temp-create failures), not only once hashing starts.
            input.use { stream ->
                val format = DocumentFingerprint.formatForFilename(displayName)
                    ?: throw ImportException.UnsupportedFormat(displayName)
                if (!booksDir.exists()) booksDir.mkdirs()

                // Copy to a temp file while hashing in one pass; the hash is of exactly
                // the bytes written locally, so identity is of the stored artifact.
                val temp = File.createTempFile("import-", ".part", booksDir)
                try {
                    val result = temp.outputStream().buffered().use { sink ->
                        DocumentFingerprint.hashing(stream, sink)
                    }
                    val key = result.canonicalKey(format)

                    // Final name derived from the (sanitized) canonical key — stable
                    // across re-imports, collision-free across distinct books.
                    val finalFile = File(booksDir, fileNameForKey(key))
                    // Whether an artifact for this key already existed: on a re-import
                    // the bytes are identical (same key ⇒ same content), so a pre-existing
                    // artifact stays valid and is still referenced by its books row.
                    val artifactPreexisted = finalFile.exists()
                    promoteAtomically(temp, finalFile)

                    val book = Book(
                        fingerprintKey = key,
                        title = titleFromDisplayName(displayName),
                        originalFormat = format,
                        contentSHA256 = result.sha256,
                        fileByteCount = result.fileByteCount,
                        localFilePath = finalFile.absolutePath,
                        sourceUri = sourceUri,
                        addedAt = clock(),
                    )
                    try {
                        repository.upsertBook(book)
                    } catch (e: Throwable) {
                        // The artifact is promoted but the DB row failed. Delete it ONLY
                        // if it was freshly created — that's a true orphan. If it
                        // preexisted, an existing books row still validly references this
                        // (byte-identical) file; deleting it would break that entry.
                        if (!artifactPreexisted) finalFile.delete()
                        throw e
                    }
                    book
                } finally {
                    // A failed import (or a successful move) leaves no .part file behind.
                    if (temp.exists()) temp.delete()
                }
            }
        }

    /**
     * Atomically swaps [temp] into [finalFile] — never delete-then-copy into the live
     * path, so a fully-imported artifact is never left missing/partial even if a
     * concurrent same-key import or a crash interleaves (Gate-4 High). Both files are
     * in [booksDir] (one filesystem), so the rename is atomic.
     */
    private fun promoteAtomically(temp: File, finalFile: File) {
        try {
            Files.move(
                temp.toPath(), finalFile.toPath(),
                StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING,
            )
        } catch (e: java.nio.file.AtomicMoveNotSupportedException) {
            // Same-dir move is still a single rename (no delete-then-partial-copy into
            // the live path) on a filesystem without ATOMIC_MOVE support.
            Files.move(temp.toPath(), finalFile.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private fun fileNameForKey(key: String): String =
        key.replace(Regex("[^A-Za-z0-9._-]"), "_")

    private fun titleFromDisplayName(name: String): String =
        name.substringBeforeLast('.', name).ifBlank { name }
}
