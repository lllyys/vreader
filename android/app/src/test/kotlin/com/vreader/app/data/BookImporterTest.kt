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

    /**
     * Gate-2 CRITICAL regression (feature #128 WI-1): a duplicate SAF import of an already-indexed
     * book must NOT null-clobber a backfilled author. BookImporter goes through the author-preserving
     * upsert, so a re-import of identical bytes (fresh null-author Book) leaves the author intact while
     * the import-owned columns (here the sourceUri) still update.
     */
    @Test
    fun reimport_afterAuthorBackfill_preservesAuthor() = runTest {
        val repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        val first = importer.importStream("content://saf/a1", "Book.epub", ByteArrayInputStream(epubBytes))
        db.bookDao().backfillAuthorIfNull(first.fingerprintKey, "Herman Melville")

        // Duplicate import: same bytes ⇒ same fingerprintKey; the importer builds a null-author Book.
        importer.importStream("content://saf/a2", "Book.epub", ByteArrayInputStream(epubBytes))

        val after = repo.findBook(first.fingerprintKey)!!
        assertEquals("author survives the duplicate import", "Herman Melville", after.author)
        assertEquals("no duplicate library row", 1, repo.observeLibrary().first().size)
        assertEquals("import-owned sourceUri DID update to the re-import URI", "content://saf/a2", after.sourceUri)
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
        // import must leave no orphaned file behind (Gate-4 r2 Medium). The import path now
        // goes through upsertBookPreservingAuthor, whose first write is insertIfAbsent.
        val throwingDao = ThrowingBookDao()
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
        val throwingDao = ThrowingBookDao()
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

    // --- feature #155 WI-1: explicit format override ---
    // An inbound `content://` URI from another app has no reliable filename, so
    // extension-derived detection cannot be the only path into the importer. The
    // trailing `format` parameter REPLACES the extension lookup when non-null;
    // when null the importer behaves exactly as it always has.

    @Test
    fun import_explicitNullFormat_reproducesExtensionDerivedBehaviour() = runTest {
        // Passing the new parameter explicitly as null must be indistinguishable from
        // omitting it: the extension still decides, and an unknown one still throws.
        val book = importer.importStream(
            sourceUri = "content://saf/n1",
            displayName = "Moby-Dick.epub",
            input = ByteArrayInputStream(epubBytes),
            format = null,
        )
        assertEquals(BookFormat.epub, book.originalFormat)
        assertEquals("epub:${book.contentSHA256}:${book.fileByteCount}", book.fingerprintKey)

        var threw = false
        try {
            importer.importStream(
                sourceUri = "content://saf/n2",
                displayName = "notes.xyz",
                input = ByteArrayInputStream(epubBytes),
                format = null,
            )
        } catch (e: ImportException.UnsupportedFormat) {
            threw = true
            assertEquals("notes.xyz", e.name)
        }
        assertTrue("format=null keeps the UnsupportedFormat contract", threw)
    }

    @Test
    fun import_explicitFormat_overridesUnknownExtension() = runTest {
        val book = importer.importStream(
            sourceUri = "content://saf/o1",
            displayName = "x.bin",
            input = ByteArrayInputStream(epubBytes),
            format = BookFormat.epub,
        )
        assertEquals(BookFormat.epub, book.originalFormat)
        // Key shape asserted from the Book's own fields with a LITERAL prefix — never
        // rebuilt through the same helper the implementation uses.
        assertEquals("epub:${book.contentSHA256}:${book.fileByteCount}", book.fingerprintKey)
        assertTrue("artifact stored", File(book.localFilePath!!).exists())
        assertNotNull(
            "book recorded in the library",
            LibraryRepository(db.bookDao(), db.readingPositionDao()).findBook(book.fingerprintKey),
        )
    }

    @Test
    fun import_explicitFormat_andExtensionDerived_produceIdenticalCanonicalKey() = runTest {
        // THE identity contract: an open-with import (no filename → explicit format) must
        // resume the SAME library row a SAF import of the same bytes created, not create a
        // duplicate. The expectation comes from the UNTOUCHED extension path.
        val viaExtension = importer.importStream(
            "content://saf/k1", "Book.epub", ByteArrayInputStream(epubBytes),
        )
        val viaOverride = importer.importStream(
            sourceUri = "content://saf/k2",
            displayName = "x.bin",
            input = ByteArrayInputStream(epubBytes),
            format = BookFormat.epub,
        )
        assertEquals(
            "explicit format and extension detection agree on identity",
            viaExtension.fingerprintKey,
            viaOverride.fingerprintKey,
        )
        val repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        assertEquals("no duplicate library row", 1, repo.observeLibrary().first().size)
    }

    @Test
    fun import_explicitFormat_beatsAConflictingValidExtension() = runTest {
        // Override vs a DIFFERENT *valid* extension: the caller-supplied format wins. The
        // caller resolves it from MIME/magic bytes, which outrank a provider-supplied name.
        val book = importer.importStream(
            sourceUri = "content://saf/c",
            displayName = "x.pdf",
            input = ByteArrayInputStream(epubBytes),
            format = BookFormat.epub,
        )
        assertEquals(BookFormat.epub, book.originalFormat)
        assertEquals("epub:${book.contentSHA256}:${book.fileByteCount}", book.fingerprintKey)
    }

    @Test
    fun import_explicitFormat_extensionlessCjkName_keepsWholeNameAsTitle() = runTest {
        // The realistic content:// shape: a name with no extension at all (and CJK, so the
        // title path is exercised on non-ASCII). Today this throws; with an override it imports.
        val book = importer.importStream(
            sourceUri = "content://saf/cjk",
            displayName = "红楼梦",
            input = ByteArrayInputStream(epubBytes),
            format = BookFormat.azw3,
        )
        assertEquals("红楼梦", book.title)
        assertEquals(BookFormat.azw3, book.originalFormat)
        assertEquals("azw3:${book.contentSHA256}:${book.fileByteCount}", book.fingerprintKey)
    }

    @Test
    fun import_explicitFormat_stillHonoursExpectedKeyVerification() = runTest {
        val viaExtension = importer.importStream(
            "content://saf/x1", "Book.epub", ByteArrayInputStream(epubBytes),
        )
        // A matching expectation succeeds through the override path.
        val ok = importer.importStream(
            sourceUri = "content://saf/x2",
            displayName = "x.bin",
            input = ByteArrayInputStream(epubBytes),
            expectedKey = viaExtension.fingerprintKey,
            format = BookFormat.epub,
        )
        assertEquals(viaExtension.fingerprintKey, ok.fingerprintKey)

        // A wrong expectation still fails — the override does not bypass verification.
        var mismatch: ImportException.FingerprintMismatch? = null
        try {
            importer.importStream(
                sourceUri = "content://saf/x3",
                displayName = "x.bin",
                input = ByteArrayInputStream(epubBytes),
                expectedKey = "pdf:${viaExtension.contentSHA256}:${viaExtension.fileByteCount}",
                format = BookFormat.epub,
            )
        } catch (e: ImportException.FingerprintMismatch) {
            mismatch = e
        }
        assertNotNull("expectedKey verification still applies under an override", mismatch)
        assertEquals(viaExtension.fingerprintKey, mismatch!!.actual)
    }
}

