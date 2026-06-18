package com.vreader.app.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
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
import vreader.contracts.VReaderLocator
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.CyclicBarrier
import java.util.concurrent.TimeUnit

/**
 * Import plumbing tests (feature #106 WI-4): the SAF byte stream is copied into
 * app-private storage and the LOCAL artifact is fingerprinted (exact-match,
 * converter-independent identity — Gate-2 High-2), surviving a cold process restart.
 */
@RunWith(RobolectricTestRunner::class)
class BookImporterTest {
    @get:Rule val tmp = TemporaryFolder()

    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private lateinit var booksDir: File
    private lateinit var db: VReaderDatabase
    private lateinit var importer: BookImporter

    // A few KB of deterministic "EPUB" bytes — content identity is over these exact bytes.
    private val epubBytes = ByteArray(4096) { (it % 251).toByte() }

    @Before
    fun setUp() {
        booksDir = tmp.newFolder("books")
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).build()
        // Unconfined dispatcher keeps the IO inline on the test thread (deterministic).
        importer = BookImporter(
            booksDir, LibraryRepository(db.bookDao(), db.readingPositionDao()), Dispatchers.Unconfined,
        ) { 1000L }
    }

    @After
    fun tearDown() = db.close()

    @Test
    fun import_copiesToStorage_andFingerprintsLocalArtifact() = runTest {
        val book = importer.importStream(
            sourceUri = "content://com.android.providers/doc/42",
            displayName = "Moby-Dick.epub",
            input = ByteArrayInputStream(epubBytes),
        )

        val local = File(book.localFilePath!!)
        assertTrue("file copied into app-private storage", local.exists())
        assertEquals(epubBytes.size.toLong(), local.length())
        assertTrue("bytes copied verbatim", local.readBytes().contentEquals(epubBytes))

        // Identity is the fingerprint of the LOCAL artifact (re-hash → same key).
        val expectedKey = DocumentFingerprint.hash(local).canonicalKey(BookFormat.epub)
        assertEquals(expectedKey, book.fingerprintKey)

        assertEquals(BookFormat.epub, book.originalFormat)
        assertEquals("Moby-Dick", book.title)
        assertEquals("content://com.android.providers/doc/42", book.sourceUri)
        assertEquals(epubBytes.size.toLong(), book.fileByteCount)

        val repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        assertNotNull("book recorded in the library", repo.findBook(book.fingerprintKey))
    }

    @Test
    fun import_thenColdRestart_reopensFromLocalStorage_identityHolds() {
        val dbName = "importer-restart.db"
        context.deleteDatabase(dbName)
        try {
            // First "process": import into a file-backed DB, then close it.
            val key: String
            val localPath: String
            run {
                val db1 = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
                    .addMigrations(*VReaderDatabase.ALL_MIGRATIONS).build()
                val importer1 = BookImporter(
                    booksDir, LibraryRepository(db1.bookDao(), db1.readingPositionDao()), Dispatchers.Unconfined,
                ) { 1L }
                val book = runBlocking {
                    importer1.importStream("content://saf/1", "Book.epub", ByteArrayInputStream(epubBytes))
                }
                key = book.fingerprintKey
                localPath = book.localFilePath!!
                db1.close()
            }

            // Cold restart: a fresh DB instance on the same file + the still-present
            // local artifact. Identity must hold (re-fingerprint the local file).
            val db2 = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
                .addMigrations(*VReaderDatabase.ALL_MIGRATIONS).build()
            try {
                val repo2 = LibraryRepository(db2.bookDao(), db2.readingPositionDao())
                val reopened = runBlocking { repo2.findBook(key) }
                assertNotNull("book survived the restart", reopened)
                val local = File(localPath)
                assertTrue("local artifact persists", local.exists())
                assertEquals(
                    "cold-start identity holds",
                    key,
                    DocumentFingerprint.hash(local).canonicalKey(BookFormat.epub),
                )
            } finally {
                db2.close()
            }
        } finally {
            context.deleteDatabase(dbName)
        }
    }

    @Test
    fun import_unsupportedFormat_throws() = runTest {
        var threw = false
        try {
            importer.importStream("content://saf/x", "notes.xyz", ByteArrayInputStream(epubBytes))
        } catch (e: ImportException.UnsupportedFormat) {
            threw = true
            assertEquals("notes.xyz", e.name)
        }
        assertTrue("unsupported extension rejected", threw)
    }

    @Test
    fun reimport_sameBytes_isIdempotent_andPreservesPosition() = runTest {
        val repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        val first = importer.importStream("content://saf/a", "Book.epub", ByteArrayInputStream(epubBytes))
        // Save a position, then re-import the identical bytes (same fingerprintKey).
        repo.savePosition(
            VReaderLocator.wrapLegacy(
                Locator(contentSHA256 = first.contentSHA256, fileByteCount = first.fileByteCount,
                    format = "epub", href = "ch.xhtml", progression = 0.42),
            ),
            updatedAt = 5L,
        )
        val second = importer.importStream("content://saf/b", "Book.epub", ByteArrayInputStream(epubBytes))

        assertEquals("identical bytes → identical identity", first.fingerprintKey, second.fingerprintKey)
        assertEquals("no duplicate library row", 1, repo.observeLibrary().first().size)
        assertEquals("saved position preserved across re-import", 0.42, repo.loadPosition(first.fingerprintKey)?.legacyLocator?.progression!!, 1e-9)
    }

    @Test
    fun import_cjkFilename_titleStripsExtension() = runTest {
        val book = importer.importStream("content://saf/z", "红楼梦.epub", ByteArrayInputStream(epubBytes))
        assertEquals("红楼梦", book.title)
    }

    @Test
    fun import_emptyStream_storesZeroByteArtifact() = runTest {
        val book = importer.importStream("content://saf/e", "empty.epub", ByteArrayInputStream(ByteArray(0)))
        assertEquals(0L, book.fileByteCount)
        val local = File(book.localFilePath!!)
        assertTrue(local.exists())
        assertEquals(0L, local.length())
        // SHA-256 of the empty byte sequence.
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            book.contentSHA256,
        )
    }

    @Test
    fun import_midCopyFailure_leavesNoArtifact() = runTest {
        val failing = object : InputStream() {
            private var emitted = 0
            override fun read(): Int = throw IOException("single-byte read unused")
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (emitted >= 1024) throw IOException("simulated mid-copy failure")
                val take = minOf(len, 1024 - emitted)
                for (i in 0 until take) b[off + i] = 1
                emitted += take
                return take
            }
        }
        var threw = false
        try {
            importer.importStream("content://saf/f", "Partial.epub", failing)
        } catch (e: IOException) {
            threw = true
        }
        assertTrue("the failure propagated", threw)
        // No half-written temp AND no final artifact left behind.
        assertTrue("no leftover .part temp", booksDir.listFiles()?.none { it.name.startsWith("import-") } ?: true)
        assertEquals("no final artifact for a failed import", 0, booksDir.listFiles()?.size ?: 0)
    }

    @Test
    fun import_concurrentSameKey_convergesToOneValidArtifact() = runTest {
        val repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        // A REAL multithreaded dispatcher + a barrier that releases both imports only
        // once both are mid-copy — so the two promotions genuinely overlap (no inline
        // false-green).
        val realImporter = BookImporter(booksDir, repo, Dispatchers.IO) { 1000L }
        val barrier = CyclicBarrier(2)
        fun syncedStream() = object : InputStream() {
            private val src = ByteArrayInputStream(epubBytes)
            private var synced = false
            override fun read(): Int = src.read()
            override fun read(b: ByteArray, off: Int, len: Int): Int {
                if (!synced) {
                    synced = true
                    barrier.await(5, TimeUnit.SECONDS)   // both threads rendezvous here
                }
                return src.read(b, off, len)
            }
        }
        coroutineScope {
            val a = async { realImporter.importStream("content://saf/c1", "Book.epub", syncedStream()) }
            val b = async { realImporter.importStream("content://saf/c2", "Book.epub", syncedStream()) }
            assertEquals(a.await().fingerprintKey, b.await().fingerprintKey)
        }
        assertEquals("one library row for identical bytes", 1, repo.observeLibrary().first().size)
        val book = repo.observeLibrary().first().single()
        val local = File(book.localFilePath!!)
        assertTrue("the surviving artifact is intact", local.exists())
        assertEquals(book.fingerprintKey, DocumentFingerprint.hash(local).canonicalKey(BookFormat.epub))
    }

    @Test
    fun import_dbWriteFailure_rollsBackPromotedArtifact() = runTest {
        // A repository whose book write fails AFTER the artifact is promoted — the
        // import must leave no orphaned file behind (Gate-4 r2 Medium).
        val throwingDao = object : BookDao {
            override suspend fun upsert(book: BookEntity): Unit = throw RuntimeException("db down")
            override fun observeAll() = emptyFlow<List<BookEntity>>()
            override suspend fun find(key: String): BookEntity? = null
            override suspend fun delete(key: String) = Unit
            override suspend fun markOpened(key: String, openedAt: Long) = Unit
        }
        val failingImporter = BookImporter(
            booksDir, LibraryRepository(throwingDao, db.readingPositionDao()), Dispatchers.Unconfined,
        ) { 1L }

        var threw = false
        try {
            failingImporter.importStream("content://saf/db", "Book.epub", ByteArrayInputStream(epubBytes))
        } catch (e: RuntimeException) {
            threw = true
        }
        assertTrue("the DB failure propagated", threw)
        assertEquals("no orphaned artifact after a failed write", 0, booksDir.listFiles()?.size ?: 0)
    }

    @Test
    fun reimport_dbWriteFailure_preservesExistingArtifact() = runTest {
        // A book is already imported (real repo → file + row exist).
        val first = importer.importStream("content://saf/r1", "Book.epub", ByteArrayInputStream(epubBytes))
        val local = File(first.localFilePath!!)
        assertTrue(local.exists())

        // Re-import the SAME bytes through a repo whose write fails after promotion.
        // Same key ⇒ identical content, so the existing row still validly references
        // this file — the rollback must NOT delete it.
        val throwingDao = object : BookDao {
            override suspend fun upsert(book: BookEntity): Unit = throw RuntimeException("db down")
            override fun observeAll() = emptyFlow<List<BookEntity>>()
            override suspend fun find(key: String): BookEntity? = null
            override suspend fun delete(key: String) = Unit
            override suspend fun markOpened(key: String, openedAt: Long) = Unit
        }
        val failingImporter = BookImporter(
            booksDir, LibraryRepository(throwingDao, db.readingPositionDao()), Dispatchers.Unconfined,
        ) { 2L }
        var threw = false
        try {
            failingImporter.importStream("content://saf/r2", "Book.epub", ByteArrayInputStream(epubBytes))
        } catch (e: RuntimeException) {
            threw = true
        }
        assertTrue("the re-import DB failure propagated", threw)
        assertTrue("existing artifact NOT deleted on re-import failure", local.exists())

        // The original library row still resolves to the present file.
        val repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        assertEquals(local.absolutePath, repo.findBook(first.fingerprintKey)?.localFilePath)
        assertEquals(first.fingerprintKey, DocumentFingerprint.hash(local).canonicalKey(BookFormat.epub))
    }
}
