package com.vreader.app.annotations

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.AnnotationNoteEntity
import com.vreader.app.data.BookEntity
import com.vreader.app.data.HighlightEntity
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.Locator

/**
 * Feature #132 WI-6b — [AnnotationsRepository.annotationsForBook] deterministic snapshot
 * (highlights + notes one-shot for the review sheet's non-Flow open), over in-memory Room.
 */
@RunWith(RobolectricTestRunner::class)
class AnnotationSnapshotTest {
    private lateinit var db: VReaderDatabase
    private lateinit var repo: AnnotationsRepository
    private val key = "epub:${"a".repeat(64)}:2048"
    private var clock = 100L

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java,
        ).build()
        repo = AnnotationsRepository(db.annotationDao(), now = { clock })
        runBlocking {
            db.bookDao().upsert(BookEntity(key, "Moby Dick", "epub", "a".repeat(64), 2048L, null, null, 1L, null))
        }
    }

    @After fun tearDown() = db.close()

    private fun loc(cfi: String) =
        Locator(contentSHA256 = "a".repeat(64), fileByteCount = 2048L, format = "epub", href = "c.xhtml", cfi = cfi)
    private fun anchor(cfi: String) = AnnotationAnchor.Epub(href = "c.xhtml", cfi = cfi)

    @Test fun annotationsForBook_emptyBook_emptySnapshot() = runBlocking {
        val snap = repo.annotationsForBook(key)
        assertTrue(snap.highlights.isEmpty())
        assertTrue(snap.notes.isEmpty())
    }

    @Test fun annotationsForBook_returnsHighlightsAndNotes() = runBlocking {
        repo.addHighlight(key, AnnotationColor.yellow, "Call me Ishmael", loc("/4:1"), anchor("/4:1"))
        repo.addNote(key, "a thought", loc("/8:1"), anchor("/8:1"))
        val snap = repo.annotationsForBook(key)
        assertEquals(1, snap.highlights.size)
        assertEquals(1, snap.notes.size)
        assertEquals("Call me Ishmael", snap.highlights.single().selectedText)
        assertEquals("a thought", snap.notes.single().content)
    }

    @Test fun annotationsForBook_isDeterministicallySorted_byCreatedAtThenId() = runBlocking {
        clock = 300L
        repo.addHighlight(key, AnnotationColor.yellow, "third", loc("/6:1"), anchor("/6:1"))
        clock = 100L
        repo.addHighlight(key, AnnotationColor.blue, "first", loc("/2:1"), anchor("/2:1"))
        clock = 200L
        repo.addHighlight(key, AnnotationColor.green, "second", loc("/4:1"), anchor("/4:1"))
        val snap = repo.annotationsForBook(key)
        assertEquals(listOf("first", "second", "third"), snap.highlights.map { it.selectedText })
        // Two repeated reads yield the same order.
        assertEquals(snap.highlights.map { it.id }, repo.annotationsForBook(key).highlights.map { it.id })
    }

    @Test fun annotationsForBook_scopesToBook_excludesOtherBooks() = runBlocking {
        val key2 = "epub:${"b".repeat(64)}:4096"
        db.bookDao().upsert(BookEntity(key2, "Walden", "epub", "b".repeat(64), 4096L, null, null, 2L, null))
        repo.addHighlight(key, AnnotationColor.yellow, "mine", loc("/4:1"), anchor("/4:1"))
        repo.addHighlight(
            key2, AnnotationColor.blue, "theirs",
            Locator("b".repeat(64), 4096L, "epub", href = "c", cfi = "/4:1"), AnnotationAnchor.Epub("c", "/4:1"),
        )
        assertEquals(1, repo.annotationsForBook(key).highlights.size)
        assertEquals("mine", repo.annotationsForBook(key).highlights.single().selectedText)
    }

    @Test fun annotationsForBook_corruptRow_skipped_notCrashed() = runBlocking {
        // A directly-inserted entity with corrupt locatorJSON must be dropped by toRecordOrNull.
        val dao = db.annotationDao()
        dao.upsertHighlight(
            HighlightEntity(
                highlightId = "corrupt-h", bookKey = key, profileKey = "$key:zzz", anchorKey = NIL_ANCHOR,
                color = "yellow", selectedText = "x", note = null,
                locatorJSON = "{not-json", anchorJSON = null, createdAt = 1L, updatedAt = 1L,
            ),
        )
        dao.upsertNote(
            AnnotationNoteEntity(
                noteId = "corrupt-n", bookKey = key, profileKey = "$key:yyy",
                content = "y", locatorJSON = "{also-bad", anchorJSON = null, createdAt = 1L, updatedAt = 1L,
            ),
        )
        // A valid one alongside.
        repo.addHighlight(key, AnnotationColor.yellow, "good", loc("/4:1"), anchor("/4:1"))
        val snap = repo.annotationsForBook(key)
        assertEquals("corrupt highlight dropped, good one kept", 1, snap.highlights.size)
        assertEquals("good", snap.highlights.single().selectedText)
        assertTrue("corrupt note dropped", snap.notes.isEmpty())
    }
}
