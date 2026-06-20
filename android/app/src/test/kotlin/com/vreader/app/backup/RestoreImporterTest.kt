package com.vreader.app.backup

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.backup.archive.BackupArchiveReader
import com.vreader.app.backup.archive.BackupArchiveWriter
import com.vreader.app.backup.archive.BlobPath
import com.vreader.app.backup.net.WebDavErrorKind
import com.vreader.app.backup.net.WebDavException
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import vreader.contracts.DocumentFingerprint
import vreader.contracts.Locator
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupLibraryEntry
import vreader.contracts.backup.BackupLibraryManifestEnvelope
import vreader.contracts.backup.BackupMetadata
import vreader.contracts.backup.BackupPosition
import vreader.contracts.backup.BackupPositionsEnvelope
import java.io.ByteArrayInputStream
import java.time.Instant

/**
 * Feature #116 WI-4 — RestoreImporter: blob fetch → import (re-fingerprint) → identity verify →
 * manifest-metadata restore → position restore, per-book failure isolation, idempotency. In-memory
 * Room (Robolectric); blobs are served by a fake fetcher.
 */
@RunWith(RobolectricTestRunner::class)
class RestoreImporterTest {
    @get:Rule val tmp = TemporaryFolder()

    private lateinit var db: VReaderDatabase
    private lateinit var repo: LibraryRepository
    private lateinit var importer: BookImporter
    private val blobs = HashMap<String, ByteArray>()
    private val now = Instant.parse("2026-06-20T12:00:00Z")

    /** A real book blob + its derived manifest entry (the fingerprint = hash of the blob bytes). */
    private fun entryFor(content: String, title: String = "Restored", addedAt: Long = 1000L): BackupLibraryEntry {
        val bytes = content.toByteArray()
        val fp = DocumentFingerprint.hashing(ByteArrayInputStream(bytes))
        val key = "epub:${fp.sha256}:${fp.fileByteCount}"
        val blobPath = BlobPath.make(BookFormat.epub, fp.sha256, fp.fileByteCount)
        blobs[blobPath] = bytes
        return BackupLibraryEntry(
            fingerprintKey = key, format = "epub", sha256 = fp.sha256, byteCount = fp.fileByteCount,
            originalExtension = "epub", title = title, addedAt = Instant.ofEpochMilli(addedAt),
            lastOpenedAt = Instant.ofEpochMilli(9000L), blobPath = blobPath,
        )
    }

    private fun archive(
        entries: List<BackupLibraryEntry>,
        positions: List<BackupPosition> = emptyList(),
    ): BackupArchiveReader {
        val manifest = BackupLibraryManifestEnvelope(1, entries)
        val sections = mapOf(
            BackupCollector.POSITIONS_SECTION to BackupJson.encode(BackupPositionsEnvelope(3, positions))
        )
        val meta = BackupMetadata("id", now, "Pixel 7", "0.7.4", entries.size, 100)
        return BackupArchiveReader.read(BackupArchiveWriter.write(meta, manifest, sections))
    }

    private fun position(entry: BackupLibraryEntry, progression: Double = 0.4) = BackupPosition(
        bookFingerprintKey = entry.fingerprintKey,
        locatorJSON = BackupJson.encode(
            Locator(entry.sha256, entry.byteCount, "epub", href = "ch1.xhtml", progression = progression)
        ),
        updatedAt = Instant.ofEpochMilli(7000L),
    )

