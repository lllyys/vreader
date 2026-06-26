package com.vreader.app.opds.ui

import android.os.SystemClock
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.backup.net.SecretCipher
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import com.vreader.app.opds.OpdsAcquisitionService
import com.vreader.app.opds.OpdsSource
import com.vreader.app.opds.OpdsSourceStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeNotNull
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID

/**
 * Feature #120 WI-4 — the FINAL-WI acceptance: drives the WI-2 + WI-3 view models end-to-end through
 * the REAL backend (OpdsSourceStore save → OpdsBrowseViewModel fetch+parse+download+import →
 * LibraryRepository) against a LIVE local OPDS feed (host alias 10.0.2.2 from the emulator). Proves
 * the user path "save a catalog → browse it → download an entry → it lands In Library". Skips unless
 * `scripts/run-opds-roundtrip.sh` passes the `opdsFeedUrl` arg.
 */
@RunWith(AndroidJUnit4::class)
class OpdsUiRoundTripConnectedTest {

    private val fakeCipher = object : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }

    @Test
    fun save_browse_download_inLibrary_overLiveHttp() = runBlocking {
        val feedUrl = InstrumentationRegistry.getArguments().getString("opdsFeedUrl")
        assumeNotNull("set -e opdsFeedUrl to run (via scripts/run-opds-roundtrip.sh)", feedUrl)

        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val db = Room.inMemoryDatabaseBuilder(ctx, VReaderDatabase::class.java).build()
        val booksDir = File(ctx.cacheDir, "opds-ui-${UUID.randomUUID()}").apply { mkdirs() }
        val prefs = File(ctx.cacheDir, "opds-ui-${UUID.randomUUID()}.preferences_pb")
        try {
            val repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
            val importer = BookImporter(booksDir, repo, Dispatchers.IO)
            val store = OpdsSourceStore(PreferenceDataStoreFactory.create { prefs }, fakeCipher)

            // 1. WI-2 — save the catalog as a source.
            val sourcesVm = OpdsSourcesViewModel(store)
            sourcesVm.openAdd(name = "Round-Trip Catalog", url = feedUrl!!)
            sourcesVm.save()
            val source = awaitSource(store)
            assertEquals(feedUrl, source.url)

            // 2. WI-3 — browse the saved source through its origin-scoped client.
            val client = store.clientFor(source)
            val service = OpdsAcquisitionService(client::download, importer)
            val browseVm = OpdsBrowseViewModel(
                rootTitle = source.name, rootUrl = source.url,
                fetcher = client::fetchFeed,
                importer = { e, b -> service.importEntry(e, b) },
                libraryFlow = repo.observeLibrary(),
            )
            val feed = awaitBrowse(browseVm) { it.phase == OpdsBrowsePhase.feed && it.entries.isNotEmpty() }
            val entry = feed.entries.first()
            assertEquals(OpdsItemState.remote, entry.state)

            // 3. download → In-Library, and the book is really in the Room library.
            browseVm.download(entry.key)
            val done = awaitBrowse(browseVm) { st -> st.entries.firstOrNull { it.key == entry.key }?.state == OpdsItemState.library }
            assertEquals(OpdsItemState.library, done.entries.first { it.key == entry.key }.state)

            val books = repo.listBooks()
            assertTrue("a book was imported", books.isNotEmpty())
            val book = books.first()
            assertNotNull("imported book has a local artifact", book.localFilePath)
            assertTrue("local artifact exists on disk", File(book.localFilePath!!).exists())
            assertTrue("provenance is the opds source", book.sourceUri?.startsWith("opds://") == true)
        } finally {
            db.close(); booksDir.deleteRecursively(); prefs.delete()
        }
    }

    private suspend fun awaitSource(store: OpdsSourceStore) =
        await(5_000) { store.list().firstOrNull() } ?: error("source was not saved")

    private suspend fun awaitBrowse(vm: OpdsBrowseViewModel, predicate: (OpdsBrowseState) -> Boolean): OpdsBrowseState =
        await(20_000) { vm.state.value.takeIf(predicate) } ?: error("browse never reached the expected state: ${vm.state.value}")

    private suspend fun <T> await(timeoutMs: Long, probe: suspend () -> T?): T? {
        val deadline = SystemClock.uptimeMillis() + timeoutMs
        while (SystemClock.uptimeMillis() < deadline) {
            probe()?.let { return it }
            delay(50)
        }
        return null
    }
}
