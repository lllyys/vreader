package com.vreader.app.backup

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.backup.net.KeystoreSecretCipher
import com.vreader.app.backup.net.WebDavClient
import com.vreader.app.backup.net.WebDavServerStore
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import com.vreader.app.reader.BookOpener
import com.vreader.app.reader.ReadiumLocatorReconstructor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
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
import java.util.UUID

/**
 * Feature #135 WI-8 — the LIVE WebDAV round-trip for a BOOKMARK, end-to-end (Gate-5 acceptance, rides WI-9).
 *
 * Adapts #132's [AnnotationBackupRoundTripConnectedTest] (the highlight/note round-trip) for the bookmark
 * lifecycle #135 lit up. It proves the four bookmark-restore guarantees the plan (WI-8) names:
 *  1. a bookmark created at a known position survives backup -> wipe -> restore over the REAL #132 path,
 *     restored under its ORIGINAL UUID with its canonical position intact;
 *  2. the restored (canonical-only, no precise Readium JSON) bookmark reconstructs a Readium locator via
 *     [ReadiumLocatorReconstructor] against the actual restored EPUB publication (the fresh-process /
 *     backup-restored jump path). A non-null reconstruction resolving to the bookmarked resource is the
 *     landing precondition (`navigator.go(readium)` in WI-9's live navigator);
 *  3. a SECOND restore does NOT duplicate the bookmark (the WI-3 `(bookKey, profileKey)` unique index +
 *     the UUID-preserving insert-if-absent seam — exactly one row after a re-restore);
 *  4. a renamed / unresolvable-resource canonical -> reconstruction null -> the sheet stays open (no crash,
 *     no invented error surface — rule 51).
 *
 * The #116/#127 lesson is that the CONNECTED gate catches device-only XML/crypto bugs a JVM run misses, and
 * that Readium publication opening + reconstruction are real-parser behaviors, so they belong on the
 * emulator. Skips unless `scripts/run-webdav-roundtrip.sh` passes the `webdavBaseUrl` instrumentation arg
 * (the same guard the #132 template uses). The LIVE emulator execution rides WI-9 acceptance; the WI-8 gate
 * is COMPILE of the androidTest source set.
 */
@RunWith(AndroidJUnit4::class)
class BookmarkBackupRestoreJumpTest {

