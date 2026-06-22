package com.vreader.app.opds

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #117 WI-2 — OpdsAcquisitionService: pick the importable acquisition (EPUB preferred, skip
 * buy/unsupported), validate the bytes are a book (content-type + magic), and import via the real
 * BookImporter. In-memory Room (Robolectric); the download is faked.
 */
@RunWith(RobolectricTestRunner::class)
class OpdsAcquisitionServiceTest {
    @get:Rule val tmp = TemporaryFolder()

    private lateinit var db: VReaderDatabase
    private lateinit var repo: LibraryRepository
    private lateinit var importer: BookImporter
    private val downloads = HashMap<String, OpdsDownload>()
    private val base = "https://cat.example.org/opds/root.xml"

    private val epubBytes = byteArrayOf('P'.code.toByte(), 'K'.code.toByte(), 0x03, 0x04) + "epub-body".toByteArray()

    private fun acq(rel: String, href: String, type: String) = OpdsLink(rel, href, type)
    private fun entry(vararg links: OpdsLink, title: String = "Moby-Dick") =
        OpdsEntry(title = title, id = "urn:b", links = links.toList())

    private fun service() = OpdsAcquisitionService(
        download = { url -> downloads[url] ?: throw OpdsError.Network("404 $url") },
        importer = importer,
    )

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java).build()
        repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        importer = BookImporter(tmp.newFolder("books"), repo, Dispatchers.Unconfined) { 1000L }
    }

    @After fun tearDown() = db.close()

    @Test fun importsOpenAccessEpub_intoLibrary() = runTest {
        val href = "https://cat.example.org/opds/files/moby.epub"
        downloads[href] = OpdsDownload(epubBytes, "application/epub+zip", href)
        val e = entry(acq("http://opds-spec.org/acquisition/open-access", "files/moby.epub", "application/epub+zip"))
        val book = service().importEntry(e, base)
        assertEquals("Moby-Dick", book.title)
        assertEquals(book.fingerprintKey, repo.findBook(book.fingerprintKey)?.fingerprintKey)
    }

    @Test fun prefersEpubOverPdf() = runTest {
        val epub = "https://cat.example.org/opds/m.epub"; val pdf = "https://cat.example.org/opds/m.pdf"
        downloads[epub] = OpdsDownload(epubBytes, "application/epub+zip", epub)
        downloads[pdf] = OpdsDownload("%PDF-1.4".toByteArray(), "application/pdf", pdf)
        val e = entry(
            acq("http://opds-spec.org/acquisition", "m.pdf", "application/pdf"),
            acq("http://opds-spec.org/acquisition", "m.epub", "application/epub+zip"),
        )
        val book = service().importEntry(e, base)
        assertEquals("epub", book.originalFormat.name)  // EPUB chosen despite PDF listed first
    }

    @Test fun skipsNonImportableAcquisition_throws() = runTest {
        val e = entry(acq("http://opds-spec.org/acquisition/buy", "buy.epub", "application/epub+zip"))
        val ex = runCatching { service().importEntry(e, base) }.exceptionOrNull()
        assertTrue(ex is OpdsError.UnsupportedAcquisition)
    }

    @Test fun rejectsHtmlLoginPage() = runTest {
        val href = "https://cat.example.org/opds/m.epub"
        downloads[href] = OpdsDownload("<html>login</html>".toByteArray(), "text/html; charset=utf-8", href)
        val e = entry(acq("http://opds-spec.org/acquisition/open-access", "m.epub", "application/epub+zip"))
        val ex = runCatching { service().importEntry(e, base) }.exceptionOrNull()
        assertTrue(ex is OpdsError.NotABook)
    }

    @Test fun rejectsWrongMagicBytes() = runTest {
        val href = "https://cat.example.org/opds/m.epub"
        downloads[href] = OpdsDownload("not a zip".toByteArray(), "application/epub+zip", href)
        val e = entry(acq("http://opds-spec.org/acquisition/open-access", "m.epub", "application/epub+zip"))
        val ex = runCatching { service().importEntry(e, base) }.exceptionOrNull()
        assertTrue(ex is OpdsError.NotABook)
    }

    @Test fun import_isIdempotent() = runTest {
        val href = "https://cat.example.org/opds/files/moby.epub"
        downloads[href] = OpdsDownload(epubBytes, "application/epub+zip", href)
        val e = entry(acq("http://opds-spec.org/acquisition/open-access", "files/moby.epub", "application/epub+zip"))
        service().importEntry(e, base)
        service().importEntry(e, base)  // same bytes → same key, no dup
        assertEquals(1, repo.listBooks().size)
    }
}
