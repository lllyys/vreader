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
 * Feature #115 WI-3 — the PDF resume contract: a PDF position is a LEGACY `VReaderLocator`
 * carrying `page`. It must round-trip the repository and resolve to `ResumeTarget.Canonical`
 * (mirrors `TxtResumeTest` but for the `page` field).
 */
@RunWith(RobolectricTestRunner::class)
class PdfResumeTest {
    private lateinit var db: VReaderDatabase
    private lateinit var repo: LibraryRepository
    private val key = "pdf:${"c".repeat(64)}:2048"

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java).build()
        repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
    }

    @After fun tearDown() = db.close()

    @Test
    fun pdfLegacyEnvelope_roundTrips_andResolvesCanonicalPage() = runBlocking {
        repo.upsertBook(Book(key, "Doc", BookFormat.pdf, "c".repeat(64), 2048, addedAt = 1L))
        val locator = Locator(contentSHA256 = "c".repeat(64), fileByteCount = 2048, format = "pdf", page = 17)
        repo.savePosition(VReaderLocator.wrapLegacy(locator), updatedAt = 5L)

        val loaded = repo.loadPosition(key)!!
        val target = ResumeResolver.resolve(loaded)

        assertTrue("a PDF legacy envelope resolves to Canonical", target is ResumeTarget.Canonical)
        assertEquals(17, (target as ResumeTarget.Canonical).locator.page)
        assertEquals(vreader.contracts.ReaderLocatorEngine.epubWKWebView, loaded.engine)
    }
}
