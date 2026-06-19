package com.vreader.app.reader

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.Book
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import vreader.contracts.Locator
import vreader.contracts.VReaderLocator

/**
 * The TXT resume contract (feature #111 WI-3, the Gate-2 High): a TXT position is a
 * LEGACY (non-Readium) `VReaderLocator` carrying `charOffsetUTF16`. It must round-trip
 * through the repository and resolve to `ResumeTarget.Canonical` (NOT `Precise`/`None`).
 */
@RunWith(RobolectricTestRunner::class)
class TxtResumeTest {
    private lateinit var db: VReaderDatabase
    private lateinit var repo: LibraryRepository
    private val key = "txt:${"a".repeat(64)}:100"

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java).build()
        repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
    }

    @After fun tearDown() = db.close()

    @Test
    fun txtLegacyEnvelope_roundTrips_andResolvesCanonical() = runBlocking {
        repo.upsertBook(
            Book(key, "Novel", BookFormat.txt, "a".repeat(64), 100, addedAt = 1L),
        )
        val locator = Locator(
            contentSHA256 = "a".repeat(64), fileByteCount = 100, format = "txt", charOffsetUTF16 = 4242,
        )
        repo.savePosition(VReaderLocator.wrapLegacy(locator), updatedAt = 5L)

        val loaded = repo.loadPosition(key)!!
        val target = ResumeResolver.resolve(loaded)

        assertTrue("a TXT legacy envelope resolves to Canonical", target is ResumeTarget.Canonical)
        assertEquals(4242, (target as ResumeTarget.Canonical).locator.charOffsetUTF16)
        // It is NOT a Readium precise locator.
        assertEquals(vreader.contracts.ReaderLocatorEngine.epubWKWebView, loaded.engine)
    }
}