/**
 * A [BookDao] whose every WRITE path throws, used by the DB-write-failure rollback tests. The
 * import path now goes through the author-preserving upsert (insert-if-absent → update), so this
 * fails the FIRST write (`insertIfAbsent`) and the whole-row `upsert`; reads return absent/empty.
 * The `@Transaction` default `upsertPreservingAuthor` body is inherited from the interface and calls
 * these throwing members, so the failure surfaces exactly where the real DAO's would.
 */
private class ThrowingBookDao : BookDao {
    override suspend fun upsert(book: BookEntity): Unit = throw RuntimeException("db down")
    override suspend fun insertIfAbsent(book: BookEntity): Long = throw RuntimeException("db down")
    override suspend fun updateImportedColumns(
        key: String, title: String, fmt: String, sha: String, bytes: Long, path: String?, uri: String?, addedAt: Long,
    ): Unit = throw RuntimeException("db down")
    override suspend fun backfillAuthorIfNull(key: String, author: String?): Unit = throw RuntimeException("db down")
    override suspend fun applyRestoredMetadata(
        key: String, title: String, addedAt: Long, lastOpenedAt: Long?, manifestAuthor: String?,
    ): Unit = throw RuntimeException("db down")
    override fun observeAll() = emptyFlow<List<BookEntity>>()
    override suspend fun find(key: String): BookEntity? = null
    override suspend fun delete(key: String) = Unit
    override suspend fun markOpened(key: String, openedAt: Long) = Unit
    override suspend fun getAll(): List<BookEntity> = emptyList()
    // #152 WI-2: the importer never touches cover state, so this fake throwing here would prove
    // nothing — it stays a no-op, and the import-failure assertions keep testing the write path.
    override suspend fun setCoverState(key: String, path: String?, version: Int?) = Unit
}
