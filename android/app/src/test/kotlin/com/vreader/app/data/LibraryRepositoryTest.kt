package com.vreader.app.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

/**
 * In-memory Room CRUD + envelope round-trip for [LibraryRepository] (feature #106
 * WI-3). Proves the persistence boundary stores/returns DTOs and the VReaderLocator
 * envelope survives a save→load cycle byte-for-byte through the canonical contract.
 */
@RunWith(RobolectricTestRunner::class)
class LibraryRepositoryTest {
    private lateinit var db: VReaderDatabase
    private lateinit var repo: LibraryRepository

    private val sha = "a".repeat(64)
    private val key = Identity.canonicalKey("epub", sha, 2048)

    private fun book(
        k: String = key,
        title: String = "Moby-Dick",
        format: BookFormat = BookFormat.epub,
        addedAt: Long = 1000L,
        author: String? = null,
    ) = Book(
        fingerprintKey = k,
        title = title,
        originalFormat = format,
        contentSHA256 = sha,
        fileByteCount = 2048,
        addedAt = addedAt,
        author = author,
    )

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            VReaderDatabase::class.java,
        ).build()
        repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
    }

    @After
    fun tearDown() = db.close()

    @Test
    fun upsertBook_thenFindAndObserve() = runTest {
        repo.upsertBook(book())
        val found = repo.findBook(key)
        assertEquals("Moby-Dick", found?.title)
        assertEquals(BookFormat.epub, found?.originalFormat)
        assertNull("not opened yet", found?.lastOpenedAt)

        val library = repo.observeLibrary().first()
        assertEquals(1, library.size)
        assertEquals(key, library.first().fingerprintKey)
    }

    @Test
    fun observeLibrary_ordersByAddedAtDescending() = runTest {
        val k1 = Identity.canonicalKey("epub", "b".repeat(64), 1)
        val k2 = Identity.canonicalKey("epub", "c".repeat(64), 2)
        repo.upsertBook(book(k = k1, title = "Older", addedAt = 100L))
        repo.upsertBook(book(k = k2, title = "Newer", addedAt = 200L))
        val titles = repo.observeLibrary().first().map { it.title }
        assertEquals(listOf("Newer", "Older"), titles)
    }

    @Test
    fun upsert_isReplaceOnConflict() = runTest {
        repo.upsertBook(book(title = "v1"))
        repo.upsertBook(book(title = "v2"))
        assertEquals("v2", repo.findBook(key)?.title)
        assertEquals(1, repo.observeLibrary().first().size)
    }

    @Test
    fun deleteBook_removesIt() = runTest {
        repo.upsertBook(book())
        repo.deleteBook(key)
        assertNull(repo.findBook(key))
        assertTrue(repo.observeLibrary().first().isEmpty())
    }

    @Test
    fun markOpened_setsLastOpenedAt() = runTest {
        repo.upsertBook(book())
        repo.markOpened(key, 5555L)
        assertEquals(5555L, repo.findBook(key)?.lastOpenedAt)
    }

    @Test
    fun cjkTitle_roundTrips() = runTest {
        repo.upsertBook(book(title = "红楼梦"))
        assertEquals("红楼梦", repo.findBook(key)?.title)
    }

    // MARK: - feature #128 WI-1 — author column + author-preserving persistence

    @Test
    fun author_roundTripsThroughInsertAndRead() = runTest {
        repo.upsertBook(book(author = "Herman Melville"))
        assertEquals("Herman Melville", repo.findBook(key)?.author)
    }

    @Test
    fun author_defaultsToNull_whenAbsent() = runTest {
        repo.upsertBook(book())
        assertNull("a book imported without an author has null author", repo.findBook(key)?.author)
    }

    @Test
    fun author_cjkRoundTrips() = runTest {
        repo.upsertBook(book(author = "曹雪芹"))
        assertEquals("曹雪芹", repo.findBook(key)?.author)
    }

    @Test
    fun backfillAuthorIfNull_setsAuthor_whenCurrentlyNull() = runTest {
        repo.upsertBook(book())                       // author is null
        db.bookDao().backfillAuthorIfNull(key, "Herman Melville")
        assertEquals("Herman Melville", repo.findBook(key)?.author)
    }

    @Test
    fun backfillAuthorIfNull_preservesExistingAuthor() = runTest {
        repo.upsertBook(book(author = "Real Author"))
        db.bookDao().backfillAuthorIfNull(key, "Should Not Overwrite")
        assertEquals("Real Author", repo.findBook(key)?.author)   // no-op: already set
    }

    /**
     * Gate-2 CRITICAL regression — a duplicate SAF import must NOT null-clobber a backfilled author.
     * The import path calls [LibraryRepository.upsertBookPreservingAuthor], whose UPDATE branch touches
     * only the import-owned columns (title/format/sha/bytes/path/uri/addedAt) and leaves `author`
     * (and `lastOpenedAt`) alone. A whole-row `@Upsert` here would erase the author with a null.
     */
    @Test
    fun upsertBookPreservingAuthor_reImportWithNullAuthor_preservesAuthor_updatesImportColumns() = runTest {
        // First import + a backfilled author.
        repo.upsertBookPreservingAuthor(book(title = "Moby-Dick", addedAt = 1000L))
        db.bookDao().backfillAuthorIfNull(key, "Herman Melville")
        repo.markOpened(key, 5555L)   // a lastOpenedAt the re-import must also preserve

        // Duplicate import: SAME fingerprintKey, a fresh null-author Book with new import-owned values.
        repo.upsertBookPreservingAuthor(
            book(title = "Moby-Dick (re-import)", addedAt = 9999L, author = null),
        )

        val after = repo.findBook(key)!!
        assertEquals("author survives the duplicate import", "Herman Melville", after.author)
        assertEquals("lastOpenedAt is untouched by the import path", 5555L, after.lastOpenedAt)
        assertEquals("import-owned title DID update", "Moby-Dick (re-import)", after.title)
        assertEquals("import-owned addedAt DID update", 9999L, after.addedAt)
        assertEquals("still one row", 1, repo.observeLibrary().first().size)
    }

    @Test
    fun upsertBookPreservingAuthor_firstInsert_recordsTheBook() = runTest {
        repo.upsertBookPreservingAuthor(book(title = "Brand New"))
        val found = repo.findBook(key)
        assertEquals("Brand New", found?.title)
        assertNull("a fresh insert has no author yet", found?.author)
    }

    @Test
    fun applyRestoredMetadata_nonNullManifestAuthor_wins() = runTest {
        repo.upsertBook(book(author = "Existing Author"))
        repo.applyRestoredMetadata(
            key = key, title = "Restored Title", addedAt = 111L, lastOpenedAt = 222L,
            manifestAuthor = "Manifest Author",
        )
        val after = repo.findBook(key)!!
        assertEquals("Manifest Author", after.author)   // non-null manifest author WINS
        assertEquals("Restored Title", after.title)
        assertEquals(111L, after.addedAt)
        assertEquals(222L, after.lastOpenedAt)
    }

    @Test
    fun applyRestoredMetadata_nullManifestAuthor_preservesExisting() = runTest {
        repo.upsertBook(book(author = "Coordinator Backfilled"))
        repo.applyRestoredMetadata(
            key = key, title = "Restored Title", addedAt = 111L, lastOpenedAt = null,
            manifestAuthor = null,
        )
        val after = repo.findBook(key)!!
        assertEquals("null manifest author PRESERVES the existing value", "Coordinator Backfilled", after.author)
        assertEquals("Restored Title", after.title)
        assertEquals(111L, after.addedAt)
        assertNull("a null restored lastOpenedAt is applied as null", after.lastOpenedAt)
    }

    @Test
    fun savePosition_legacyEnvelope_roundTrips() = runTest {
        repo.upsertBook(book())
        val locator = Locator(
            contentSHA256 = sha,
            fileByteCount = 2048,
            format = "epub",
            href = "chapter3.xhtml",
            progression = 0.4213,
            totalProgression = 0.18,
            textQuote = "Call me Ishmael",
        )
        val envelope = VReaderLocator.wrapLegacy(locator)
        repo.savePosition(envelope, updatedAt = 42L)

        val loaded = repo.loadPosition(key)!!
        assertEquals(ReaderLocatorEngine.epubWKWebView, loaded.engine)
        assertNull(loaded.readiumLocatorJSON)
        assertEquals(locator, loaded.legacyLocator)
        assertEquals(BookFormat.epub, loaded.originalFormat)
        assertEquals(VReaderLocator.CURRENT_SCHEMA_VERSION, loaded.schemaVersion)
        // canonicalHash is stable across the save/load round-trip.
        assertEquals(envelope.canonicalHash, loaded.canonicalHash)
    }

    @Test
    fun savePosition_readiumEnvelope_roundTrips() = runTest {
        repo.upsertBook(book())
        val readiumJSON = """{"href":"/ch3.xhtml","locations":{"progression":0.4}}"""
        val envelope = VReaderLocator(
            fingerprintKey = key,
            originalFormat = BookFormat.epub,
            engine = ReaderLocatorEngine.readium,
            readiumLocatorJSON = readiumJSON,
            legacyLocator = null,
        )
        repo.savePosition(envelope, updatedAt = 7L)

        val loaded = repo.loadPosition(key)!!
        assertEquals(ReaderLocatorEngine.readium, loaded.engine)
        assertEquals(readiumJSON, loaded.readiumLocatorJSON)
        assertNull(loaded.legacyLocator)
    }

    @Test
    fun savePosition_isReplaceOnConflict() = runTest {
        repo.upsertBook(book())
        repo.savePosition(VReaderLocator.wrapLegacy(legacyLocatorAt(0.1)), updatedAt = 1L)
        repo.savePosition(VReaderLocator.wrapLegacy(legacyLocatorAt(0.9)), updatedAt = 2L)
        assertEquals(0.9, repo.loadPosition(key)?.legacyLocator?.progression!!, 1e-9)
    }

    @Test
    fun loadPosition_missing_isNull() = runTest {
        assertNull(repo.loadPosition(key))
    }

    @Test
    fun deleteBook_cascadesPosition() = runTest {
        repo.upsertBook(book())
        repo.savePosition(VReaderLocator.wrapLegacy(legacyLocatorAt(0.5)), updatedAt = 1L)
        repo.deleteBook(key)
        assertNull("position cascade-deleted with its book", repo.loadPosition(key))
    }

    /**
     * Gate-4 Critical regression: re-importing a book must NOT wipe its saved
     * position. @Upsert updates the book in place; a REPLACE (delete+insert) would
     * fire the ON DELETE CASCADE and silently drop the reading_positions row.
     */
    @Test
    fun reUpsertBook_preservesSavedPosition() = runTest {
        repo.upsertBook(book(title = "v1"))
        repo.savePosition(VReaderLocator.wrapLegacy(legacyLocatorAt(0.7)), updatedAt = 1L)
        repo.upsertBook(book(title = "v2 re-import"))   // same fingerprintKey
        assertEquals("v2 re-import", repo.findBook(key)?.title)
        assertEquals(0.7, repo.loadPosition(key)?.legacyLocator?.progression!!, 1e-9)
    }

    @Test
    fun savePosition_rejectsNegativePage() = runTest {
        repo.upsertBook(book())
        val bad = Locator(contentSHA256 = sha, fileByteCount = 2048, format = "pdf", page = -1)
        assertThrowsIllegalArgument { repo.savePosition(VReaderLocator.wrapLegacy(bad), updatedAt = 1L) }
        assertNull("nothing persisted for an invalid locator", repo.loadPosition(key))
    }

    @Test
    fun savePosition_rejectsInvertedRange() = runTest {
        repo.upsertBook(book())
        val bad = Locator(
            contentSHA256 = sha, fileByteCount = 2048, format = "txt",
            charRangeStartUTF16 = 50, charRangeEndUTF16 = 10,
        )
        assertThrowsIllegalArgument { repo.savePosition(VReaderLocator.wrapLegacy(bad), updatedAt = 1L) }
    }

    /** Asserts a suspend block throws IllegalArgumentException (no nested runTest). */
    private suspend fun assertThrowsIllegalArgument(block: suspend () -> Unit) {
        var threw = false
        try {
            block()
        } catch (e: IllegalArgumentException) {
            threw = true
        }
        assertTrue("expected IllegalArgumentException", threw)
    }

    @Test
    fun savePosition_repairsNonFiniteProgression() = runTest {
        repo.upsertBook(book())
        val infinite = Locator(
            contentSHA256 = sha, fileByteCount = 2048, format = "epub",
            href = "ch.xhtml", progression = Double.POSITIVE_INFINITY,
        )
        // Non-finite is repaired (nulled), not rejected — mirrors the iOS persistence
        // boundary. It must store without throwing and load back with null progression.
        repo.savePosition(VReaderLocator.wrapLegacy(infinite), updatedAt = 1L)
        assertNull(repo.loadPosition(key)?.legacyLocator?.progression)
    }

    /**
     * Gate-4 Medium: the position is stored as the WHOLE envelope JSON, so a future
     * envelope field (written by a newer app) survives a round-trip on an older
     * decoder WITHOUT a Room schema change. Insert a raw envelope JSON carrying an
     * unknown field directly, then load it back through the repository.
     */
    @Test
    fun loadPosition_toleratesForwardEnvelopeField() = runTest {
        repo.upsertBook(book())
        val futureJson =
            """{"fingerprintKey":"$key","originalFormat":"epub","engine":"readium",""" +
                """"readiumLocatorJSON":"{}","legacyLocator":null,"schemaVersion":2,""" +
                """"futureOnlyField":"ignored-by-older-build"}"""
        db.readingPositionDao().upsert(
            ReadingPositionEntity(
                fingerprintKey = key,
                vreaderLocatorJSON = futureJson,
                canonicalHash = "deadbeef",
                updatedAt = 1L,
            ),
        )
        val loaded = repo.loadPosition(key)!!
        assertEquals(ReaderLocatorEngine.readium, loaded.engine)
        assertEquals(2, loaded.schemaVersion)
    }

    private fun legacyLocatorAt(progression: Double) = Locator(
        contentSHA256 = sha, fileByteCount = 2048, format = "epub",
        href = "ch.xhtml", progression = progression,
    )
}
