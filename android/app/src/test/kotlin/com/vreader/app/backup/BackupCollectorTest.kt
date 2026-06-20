package com.vreader.app.backup

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.backup.archive.BlobPath
import com.vreader.app.data.Book
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import vreader.contracts.Identity
import vreader.contracts.Locator
import vreader.contracts.ReaderLocatorEngine
import vreader.contracts.VReaderLocator
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupPositionsEnvelope
import java.time.Instant

/**
 * Feature #116 WI-3 — the BackupCollector turns the Room library + positions into the #113
 * manifest + positions DTOs and the blob-upload list. In-memory Room (Robolectric); files are
 * faked via the injected checker.
 */
@RunWith(RobolectricTestRunner::class)
class BackupCollectorTest {
    private lateinit var db: VReaderDatabase
    private lateinit var repo: LibraryRepository
    private val now = Instant.parse("2026-06-20T12:00:00Z")
    private val readablePaths = mutableSetOf<String>()

    private fun shaFor(seed: Char) = seed.toString().repeat(64)

    private fun book(
        seed: Char = 'a',
        title: String = "Moby-Dick",
        format: BookFormat = BookFormat.epub,
        bytes: Long = 2048,
        path: String? = "/data/$seed.epub",
        addedAt: Long = 1000L,
        lastOpenedAt: Long? = 5000L,
    ): Book {
        val sha = shaFor(seed)
        val key = Identity.canonicalKey(format.name, sha, bytes)
        if (path != null) readablePaths += path
        return Book(
            fingerprintKey = key, title = title, originalFormat = format,
            contentSHA256 = sha, fileByteCount = bytes, localFilePath = path,
            addedAt = addedAt, lastOpenedAt = lastOpenedAt,
        )
    }

    private fun legacyEnvelope(b: Book, progression: Double = 0.5) =
        VReaderLocator.wrapLegacy(
            Locator(b.contentSHA256, b.fileByteCount, b.originalFormat.name, href = "ch1.xhtml", progression = progression)
        )

    private fun collector() = BackupCollector(repo, fileChecker = { it in readablePaths })

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java
        ).build()
        repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
    }

    @After fun tearDown() = db.close()

    @Test fun collect_buildsManifestPositionsAndBlobs() = runTest {
        val b = book(title = "红楼梦")
        repo.upsertBook(b)
        repo.savePosition(legacyEnvelope(b), updatedAt = 7000L)

        val out = collector().collect("Pixel 7", "0.7.3", "11111111-1111-4111-8111-111111111111", now)

        assertEquals(1, out.metadata.bookCount)
        assertEquals("Pixel 7", out.metadata.deviceName)
        // Manifest: one entry, CJK title preserved, blob path = iOS layout.
        assertEquals(1, out.manifest.books.size)
        val entry = out.manifest.books[0]
        assertEquals("红楼梦", entry.title)
        assertEquals("epub", entry.originalExtension)
        assertEquals(BlobPath.make(BookFormat.epub, b.contentSHA256, b.fileByteCount), entry.blobPath)
        // Blob upload list mirrors the manifest.
        assertEquals(1, out.blobs.size)
        assertEquals("/data/a.epub", out.blobs[0].localFilePath)
        assertEquals(entry.blobPath, out.blobs[0].blobPath)
        // Positions section: the canonical (legacy) locator JSON, decodable as a plain Locator.
        val positions = BackupJson.decode<BackupPositionsEnvelope>(out.sections["positions.json"]!!)
        assertEquals(1, positions.positions.size)
        val pos = positions.positions[0]
        assertEquals(b.fingerprintKey, pos.bookFingerprintKey)
        val decoded = BackupJson.decode<Locator>(pos.locatorJSON)
        assertEquals(0.5, decoded.progression!!, 1e-9)
        assertEquals(Instant.ofEpochMilli(7000L), pos.updatedAt)
        assertEquals(Instant.ofEpochMilli(5000L), pos.lastOpenedAt)
    }

    @Test fun collect_emptyLibrary_isValidEmpty() = runTest {
        val out = collector().collect("Pixel 7", "0.7.3", "id", now)
        assertEquals(0, out.metadata.bookCount)
        assertTrue(out.manifest.books.isEmpty())
        assertTrue(out.blobs.isEmpty())
        val positions = BackupJson.decode<BackupPositionsEnvelope>(out.sections["positions.json"]!!)
        assertTrue(positions.positions.isEmpty())
    }

    @Test fun collect_failsLoud_onMissingLocalPath() = runTest {
        repo.upsertBook(book(path = null))
        val ex = runCatching { collector().collect("d", "v", "id", now) }.exceptionOrNull()
        assertTrue(ex is BackupCollectionException)
    }

    @Test fun collect_failsLoud_onUnreadableFile() = runTest {
        val b = book()
        readablePaths.remove(b.localFilePath)  // checker now rejects it
        repo.upsertBook(b)
        val ex = runCatching { collector().collect("d", "v", "id", now) }.exceptionOrNull()
        assertTrue(ex is BackupCollectionException)
    }

    @Test fun collect_defaultChecker_rejectsDirectory_acceptsRegularFile() = runTest {
        val tmpDir = java.io.File.createTempFile("vr-blob", "").let { it.delete(); it.mkdirs(); it }
        val real = java.io.File(tmpDir, "book.epub").apply { writeText("epub") }
        try {
            // A book whose localFilePath is a DIRECTORY must fail (default fileChecker = isFile).
            repo.upsertBook(book(seed = 'd', path = tmpDir.absolutePath))
            val ex = runCatching { BackupCollector(repo).collect("d", "v", "id", now) }.exceptionOrNull()
            assertTrue("directory rejected", ex is BackupCollectionException)
            // Swap to a real regular file → collection succeeds.
            repo.upsertBook(book(seed = 'd', path = real.absolutePath))
            val out = BackupCollector(repo).collect("d", "v", "id", now)
            assertEquals(1, out.blobs.size)
        } finally {
            real.delete(); tmpDir.delete()
        }
    }

    @Test fun collect_failsLoud_onPositionlessReadiumEnvelope() = runTest {
        val b = book()
        repo.upsertBook(b)
        // A Readium envelope with NO canonical legacy locator — nothing to back up.
        repo.savePosition(
            VReaderLocator(
                fingerprintKey = b.fingerprintKey, originalFormat = b.originalFormat,
                engine = ReaderLocatorEngine.readium, readiumLocatorJSON = "{\"href\":\"x\"}",
                legacyLocator = null,
            ),
            updatedAt = 7000L,
        )
        val ex = runCatching { collector().collect("d", "v", "id", now) }.exceptionOrNull()
        assertTrue(ex is BackupCollectionException)
    }
}