    @Test
    fun bookmark_survives_backup_then_restore_and_jumps_overLiveWebDav() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        val baseUrl = args.getString("webdavBaseUrl")
        assumeNotNull("set -e webdavBaseUrl to run (via scripts/run-webdav-roundtrip.sh)", baseUrl)
        val user = args.getString("webdavUser") ?: "vreader"
        val pass = args.getString("webdavPass") ?: "vreader"

        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val ctx = instrumentation.targetContext
        val db = Room.inMemoryDatabaseBuilder(ctx, VReaderDatabase::class.java).build()
        val repo = LibraryRepository(db.bookDao(), db.readingPositionDao())
        val annotations = AnnotationsRepository(db.annotationDao())
        val booksDir = File(ctx.cacheDir, "wi8-bm-books-${UUID.randomUUID()}").apply { mkdirs() }
        val importer = BookImporter(booksDir, repo, Dispatchers.IO)
        val prefsFile = File(ctx.filesDir, "wi8-bm-${UUID.randomUUID()}.preferences_pb")
        val store = WebDavServerStore(
            PreferenceDataStoreFactory.create { prefsFile },
            KeystoreSecretCipher("vreader.test.webdav.bm"),
        )
        try {
            store.upsert("srv", "rclone", baseUrl!!, user, pass, wifiOnly = false)
            val service = WebDavBackupService(
                store, repo, importer,
                BackupCollector(repo, annotationsRepository = annotations),
                "ConnectedTest", "0.14.0",
                transportFactory = { b, u, p -> WebDavClient(b, u, p) },
                ioDispatcher = Dispatchers.IO,
                annotationsRepository = annotations,  // restore re-creates bookmarks under their UUIDs
            )

            val test = service.testConnection(ServerDraft("rclone", baseUrl, user, pass, false))
            assertTrue("connection ok: $test", test is TestResult.Ok)

            // Import a real EPUB (from the instrumentation assets, mirroring the reader connected tests) so
            // the restored publication actually opens + the canonical href resolves.
            val epubBytes = instrumentation.context.assets.open("minimal.epub").use { it.readBytes() }
            val book = importer.importStream(
                "content://test/minimal.epub", "minimal.epub", ByteArrayInputStream(epubBytes),
            )

            // Discover a REAL, resolvable href from the opened publication so the reconstruction actually
            // resolves (a hard-coded href couples the test to the fixture's internal layout).
            val realHref = BookOpener(ctx).open(File(book.localFilePath!!)).let { pub ->
                try { pub.readingOrder.first().href.toString() } finally { pub.close() }
            }

            // Create a bookmark at a KNOWN canonical position (via the toggle path #135 lit up). The toggle
            // creates exactly one row; capture its UUID via allBookmarks().
            val bookmarked = Locator(
                book.contentSHA256, book.fileByteCount, "epub", href = realHref, progression = 0.25,
            )
            annotations.toggleBookmark(book.fingerprintKey, title = null, locator = bookmarked)
            val created = annotations.allBookmarks().single()
            assertEquals("the created bookmark points at the known position", bookmarked, created.locator)
            val originalUuid = created.id

            // Back up to the live server (draining the flow is what performs the upload).
            service.startBackup("srv").drain()

            // Wipe locally — the book AND every bookmark.
            repo.deleteBook(book.fingerprintKey)
            for (b in annotations.allBookmarks()) annotations.removeBookmark(b.id)
            assertNull(repo.findBook(book.fingerprintKey))
            assertTrue("bookmarks wiped before restore", annotations.allBookmarks().isEmpty())

            // List → pick OUR backup deterministically (the one we just wrote is `latest`; a reused live
            // server may hold older archives, so never "first with books>=1") → selectively restore.
            val list = service.listBackups("srv")
            assertTrue("listBackups ok: $list", list is BackupListResult.Ok)
            val backups = (list as BackupListResult.Ok).backups
            val summary = backups.firstOrNull { it.latest && it.books >= 1 }
                ?: backups.firstOrNull { it.books >= 1 }
            assertNotNull("the backup we just wrote (latest) exists", summary)
            restoreExpectingSuccess(service, summary!!.id, setOf(book.fingerprintKey))

            // (1) restored under the ORIGINAL UUID with its canonical position intact.
            val restored = annotations.allBookmarks().single()
            assertEquals("bookmark restored under its original UUID", originalUuid, restored.id)
            assertEquals("the canonical position is byte-stable across the round-trip", bookmarked, restored.locator)

            // (2) the restored canonical-only bookmark reconstructs a Readium locator against the RESTORED
            //     publication (the fresh-process / backup-restored jump path). (4) a renamed/unresolvable
            //     resource reconstructs to null → the sheet stays open.
            val restoredBook = repo.findBook(book.fingerprintKey)
            assertNotNull("the book was materialized by the restore", restoredBook)
            val pub = BookOpener(ctx).open(File(restoredBook!!.localFilePath!!))
            try {
                val readium = ReadiumLocatorReconstructor(book.fingerprintKey, pub).toReadium(restored.locator)
                assertNotNull("the restored canonical-only bookmark reconstructs a Readium locator", readium)
                assertEquals("the reconstruction resolves to the bookmarked resource", realHref, readium!!.href.toString())
                // A real POSITION, not just an href match: the canonical progression is carried into the
                // reconstructed Readium locator (the landing precision `navigator.go` uses at WI-9).
                assertEquals(
                    "the reconstruction carries the bookmark's canonical progression",
                    0.25, readium.locations.progression!!, 1e-9,
                )

                val renamed = restored.locator.copy(href = "renamed-does-not-exist.xhtml")
                val nullRecon = ReadiumLocatorReconstructor(book.fingerprintKey, pub).toReadium(renamed)
                assertNull("a renamed/unresolvable resource reconstructs to null (sheet stays open, rule 51)", nullRecon)
            } finally {
                pub.close()
            }

            // (3a) re-restore does NOT duplicate — the UUID-preserving insert-if-absent.
            restoreExpectingSuccess(service, summary.id, setOf(book.fingerprintKey))
            val afterReRestore = annotations.allBookmarks()
            assertEquals("re-restore inserts no duplicate bookmark", 1, afterReRestore.size)
            assertEquals("the single surviving bookmark keeps its original UUID", originalUuid, afterReRestore.single().id)

            // (3b) the WI-3 (bookKey, profileKey) UNIQUE INDEX fallback — NOT just the UUID primary key: a
            // LOCAL bookmark at the SAME position but with a DIFFERENT UUID (a device that bookmarked the
            // spot independently) must not co-exist with the restored one after a re-restore. Wipe, recreate
            // the same-position bookmark via the toggle path (fresh UUID), then re-restore: the restored row
            // (its own UUID) collides on (bookKey, profileKey) and is suppressed → still exactly one row.
            for (b in annotations.allBookmarks()) annotations.removeBookmark(b.id)
            annotations.toggleBookmark(book.fingerprintKey, title = null, locator = bookmarked)
            val localRow = annotations.allBookmarks().single()
            assertTrue("the local same-position bookmark has a DIFFERENT UUID", localRow.id != originalUuid)
            restoreExpectingSuccess(service, summary.id, setOf(book.fingerprintKey))
            val afterProfileFallback = annotations.allBookmarks()
            assertEquals("the profile-key unique index keeps exactly one bookmark per position", 1, afterProfileFallback.size)
        } finally {
            db.close()
            booksDir.deleteRecursively()
            prefsFile.delete()
        }
    }

    // ---- helpers ----

    /** Drain a backup progress flow to completion — the upload happens as the collector's flow drains
     *  (the #132 template's `.toList()` idiom, without materializing the events we don't assert on). */
    private suspend fun Flow<BackupProgress>.drain() = collect { }

    /** Drive a selective restore to its terminal Result and assert success (the template's last()-as-Result
     *  idiom). Both the first restore and the re-restore go through this same real #132 path. */
    private suspend fun restoreExpectingSuccess(service: WebDavBackupService, backupId: String, selection: Set<String>) {
        var terminal: RestoreProgress.Result? = null
        service.restore(backupId, selection).collect { if (it is RestoreProgress.Result) terminal = it }
        assertNotNull("restore produced a terminal Result", terminal)
        assertEquals(RestoreOutcome.success, terminal!!.outcome)
    }
}