    private fun restorer() = RestoreImporter(importer, repo, fetchBlob = {
        val bytes = blobs[it] ?: throw WebDavException(WebDavErrorKind.notFound404, "404 $it")
        ByteArrayInputStream(bytes)
    }, ioDispatcher = Dispatchers.Unconfined)

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java
        ).build()
        repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        importer = BookImporter(tmp.newFolder("books"), repo, Dispatchers.Unconfined) { 999L }
    }

    @After fun tearDown() = db.close()

    @Test fun restore_importsBook_restoresMetadataAndPosition() = runTest {
        // Whole-second epoch values: the manifest round-trips dates as ISO8601 second-precision
        // (the cross-platform contract), so sub-second millis would truncate.
        val e = entryFor("EPUB-CONTENT-A", title = "红楼梦", addedAt = 2000L)
        val out = restorer().restore(archive(listOf(e), listOf(position(e))))

        assertEquals(listOf(e.fingerprintKey), out.restored)
        assertTrue(out.failed.isEmpty())
        assertEquals(1, out.positionsRestored)
        // Manifest metadata restored (NOT BookImporter's synthetic title / addedAt=999).
        val book = repo.findBook(e.fingerprintKey)!!
        assertEquals("红楼梦", book.title)
        assertEquals(2000L, book.addedAt)
        assertEquals(9000L, book.lastOpenedAt)
        // Position restored as a wrapped legacy locator.
        val pos = repo.loadPosition(e.fingerprintKey)!!
        assertEquals(0.4, pos.legacyLocator!!.progression!!, 1e-9)
    }

    @Test fun restore_isIdempotent() = runTest {
        val e = entryFor("EPUB-CONTENT-B")
        val arc = archive(listOf(e), listOf(position(e)))
        restorer().restore(arc)
        val out = restorer().restore(archive(listOf(e), listOf(position(e))))  // again
        assertEquals(listOf(e.fingerprintKey), out.restored)
        assertEquals(1, repo.listBooks().size)  // no duplicate
    }

    @Test fun restore_blobMissing_isolatesFailure() = runTest {
        val ok = entryFor("EPUB-CONTENT-C")
        val gone = entryFor("EPUB-CONTENT-D").also { blobs.remove(it.blobPath) }  // 404 on fetch
        val out = restorer().restore(archive(listOf(ok, gone)))
        assertTrue(out.restored.contains(ok.fingerprintKey))
        assertEquals(1, out.failed.size)
        assertEquals(gone.fingerprintKey, out.failed[0].fingerprintKey)
        assertNull(repo.findBook(gone.fingerprintKey))
    }

    @Test fun restore_fingerprintMismatch_rollsBack() = runTest {
        // Manifest claims an identity the blob bytes do NOT hash to.
        val real = entryFor("EPUB-CONTENT-E")
        val lying = real.copy(
            fingerprintKey = "epub:${"f".repeat(64)}:${real.byteCount}", sha256 = "f".repeat(64),
        )
        // Point the lying entry's blobPath at the real bytes.
        blobs[lying.blobPath] = "EPUB-CONTENT-E".toByteArray()
        val out = restorer().restore(archive(listOf(lying)))
        assertTrue(out.restored.isEmpty())
        assertEquals(1, out.failed.size)
        // Neither the lying key nor the blob's real key leaked into the library.
        assertNull(repo.findBook(lying.fingerprintKey))
        assertEquals(0, repo.listBooks().size)
    }

    @Test fun restore_selection_restoresOnlyChosen() = runTest {
        val a = entryFor("EPUB-CONTENT-F")
        val b = entryFor("EPUB-CONTENT-G")
        val out = restorer().restore(archive(listOf(a, b)), selection = setOf(a.fingerprintKey))
        assertEquals(listOf(a.fingerprintKey), out.restored)
        assertNull(repo.findBook(b.fingerprintKey))
    }

    @Test fun restore_invalidPosition_keepsBook() = runTest {
        val e = entryFor("EPUB-CONTENT-H")
        val bad = BackupPosition(
            bookFingerprintKey = e.fingerprintKey,
            locatorJSON = BackupJson.encode(Locator(e.sha256, e.byteCount, "epub", page = -5)),  // invalid
            updatedAt = Instant.ofEpochMilli(7000L),
        )
        val out = restorer().restore(archive(listOf(e), listOf(bad)))
        assertEquals(listOf(e.fingerprintKey), out.restored)
        assertEquals(0, out.positionsRestored)
        assertNull(repo.loadPosition(e.fingerprintKey))  // book kept, position skipped
    }

    @Test fun restore_emptyManifest_noop() = runTest {
        val out = restorer().restore(archive(emptyList()))
        assertTrue(out.restored.isEmpty() && out.failed.isEmpty())
        assertEquals(0, out.positionsRestored)
    }
}
