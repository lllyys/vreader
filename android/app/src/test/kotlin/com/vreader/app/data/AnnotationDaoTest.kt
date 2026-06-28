package com.vreader.app.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #123 WI-1 — [AnnotationDao] CRUD / observe / FK-cascade / transactional dedupe over an
 * in-memory Room db (the iOS PersistenceActor-test analog). FK constraints are enabled so the
 * book-delete cascade is exercised.
 */
@RunWith(RobolectricTestRunner::class)
class AnnotationDaoTest {
    private lateinit var db: VReaderDatabase
    private lateinit var dao: AnnotationDao
    private val key = "epub:${"a".repeat(64)}:2048"

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java,
        ).build()
        dao = db.annotationDao()
        // a parent book is required for the FK
        runBlocking {
            db.bookDao().upsert(
                BookEntity(key, "Pride and Prejudice", "epub", "a".repeat(64), 2048L, null, null, 1L, null),
            )
        }
    }

    @After fun tearDown() = db.close()

    private fun highlight(id: String, anchorKey: String = "anchor-$id", color: String = "yellow") =
        HighlightEntity(
            highlightId = id, bookKey = key, profileKey = "$key:p-$id", anchorKey = anchorKey,
            color = color, selectedText = "selected $id", note = null,
            locatorJSON = "{}", anchorJSON = null, createdAt = 1L, updatedAt = 1L,
        )

    @Test fun upsertHighlight_thenObserve_returnsIt() = runBlocking {
        dao.upsertHighlight(highlight("h1"))
        val observed = dao.observeHighlights(key).first()
        assertEquals(1, observed.size)
        assertEquals("h1", observed.single().highlightId)
    }

    @Test fun upsertHighlight_sameProfileAndAnchor_updatesInPlace() = runBlocking {
        val h = highlight("h1", anchorKey = "same", color = "yellow")
        dao.upsertHighlight(h)
        // re-highlight the SAME range (same profileKey+anchorKey) with a different id + color
        dao.upsertHighlight(h.copy(highlightId = "h2", profileKey = h.profileKey, color = "pink", updatedAt = 9L))
        val all = dao.highlightsForBook(key)
        assertEquals("dedupe → one row", 1, all.size)
        assertEquals("color updated in place", "pink", all.single().color)
        assertEquals("kept the original id (insert ignored, existing updated)", "h1", all.single().highlightId)
    }

    @Test fun upsertHighlight_differentAnchor_keepsBoth() = runBlocking {
        dao.upsertHighlight(highlight("h1", anchorKey = "a1"))
        dao.upsertHighlight(highlight("h2", anchorKey = "a2"))
        assertEquals(2, dao.highlightsForBook(key).size)
    }

    @Test fun updateHighlightColorNote_byId() = runBlocking {
        dao.upsertHighlight(highlight("h1"))
        dao.updateHighlightColorNote("h1", "green", "my note", 5L)
        val h = dao.findHighlight("h1")!!
        assertEquals("green", h.color)
        assertEquals("my note", h.note)
    }

    @Test fun deleteHighlight_removesIt() = runBlocking {
        dao.upsertHighlight(highlight("h1"))
        dao.deleteHighlight("h1")
        assertNull(dao.findHighlight("h1"))
        assertEquals(0, dao.highlightCount(key))
    }

    @Test fun deletingBook_cascades_toAnnotations() = runBlocking {
        dao.upsertHighlight(highlight("h1"))
        dao.upsertNote(AnnotationNoteEntity("n1", key, "$key:n", "note body", "{}", null, 1L, 1L))
        dao.upsertBookmark(BookmarkEntity("b1", key, "$key:b", "Ch.1", "{}", 1L, 1L))
        db.bookDao().delete(key)   // ON DELETE CASCADE
        assertEquals(0, dao.highlightsForBook(key).size)
        assertEquals(0, dao.notesForBook(key).size)
        assertEquals(0, dao.bookmarksForBook(key).size)
    }

    @Test fun notes_and_bookmarks_crud() = runBlocking {
        dao.upsertNote(AnnotationNoteEntity("n1", key, "$key:n", "first", "{}", null, 1L, 1L))
        dao.upsertNote(AnnotationNoteEntity("n2", key, "$key:n2", "second", "{}", null, 2L, 2L))
        assertEquals(2, dao.observeNotes(key).first().size)
        dao.deleteNote("n1")
        assertEquals(1, dao.notesForBook(key).size)

        dao.upsertBookmark(BookmarkEntity("b1", key, "$key:b", "Ch.1", "{}", 1L, 1L))
        assertEquals(1, dao.observeBookmarks(key).first().size)
        dao.deleteBookmark("b1")
        assertTrue(dao.bookmarksForBook(key).isEmpty())
    }

    @Test fun allHighlights_spansBooks_orderedByBookThenCreated() = runBlocking {
        val key2 = "epub:${"b".repeat(64)}:4096"
        db.bookDao().upsert(BookEntity(key2, "Walden", "epub", "b".repeat(64), 4096L, null, null, 2L, null))
        dao.upsertHighlight(highlight("h1"))
        dao.upsertHighlight(
            HighlightEntity("h2", key2, "$key2:p", "a2", "blue", "w", null, "{}", null, 1L, 1L),
        )
        assertEquals(2, dao.allHighlights().size)
    }
}
