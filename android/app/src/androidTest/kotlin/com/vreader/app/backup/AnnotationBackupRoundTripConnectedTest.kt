package com.vreader.app.backup

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.annotations.AnnotationColor
import com.vreader.app.annotations.AnnotationsRepository
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
import java.io.ByteArrayInputStream
import java.io.File
import java.time.Instant
import java.util.UUID

/**
 * Feature #132 WI-8 — the LIVE WebDAV round-trip for annotations.json (Gate-5 acceptance, rides WI-9).
 * Drives the REAL WebDavClient + WebDavBackupService end-to-end against an `rclone serve webdav`
 * instance on the Mac host (reachable from the emulator at 10.0.2.2): import a book, add a highlight +
 * a note, back up, wipe the book AND the annotations, then selectively restore and assert the highlight
 * and note come back preserving their UUIDs. The #116/#127 lesson is that the connected gate catches
 * device-only XML/crypto bugs a JVM/Robolectric run misses. Skips unless
 * `scripts/run-webdav-roundtrip.sh` passes the `webdavBaseUrl` instrumentation arg.
 */
@RunWith(AndroidJUnit4::class)
class AnnotationBackupRoundTripConnectedTest {

    @Test
    fun annotations_survive_backup_then_restore_overLiveWebDav() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val baseUrl = args.getString("webdavBaseUrl")
        assumeNotNull("set -e webdavBaseUrl to run (via scripts/run-webdav-roundtrip.sh)", baseUrl)
        val user = args.getString("webdavUser") ?: "vreader"
        val pass = args.getString("webdavPass") ?: "vreader"

        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val db = Room.inMemoryDatabaseBuilder(ctx, VReaderDatabase::class.java).build()
        val repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        val annotations = AnnotationsRepository(db.annotationDao())
        val booksDir = File(ctx.cacheDir, "wi8-books-${UUID.randomUUID()}").apply { mkdirs() }
        val importer = BookImporter(booksDir, repo, Dispatchers.IO)
        val prefsFile = File(ctx.filesDir, "wi8-${UUID.randomUUID()}.preferences_pb")
        val store = WebDavServerStore(
            PreferenceDataStoreFactory.create { prefsFile },
            KeystoreSecretCipher("vreader.test.webdav"),
        )
        try {
            store.upsert("srv", "rclone", baseUrl!!, user, pass, wifiOnly = false)
            val service = WebDavBackupService(
                store, repo, importer,
                BackupCollector(repo, annotationsRepository = annotations),
                "ConnectedTest", "0.14.0",
                transportFactory = { b, u, p -> WebDavClient(b, u, p) },
                ioDispatcher = Dispatchers.IO,
                annotationsRepository = annotations,  // restore re-creates highlights + notes
            )

            val test = service.testConnection(ServerDraft("rclone", baseUrl, user, pass, false))
            assertTrue("connection ok: $test", test is TestResult.Ok)

            // Import a unique book + a highlight + a note anchored in it.
            val content = "EPUB-ANNOTATIONS-${UUID.randomUUID()}"
            val book = importer.importStream("content://t", "Annotated.epub", ByteArrayInputStream(content.toByteArray()))
            val loc = Locator(book.contentSHA256, book.fileByteCount, "epub", href = "ch1.xhtml", charOffsetUTF16 = 42)
            val loc2 = Locator(book.contentSHA256, book.fileByteCount, "epub", href = "ch1.xhtml", charOffsetUTF16 = 99)
            val highlight = annotations.addHighlight(book.fingerprintKey, AnnotationColor.DEFAULT, "the whale", loc, anchor = null)
            val note = annotations.addNote(book.fingerprintKey, "reminder", loc2)

            // Back up to the live server.
            service.startBackup("srv").toList()

            // Wipe locally — the book AND the annotations.
            repo.deleteBook(book.fingerprintKey)
            for (h in annotations.allHighlights()) annotations.removeHighlight(h.id)
            for (n in annotations.allNotes()) annotations.removeNote(n.id)
            assertNull(repo.findBook(book.fingerprintKey))
            assertTrue("annotations wiped before restore", annotations.allHighlights().isEmpty())

            // List → find our backup → selectively restore → book + annotations come back.
            val list = service.listBackups("srv")
            assertTrue("listBackups ok: $list", list is BackupListResult.Ok)
            val summary = (list as BackupListResult.Ok).backups.firstOrNull { it.books >= 1 }
            assertNotNull("a backup with our book exists", summary)
            val result = service.restore(summary!!.id, setOf(book.fingerprintKey)).toList()
                .last() as RestoreProgress.Result
            assertEquals(RestoreOutcome.success, result.outcome)

            val restoredH = annotations.findHighlight(highlight.id)
            assertNotNull("highlight restored under its original UUID", restoredH)
            assertEquals(highlight.id, restoredH!!.id)
            assertEquals("the whale", restoredH.selectedText)
            val restoredNotes = annotations.allNotes()
            assertEquals(1, restoredNotes.size)
            assertEquals(note.id, restoredNotes[0].id)
            assertEquals("reminder", restoredNotes[0].content)
        } finally {
            db.close()
            booksDir.deleteRecursively()
            prefsFile.delete()
        }
    }
}
