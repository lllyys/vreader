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
    ) = Book(
        fingerprintKey = k,
        title = title,
        originalFormat = format,
        contentSHA256 = sha,
        fileByteCount = 2048,
        addedAt = addedAt,
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
