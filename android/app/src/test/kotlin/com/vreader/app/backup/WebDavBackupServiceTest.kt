package com.vreader.app.backup

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.backup.net.SecretCipher
import com.vreader.app.backup.net.WebDavEntry
import com.vreader.app.backup.net.WebDavErrorKind
import com.vreader.app.backup.net.WebDavException
import com.vreader.app.backup.net.WebDavServerStore
import com.vreader.app.backup.net.WebDavTransport
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.Locator
import vreader.contracts.VReaderLocator
import java.io.ByteArrayInputStream
import java.io.InputStream
import java.time.Instant

/**
 * Feature #116 WI-5b — the WebDavBackupService over an IN-MEMORY fake WebDAV transport: a full
 * import → backup → wipe → list → restore round-trip (books + positions), plus testConnection /
 * error mapping. Proves the orchestration end-to-end without a live server (WI-6 does the real one).
 */
@RunWith(RobolectricTestRunner::class)
class WebDavBackupServiceTest {
    @get:Rule val tmp = TemporaryFolder()

    /** Map-backed WebDAV: PUT stores, GET/getStream read, PROPFIND lists direct children, MOVE
     *  renames, mkcol is implicit, exists/delete operate on the map. */
    private class FakeDav : WebDavTransport {
        val files = LinkedHashMap<String, ByteArray>()
        val puts = mutableListOf<String>()
        var failAuth = false
        override suspend fun propfind(path: String): List<WebDavEntry> {
            if (failAuth) throw WebDavException(WebDavErrorKind.auth401, "401")
            val dir = path.trimEnd('/')
            val children = files.keys.filter { it.substringBeforeLast('/') == dir }
            if (dir.isNotEmpty() && children.isEmpty() && files.keys.none { it.startsWith("$dir/") }) {
                throw WebDavException(WebDavErrorKind.notFound404, "404 $path")
            }
            return children.map { WebDavEntry(it, false, files[it]?.size?.toLong()) }
        }
        override suspend fun mkcol(path: String) {}
        override suspend fun put(path: String, bytes: ByteArray) { puts += path; files[path] = bytes }
        override suspend fun putFile(path: String, file: java.io.File) { puts += path; files[path] = file.readBytes() }
        override suspend fun get(path: String): ByteArray =
            files[path] ?: throw WebDavException(WebDavErrorKind.notFound404, "404 $path")
        override suspend fun getStream(path: String): InputStream = ByteArrayInputStream(get(path))
        override suspend fun move(from: String, to: String) {
            files[to] = files.remove(from) ?: throw WebDavException(WebDavErrorKind.notFound404, "404 $from")
        }
        override suspend fun delete(path: String) { files.remove(path) }
        override suspend fun exists(path: String): Boolean = files.containsKey(path)
    }

    private val fakeCipher = object : SecretCipher {
        override fun encrypt(plaintext: String) = "enc($plaintext)"
        override fun decrypt(token: String) = token.removePrefix("enc(").removeSuffix(")")
    }

    private lateinit var db: VReaderDatabase
    private lateinit var repo: LibraryRepository
    private lateinit var importer: BookImporter
    private lateinit var store: WebDavServerStore
    private lateinit var dav: FakeDav
    private lateinit var service: WebDavBackupService
    private val now = Instant.parse("2026-06-20T12:00:00Z")

