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
 * Feature #112 — the MD resume contract reuses the TXT LEGACY path: an .md position is a
 * legacy (non-Readium) `VReaderLocator` carrying `charOffsetUTF16`. It must round-trip the
 * repository and resolve to `ResumeTarget.Canonical` for `format = "md"` exactly as it does
 * for txt (mirrors `TxtResumeTest`); the reader's `computeInitialIndex` then maps the offset
 * to a chunk. Offsets index the RAW markdown source, so rendering can't drift resume.
 */
@RunWith(RobolectricTestRunner::class)
class MdResumeTest {
    private lateinit var db: VReaderDatabase
    private lateinit var repo: LibraryRepository
    private val key = "md:${"b".repeat(64)}:200"

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java).build()
        repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
    }

    @After fun tearDown() = db.close()

    @Test
    fun mdLegacyEnvelope_roundTrips_andResolvesCanonical() = runBlocking {
        repo.upsertBook(Book(key, "Note", BookFormat.md, "b".repeat(64), 200, addedAt = 1L))
        val locator = Locator(
            contentSHA256 = "b".repeat(64), fileByteCount = 200, format = "md", charOffsetUTF16 = 2528,
        )
        repo.savePosition(VReaderLocator.wrapLegacy(locator), updatedAt = 5L)

        val loaded = repo.loadPosition(key)!!
        val target = ResumeResolver.resolve(loaded)

        assertTrue("an MD legacy envelope resolves to Canonical", target is ResumeTarget.Canonical)
        assertEquals(2528, (target as ResumeTarget.Canonical).locator.charOffsetUTF16)
        assertEquals(vreader.contracts.ReaderLocatorEngine.epubWKWebView, loaded.engine)
    }
}
