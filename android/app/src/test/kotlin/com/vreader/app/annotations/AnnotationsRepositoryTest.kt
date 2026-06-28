package com.vreader.app.annotations

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.BookEntity
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.Locator

/** Feature #123 WI-2 — [AnnotationsRepository] over a real in-memory Room db. */
@RunWith(RobolectricTestRunner::class)
class AnnotationsRepositoryTest {
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
            db.bookDao().upsert(BookEntity(key, "Pride and Prejudice", "epub", "a".repeat(64), 2048L, null, null, 1L, null))
        }
    }

    @After fun tearDown() = db.close()

    private fun loc(cfi: String) = Locator(contentSHA256 = "a".repeat(64), fileByteCount = 2048L, format = "epub", href = "c.xhtml", cfi = cfi)
    private fun anchor(cfi: String) = AnnotationAnchor.Epub(href = "c.xhtml", cfi = cfi)

    @Test fun addHighlight_persists_andObserves() = runBlocking {
        val rec = repo.addHighlight(key, AnnotationColor.yellow, "Call me Ishmael", loc("/4:1"), anchor("/4:1"))
        assertNotNull(rec.id)
        val observed = repo.highlights(key).first()
        assertEquals(1, observed.size)
        assertEquals("Call me Ishmael", observed.single().selectedText)
        assertEquals(AnnotationColor.yellow, observed.single().color)
        assertEquals(anchor("/4:1"), observed.single().anchor)
    }

    @Test fun addHighlight_sameRange_dedupes_updatesInPlace() = runBlocking {
        repo.addHighlight(key, AnnotationColor.yellow, "x", loc("/4:1"), anchor("/4:1"))
        repo.addHighlight(key, AnnotationColor.pink, "x", loc("/4:1"), anchor("/4:1"))
        val all = repo.highlightsForBook(key)
        assertEquals("same (profileKey, anchorKey) → one row", 1, all.size)
        assertEquals("color updated in place", AnnotationColor.pink, all.single().color)
    }

    @Test fun addHighlight_onDedupe_returnsPersistedExistingId_notDeadNewId() = runBlocking {
        val first = repo.addHighlight(key, AnnotationColor.yellow, "x", loc("/4:1"), anchor("/4:1"))
        val second = repo.addHighlight(key, AnnotationColor.pink, "x", loc("/4:1"), anchor("/4:1"))
        // the dedupe kept the existing row, so the returned id must be the PERSISTED one (findable),
        // not the discarded freshly-generated id.
        assertEquals("returns the existing persisted id", first.id, second.id)
        assertNotNull("returned id is a live row", repo.findHighlight(second.id))
        assertEquals("the persisted record reflects the update", AnnotationColor.pink, repo.findHighlight(second.id)!!.color)
    }

    @Test(expected = IllegalArgumentException::class)
    fun addHighlight_locatorForAnotherBook_rejected() = runBlocking {
        val otherLoc = Locator(contentSHA256 = "b".repeat(64), fileByteCount = 4096L, format = "epub", href = "c", cfi = "/4:1")
        repo.addHighlight(key, AnnotationColor.yellow, "x", otherLoc, anchor("/4:1"))
        Unit
    }

    @Test fun addHighlight_differentRange_keepsBoth() = runBlocking {
        repo.addHighlight(key, AnnotationColor.yellow, "a", loc("/4:1"), anchor("/4:1"))
        repo.addHighlight(key, AnnotationColor.blue, "b", loc("/6:1"), anchor("/6:1"))
        assertEquals(2, repo.highlightsForBook(key).size)
    }

    @Test fun updateHighlight_changesColorAndNote() = runBlocking {
        val rec = repo.addHighlight(key, AnnotationColor.yellow, "x", loc("/4:1"), anchor("/4:1"))
        repo.updateHighlight(rec.id, AnnotationColor.green, "a thought")
        val h = repo.findHighlight(rec.id)!!
        assertEquals(AnnotationColor.green, h.color)
        assertEquals("a thought", h.note)
    }

    @Test fun removeHighlight_deletes() = runBlocking {
        val rec = repo.addHighlight(key, AnnotationColor.yellow, "x", loc("/4:1"), anchor("/4:1"))
        repo.removeHighlight(rec.id)
        assertNull(repo.findHighlight(rec.id))
        assertEquals(0, repo.highlightCount(key))
    }

    @Test fun notes_addAndRemove() = runBlocking {
        val n = repo.addNote(key, "standalone thought", loc("/8:1"))
        assertEquals(1, repo.notes(key).first().size)
        repo.removeNote(n.id)
        assertTrue(repo.notes(key).first().isEmpty())
    }

    @Test fun bookmarks_addAndRemove() = runBlocking {
        val b = repo.addBookmark(key, "Chapter 1", loc("/2:0"))
        assertEquals(1, repo.bookmarks(key).first().size)
        repo.removeBookmark(b.id)
        assertTrue(repo.bookmarks(key).first().isEmpty())
    }

    @Test fun highlight_locatorRoundTrips_throughStorage() = runBlocking {
        val rec = repo.addHighlight(key, AnnotationColor.yellow, "x", loc("/4:7"), anchor("/4:7"))
        val read = repo.findHighlight(rec.id)!!
        assertEquals("locator survives the JSON round-trip", "/4:7", read.locator.cfi)
        assertEquals("epub", read.locator.format)
    }

    @Test fun allHighlights_spansBooks() = runBlocking {
        val key2 = "epub:${"b".repeat(64)}:4096"
        db.bookDao().upsert(BookEntity(key2, "Walden", "epub", "b".repeat(64), 4096L, null, null, 2L, null))
        repo.addHighlight(key, AnnotationColor.yellow, "a", loc("/4:1"), anchor("/4:1"))
        repo.addHighlight(key2, AnnotationColor.blue, "b", Locator("b".repeat(64), 4096L, "epub", href = "c", cfi = "/4:1"), anchor("/4:1"))
        assertEquals(2, repo.allHighlights().size)
    }
}