    @Before fun setUp() = runTest {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java
        ).build()
        repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        importer = BookImporter(tmp.newFolder("books"), repo, Dispatchers.Unconfined) { 1000L }
        store = WebDavServerStore(
            PreferenceDataStoreFactory.create { tmp.newFile("s.preferences_pb") }, fakeCipher
        )
        store.upsert("s1", "Home NAS", "https://nas.local/dav/", "alice", "pw", wifiOnly = true)
        dav = FakeDav()
        service = WebDavBackupService(
            store, repo, importer, BackupCollector(repo), "Pixel 7", "0.7.6",
            transportFactory = { _, _, _ -> dav }, ioDispatcher = Dispatchers.Unconfined,
            now = { now }, newBackupId = { "bkp-1" },
        )
    }

    @After fun tearDown() = db.close()

    private suspend fun importBookWithPosition(): String {
        val book = importer.importStream("content://x", "Book.epub", ByteArrayInputStream("EPUB-BYTES".toByteArray()))
        repo.savePosition(
            VReaderLocator.wrapLegacy(
                Locator(book.contentSHA256, book.fileByteCount, "epub", href = "ch1.xhtml", progression = 0.42)
            ),
            updatedAt = 7000L,
        )
        return book.fingerprintKey
    }

    @Test fun listServers_fromStore() = runTest {
        val servers = service.listServers()
        assertEquals(1, servers.size)
        assertEquals("Home NAS", servers[0].name)
        assertTrue(servers[0].wifiOnly)
    }

    @Test fun testConnection_ok_whenNoBackupsYet() = runTest {
        val result = service.testConnection(ServerDraft("Home", "https://nas/", "u", "p", true))
        assertTrue(result is TestResult.Ok)
    }

    @Test fun testConnection_mapsAuthFailure() = runTest {
        dav.failAuth = true
        val result = service.testConnection(ServerDraft("Home", "https://nas/", "u", "bad", true))
        assertTrue(result is TestResult.Fail)
        assertEquals(WebDavError.auth401, (result as TestResult.Fail).cause)
    }

    @Test fun fullRoundTrip_backup_wipe_list_restore() = runTest {
        val key = importBookWithPosition()

        // Back up → the fake server now holds the ZIP + the content-addressed blob.
        service.startBackup("s1").toList()
        assertTrue("a *.vreader.zip was written", dav.files.keys.any { it.startsWith("VReader/backups/") && it.endsWith(".vreader.zip") })
        assertTrue("a blob was published", dav.files.keys.any { it.startsWith("VReader/books/epub/") && !it.endsWith(".tmp") })
        assertTrue("no leftover .tmp", dav.files.keys.none { it.endsWith(".tmp") })

        // Wipe the local library.
        repo.deleteBook(key)
        assertNull(repo.findBook(key))
        assertEquals(0, repo.listBooks().size)

        // List → exactly one backup; load its manifest (book now shows remote).
        val list = service.listBackups("s1")
        assertTrue(list is BackupListResult.Ok)
        val summary = (list as BackupListResult.Ok).backups.single()
        assertEquals(1, summary.books)
        assertTrue(summary.latest)
        val manifest = service.loadManifest(summary.id)
        assertEquals(BookState.remote, manifest.single().state)

        // Restore → book + position come back.
        val progress = service.restore(summary.id, emptySet()).toList()
        val result = progress.last() as RestoreProgress.Result
        assertEquals(RestoreOutcome.success, result.outcome)
        assertEquals(1, result.restored)
        assertEquals(key, repo.findBook(key)?.fingerprintKey)
        assertEquals(0.42, repo.loadPosition(key)!!.legacyLocator!!.progression!!, 1e-9)
    }

    @Test fun backup_isDeduped_secondRunReusesBlob() = runTest {
        importBookWithPosition()
        service.startBackup("s1").toList()
        service.startBackup("s1").toList()  // again — the existing blob must NOT be re-uploaded
        // The blob is published via a single PUT(.tmp)→MOVE on the FIRST backup; the second
        // backup's exists()-dedupe skips it entirely.
        assertEquals("blob uploaded exactly once across two backups", 1,
            dav.puts.count { it.startsWith("VReader/books/") && it.endsWith(".tmp") })
        assertTrue("the published blob is present", dav.files.keys.any { it.startsWith("VReader/books/epub/") && !it.endsWith(".tmp") })
    }

    @Test fun retryBook_restoresSingle() = runTest {
        val key = importBookWithPosition()
        service.startBackup("s1").toList()
        repo.deleteBook(key)
        val summary = (service.listBackups("s1") as BackupListResult.Ok).backups.single()
        assertEquals(BookRestoreResult.restored, service.retryBook(summary.id, key))
        assertEquals(key, repo.findBook(key)?.fingerprintKey)
    }
}
