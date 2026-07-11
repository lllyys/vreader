package com.vreader.app.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.annotations.AnnotationsRepository
import com.vreader.app.annotations.BookmarkRecord
import com.vreader.app.annotations.BookmarkToggleResult
import com.vreader.app.annotations.newAnnotationId
import com.vreader.app.annotations.profileKeyFor
import com.vreader.app.annotations.toEntity
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.Locator

/**
 * Feature #135 WI-3 — atomic bookmark toggle + presence over a real in-memory Room db (the unique
 * `(bookKey, profileKey)` index makes re-bookmarking the same position idempotent). Exercises the
 * DAO `toggleBookmark` / `isBookmarked` and the repository wrappers.
 */
@RunWith(RobolectricTestRunner::class)
class BookmarkToggleTest {
    private lateinit var db: VReaderDatabase
    private lateinit var dao: AnnotationDao
    private lateinit var repo: AnnotationsRepository
    private val key = "epub:${"a".repeat(64)}:2048"
    private var clock = 100L

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(), VReaderDatabase::class.java,
        ).build()
        dao = db.annotationDao()
        repo = AnnotationsRepository(dao, now = { clock })
        runBlocking {
            db.bookDao().upsert(BookEntity(key, "Pride and Prejudice", "epub", "a".repeat(64), 2048L, null, null, 1L, null))
        }
    }

    @After fun tearDown() = db.close()

    private fun loc(cfi: String) = Locator(contentSHA256 = "a".repeat(64), fileByteCount = 2048L, format = "epub", href = "c.xhtml", cfi = cfi)

    private fun entity(id: String, cfi: String) = BookmarkRecord(
        id = id, bookKey = key, title = "Chapter 1", locator = loc(cfi), createdAt = clock, updatedAt = clock,
    ).toEntity()

    // ---- repository toggle ----

    @Test fun toggle_add_thenAgain_removes() = runBlocking {
        val added = repo.toggleBookmark(key, "Chapter 1", loc("/2:0"))
        assertEquals(BookmarkToggleResult.Added, added)
        assertEquals("exactly one bookmark after add", 1, repo.allBookmarks().size)

        val removed = repo.toggleBookmark(key, "Chapter 1", loc("/2:0"))
        assertEquals(BookmarkToggleResult.Removed, removed)
        assertEquals("zero bookmarks after toggle-off", 0, repo.allBookmarks().size)
    }

    @Test fun isBookmarked_reflectsPresence() = runBlocking {
        assertFalse("not bookmarked initially", repo.isBookmarked(key, loc("/2:0")))
        repo.toggleBookmark(key, null, loc("/2:0"))
        assertTrue("bookmarked after toggle-on", repo.isBookmarked(key, loc("/2:0")))
        repo.toggleBookmark(key, null, loc("/2:0"))
        assertFalse("not bookmarked after toggle-off", repo.isBookmarked(key, loc("/2:0")))
    }

    @Test fun toggle_differentPositions_areIndependent() = runBlocking {
        repo.toggleBookmark(key, null, loc("/2:0"))
        repo.toggleBookmark(key, null, loc("/6:1"))
        assertEquals("two distinct positions → two bookmarks", 2, repo.allBookmarks().size)
        assertTrue(repo.isBookmarked(key, loc("/2:0")))
        assertTrue(repo.isBookmarked(key, loc("/6:1")))
    }

    @Test(expected = IllegalArgumentException::class)
    fun toggle_locatorForAnotherBook_rejected() = runBlocking {
        val otherLoc = Locator(contentSHA256 = "b".repeat(64), fileByteCount = 4096L, format = "epub", href = "c", cfi = "/4:1")
        repo.toggleBookmark(key, null, otherLoc)
        Unit
    }

    // ---- DAO-level idempotency (the unique index is the enforcer) ----

    @Test fun repeatAdd_viaInsertIfAbsent_isIdempotent_exactlyOneRow() = runBlocking {
        // Two adds at the same (bookKey, profileKey) with different ids → the unique index keeps ONE.
        val pk = profileKeyFor(key, loc("/2:0"))
        assertTrue(dao.insertBookmarkIfAbsent(entity("id-a", "/2:0")) != -1L)
        assertEquals("second add at same position rejected", -1L, dao.insertBookmarkIfAbsent(entity("id-b", "/2:0")))
        assertEquals("exactly one row for this position", 1, dao.bookmarksForBook(key).size)
        assertEquals("presence is 1", 1, dao.isBookmarked(key, pk))
    }

    @Test fun toggle_dao_addToggle_isRepeatable() = runBlocking {
        val e = entity("id-a", "/2:0")
        assertEquals(BookmarkToggleResult.Added, dao.toggleBookmark(e))
        assertEquals(1, dao.bookmarksForBook(key).size)
        // A new entity (fresh id) at the same position toggles OFF the existing one.
        assertEquals(BookmarkToggleResult.Removed, dao.toggleBookmark(entity("id-b", "/2:0")))
        assertEquals(0, dao.bookmarksForBook(key).size)
        // Toggling again re-adds.
        assertEquals(BookmarkToggleResult.Added, dao.toggleBookmark(entity("id-c", "/2:0")))
        assertEquals(1, dao.bookmarksForBook(key).size)
    }

    @Test fun concurrentAdd_viaInsertIfAbsent_yieldsExactlyOneRow() = runBlocking {
        // Fire many insert-if-absent for the SAME position concurrently; the unique index guarantees
        // exactly one row survives regardless of interleaving.
        val jobs = (0 until 12).map { i ->
            async { dao.insertBookmarkIfAbsent(entity("id-$i", "/2:0")) }
        }
        jobs.awaitAll()
        assertEquals("concurrent repeat-add collapses to exactly one row", 1, dao.bookmarksForBook(key).size)
    }

    @Test fun findAndDeleteByProfile_roundTrip() = runBlocking {
        val pk = profileKeyFor(key, loc("/2:0"))
        assertEquals("nothing found before add", 0, dao.isBookmarked(key, pk))
        dao.insertBookmarkIfAbsent(entity("id-a", "/2:0"))
        val found = dao.findBookmarkByProfile(key, pk)
        assertEquals("id-a", found?.bookmarkId)
        val deleted = dao.deleteBookmarkByProfile(key, pk)
        assertEquals("one row deleted", 1, deleted)
        assertEquals("presence is 0 after delete", 0, dao.isBookmarked(key, pk))
    }
}
