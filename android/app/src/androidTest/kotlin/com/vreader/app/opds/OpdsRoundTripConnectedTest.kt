package com.vreader.app.opds

import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

/**
 * Feature #117 WI-2 — the LIVE OPDS round-trip (Gate-5 acceptance). Drives the REAL OpdsClient
 * (HTTP fetch + download) + OpdsParser + OpdsAcquisitionService + BookImporter end-to-end against a
 * local HTTP server on the Mac host (reachable from the emulator at 10.0.2.2) serving a static OPDS
 * feed + an EPUB. Skips unless `scripts/run-opds-roundtrip.sh` passes the `opdsFeedUrl` arg.
 */
@RunWith(AndroidJUnit4::class)
class OpdsRoundTripConnectedTest {

    @Test
    fun fetch_parse_download_import_overLiveHttp() = runBlocking {
        val feedUrl = InstrumentationRegistry.getArguments().getString("opdsFeedUrl")
        assumeNotNull("set -e opdsFeedUrl to run (via scripts/run-opds-roundtrip.sh)", feedUrl)

        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val db = Room.inMemoryDatabaseBuilder(ctx, VReaderDatabase::class.java).build()
        val booksDir = File(ctx.cacheDir, "opds-${UUID.randomUUID()}").apply { mkdirs() }
        try {
            val repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
            val importer = BookImporter(booksDir, repo, Dispatchers.IO)
            val client = OpdsClient()
            val service = OpdsAcquisitionService(client::download, importer)

            // Fetch + parse the live OPDS feed.
            val feed = client.fetchFeed(feedUrl!!)
            assertTrue("feed has entries", feed.entries.isNotEmpty())
            val entry = feed.entries.first { it.acquisitionLinks.any { l -> l.isAutoImportable } }

            // Download + import the book over real HTTP.
            val book = service.importEntry(entry, feed.baseUrl)
            assertNotNull("book imported", book.fingerprintKey)
            assertNotNull("book is in the library", repo.findBook(book.fingerprintKey))
            assertTrue("local artifact exists", File(book.localFilePath!!).exists())
        } finally {
            db.close()
            booksDir.deleteRecursively()
        }
    }
}
