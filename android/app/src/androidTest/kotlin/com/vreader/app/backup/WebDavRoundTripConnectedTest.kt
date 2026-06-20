package com.vreader.app.backup

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.backup.net.KeystoreSecretCipher
import com.vreader.app.backup.net.WebDavClient
import com.vreader.app.backup.net.WebDavServerStore
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeNotNull
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.Locator
import vreader.contracts.VReaderLocator
import java.io.ByteArrayInputStream
import java.io.File
import java.time.Instant
import java.util.UUID

/**
 * Feature #116 WI-6 — the LIVE WebDAV round-trip (Gate-5 acceptance). Drives the REAL WebDavClient
 * (PROPFIND / MKCOL / PUT / MOVE / GET / getStream) + the on-device AndroidKeyStore SecretCipher
 * + WebDavBackupService end-to-end against an `rclone serve webdav` instance on the Mac host
 * (reachable from the emulator at 10.0.2.2). Skips unless `scripts/run-webdav-roundtrip.sh` passes
 * the `webdavBaseUrl` instrumentation arg, so a normal connectedAndroidTest run doesn't require a
 * server.
 */
@RunWith(AndroidJUnit4::class)
class WebDavRoundTripConnectedTest {

    @Test
    fun backup_then_restore_overLiveWebDav() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val baseUrl = args.getString("webdavBaseUrl")
        assumeNotNull("set -e webdavBaseUrl to run (via scripts/run-webdav-roundtrip.sh)", baseUrl)
        val user = args.getString("webdavUser") ?: "vreader"
        val pass = args.getString("webdavPass") ?: "vreader"

        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val db = Room.inMemoryDatabaseBuilder(ctx, VReaderDatabase::class.java).build()
        val repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        val booksDir = File(ctx.cacheDir, "wi6-books-${UUID.randomUUID()}").apply { mkdirs() }
        val importer = BookImporter(booksDir, repo, Dispatchers.IO)
        val prefsFile = File(ctx.filesDir, "wi6-${UUID.randomUUID()}.preferences_pb")
        val store = WebDavServerStore(
            PreferenceDataStoreFactory.create { prefsFile },
            KeystoreSecretCipher("vreader.test.webdav"),  // exercises the REAL AndroidKeyStore cipher
        )
        try {
            store.upsert("srv", "rclone", baseUrl!!, user, pass, wifiOnly = false)
            val service = WebDavBackupService(
                store, repo, importer, BackupCollector(repo), "ConnectedTest", "0.7.7",
                transportFactory = { b, u, p -> WebDavClient(b, u, p) },
                ioDispatcher = Dispatchers.IO,
            )

            // testConnection against the live server.
            val test = service.testConnection(ServerDraft("rclone", baseUrl, user, pass, false))
            assertTrue("connection ok: $test", test is TestResult.Ok)

            // Import a unique book + a saved position.
            val content = "EPUB-ROUNDTRIP-${UUID.randomUUID()}"
            val book = importer.importStream("content://t", "RoundTrip.epub", ByteArrayInputStream(content.toByteArray()))
            repo.savePosition(
                VReaderLocator.wrapLegacy(
                    Locator(book.contentSHA256, book.fileByteCount, "epub", href = "ch1.xhtml", progression = 0.37)
                ),
                updatedAt = Instant.now().toEpochMilli(),
            )

            // Back up to the live server.
            service.startBackup("srv").toList()

            // Wipe locally.
            repo.deleteBook(book.fingerprintKey)
            assertNull(repo.findBook(book.fingerprintKey))

            // List → find our backup → restore → book + position come back.
            val list = service.listBackups("srv")
            assertTrue("listBackups ok: $list", list is BackupListResult.Ok)
            val summary = (list as BackupListResult.Ok).backups.firstOrNull { it.books >= 1 }
            assertNotNull("a backup with our book exists", summary)
            val result = service.restore(summary!!.id, setOf(book.fingerprintKey)).toList()
                .last() as RestoreProgress.Result
            assertEquals(RestoreOutcome.success, result.outcome)
            assertEquals(book.fingerprintKey, repo.findBook(book.fingerprintKey)?.fingerprintKey)
            assertEquals(0.37, repo.loadPosition(book.fingerprintKey)!!.legacyLocator!!.progression!!, 1e-9)
        } finally {
            db.close()
            booksDir.deleteRecursively()
            prefsFile.delete()
        }
    }
}
