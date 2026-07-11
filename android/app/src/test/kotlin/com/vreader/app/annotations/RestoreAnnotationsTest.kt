package com.vreader.app.annotations

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.BookEntity
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.Locator
import vreader.contracts.backup.BackupAnnotationsEnvelope
import vreader.contracts.backup.BackupBookmark
import vreader.contracts.backup.BackupHighlight
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupNote
import java.time.Instant

/**
 * Feature #132 WI-6b — the UUID-preserving transactional restore seam
 * ([AnnotationsRepository.restoreAnnotations]) over a real in-memory Room db.
 * The backup's `locatorJSON` is a PLAIN `Locator` JSON (`BackupJson.encode(locator)`),
 * the same decodable form positions use — the contract WI-8 writes to.
 */
@RunWith(RobolectricTestRunner::class)
class RestoreAnnotationsTest {
    private lateinit var db: VReaderDatabase
    private lateinit var repo: AnnotationsRepository
    private val key = "epub:${"a".repeat(64)}:2048"

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java,
        ).build()
        repo = AnnotationsRepository(db.annotationDao())
        runBlocking {
            db.bookDao().upsert(BookEntity(key, "Moby Dick", "epub", "a".repeat(64), 2048L, null, null, 1L, null))
        }
    }

    @After fun tearDown() = db.close()

    private fun loc(cfi: String) =
        Locator(contentSHA256 = "a".repeat(64), fileByteCount = 2048L, format = "epub", href = "c.xhtml", cfi = cfi)

    private fun locJson(cfi: String) = BackupJson.encode(loc(cfi))

    private fun highlight(id: String, cfi: String = "/4:1", ts: Long = 1000L) = BackupHighlight(
        highlightId = id, bookFingerprintKey = key, locatorJSON = locJson(cfi),
        selectedText = "text-$id", color = "yellow", note = null,
        createdAt = Instant.ofEpochMilli(ts), updatedAt = Instant.ofEpochMilli(ts),
    )

    private fun note(id: String, cfi: String = "/8:1", ts: Long = 2000L) = BackupNote(
        annotationId = id, bookFingerprintKey = key, locatorJSON = locJson(cfi),
        content = "note-$id", createdAt = Instant.ofEpochMilli(ts), updatedAt = Instant.ofEpochMilli(ts),
    )

    private fun bookmark(id: String, cfi: String = "/2:0", ts: Long = 3000L) = BackupBookmark(
        bookmarkId = id, bookFingerprintKey = key, locatorJSON = locJson(cfi),
        title = "Chapter", createdAt = Instant.ofEpochMilli(ts), updatedAt = Instant.ofEpochMilli(ts),
    )

    private fun env(
        highlights: List<BackupHighlight> = emptyList(),
        notes: List<BackupNote> = emptyList(),
        bookmarks: List<BackupBookmark> = emptyList(),
    ) = BackupAnnotationsEnvelope(schemaVersion = 1, highlights = highlights, bookmarks = bookmarks, notes = notes)

    @Test fun restore_preservesBackedUpUuid_andTimestamps_notFreshId() = runBlocking {
        val backupId = "11111111-2222-3333-4444-555555555555"
        val report = repo.restoreAnnotations(
            env(highlights = listOf(highlight(backupId, ts = 4242L))), setOf(key),
        )
        assertEquals(1, report.highlights.applied)
        // The stored row's id must equal the BACKUP id (not a freshly minted UUID).
        val stored = repo.findHighlight(backupId)
        assertNotNull("restored under the backed-up UUID", stored)
        assertEquals(backupId, stored!!.id)
        assertEquals("createdAt preserved verbatim", 4242L, stored.createdAt)
        assertEquals("updatedAt preserved verbatim", 4242L, stored.updatedAt)
    }

    @Test fun restore_isIdempotent_secondPassAppliesZero() = runBlocking {
        val e = env(
            highlights = listOf(highlight("h-1"), highlight("h-2", cfi = "/6:1")),
            notes = listOf(note("n-1")),
            bookmarks = listOf(bookmark("b-1")),
        )
        val first = repo.restoreAnnotations(e, setOf(key))
        assertEquals(2, first.highlights.applied)
        assertEquals(1, first.notes.applied)
        assertEquals(1, first.bookmarks.applied)

        val second = repo.restoreAnnotations(e, setOf(key))
        assertEquals("repeat: 0 highlights applied", 0, second.highlights.applied)
        assertEquals("repeat: 2 highlights skipped", 2, second.highlights.skipped)
        assertEquals("repeat: 0 notes applied", 0, second.notes.applied)
        assertEquals("repeat: 1 note skipped", 1, second.notes.skipped)
        assertEquals("repeat: 0 bookmarks applied", 0, second.bookmarks.applied)
        assertEquals("repeat: 1 bookmark skipped", 1, second.bookmarks.skipped)

        // No duplicates materialized.
        assertEquals(2, repo.allHighlights().size)
        assertEquals(1, repo.allNotes().size)
        assertEquals(1, repo.allBookmarks().size)
    }

    @Test fun restore_rowForNonAllowedBook_skipped_notApplied() = runBlocking {
        val report = repo.restoreAnnotations(
            env(highlights = listOf(highlight("h-x"))), allowedBookKeys = emptySet(),
        )
        assertEquals(0, report.highlights.applied)
        assertEquals("out-of-scope book → skipped", 1, report.highlights.skipped)
        assertEquals(0, report.highlights.failed)
        assertNull(repo.findHighlight("h-x"))
    }

    @Test fun restore_locatorForAnotherBook_countedFailed_notApplied() = runBlocking {
        // locatorJSON parses to a Locator whose fingerprintKey != bookFingerprintKey.
        val mismatched = highlight("h-bad").copy(
            locatorJSON = BackupJson.encode(
                Locator(contentSHA256 = "b".repeat(64), fileByteCount = 4096L, format = "epub", href = "c", cfi = "/4:1"),
            ),
        )
        val report = repo.restoreAnnotations(env(highlights = listOf(mismatched)), setOf(key))
        assertEquals(0, report.highlights.applied)
        assertEquals(1, report.highlights.failed)
        assertEquals(0, report.highlights.skipped)
        assertNull(repo.findHighlight("h-bad"))
    }

    @Test fun restore_corruptLocatorJson_countedFailed() = runBlocking {
        val corrupt = note("n-bad").copy(locatorJSON = "{not-valid-json")
        val report = repo.restoreAnnotations(env(notes = listOf(corrupt)), setOf(key))
        assertEquals(0, report.notes.applied)
        assertEquals(1, report.notes.failed)
    }

    @Test fun restore_emptyEnvelope_allZero() = runBlocking {
        val report = repo.restoreAnnotations(env(), setOf(key))
        assertEquals(KindCounts(0, 0, 0), report.highlights)
        assertEquals(KindCounts(0, 0, 0), report.notes)
        assertEquals(KindCounts(0, 0, 0), report.bookmarks)
    }

    @Test fun restore_perKindCounts_areExact_mixedOutcomes() = runBlocking {
        val key2 = "epub:${"b".repeat(64)}:4096"
        db.bookDao().upsert(BookEntity(key2, "Walden", "epub", "b".repeat(64), 4096L, null, null, 2L, null))
        val notAllowed = highlight("h-notallowed").copy(bookFingerprintKey = key2)
        val bad = highlight("h-bad2").copy(locatorJSON = "{bad")
        val good = highlight("h-good")
        // only `key` is allowed → notAllowed is skipped, bad is failed, good is applied.
        val report = repo.restoreAnnotations(env(highlights = listOf(good, notAllowed, bad)), setOf(key))
        assertEquals(1, report.highlights.applied)
        assertEquals(1, report.highlights.skipped)
        assertEquals(1, report.highlights.failed)
    }

    @Test fun restore_sameAnchorDifferentUuid_dedupesViaProfileKeyIndex() = runBlocking {
        // First restore lands under one UUID.
        repo.restoreAnnotations(env(highlights = listOf(highlight("uuid-A", cfi = "/4:1"))), setOf(key))
        // A DIFFERENT UUID at the SAME (profileKey, anchorKey) — the unique index guards it.
        val report = repo.restoreAnnotations(env(highlights = listOf(highlight("uuid-B", cfi = "/4:1"))), setOf(key))
        assertEquals("same-anchor different-UUID does not duplicate", 0, report.highlights.applied)
        assertEquals(1, report.highlights.skipped)
        assertEquals(1, repo.allHighlights().size)
    }
}
