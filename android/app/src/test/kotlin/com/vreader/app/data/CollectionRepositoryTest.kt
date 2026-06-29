package com.vreader.app.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #127 WI-2 — [CollectionRepository] over an in-memory v5 Room DB. Covers the transactional
 * create/rename dedup (case-insensitive via `nameKey`, locale-invariant), trim/empty/truncate-100
 * (iOS parity), membership, cascade, and the LEFT-JOIN count (empty collection = 0).
 */
@RunWith(RobolectricTestRunner::class)
class CollectionRepositoryTest {
    private lateinit var db: VReaderDatabase
    private lateinit var repo: CollectionRepository
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val bookKey = "epub:${"a".repeat(64)}:2048"
    private var seq = 0

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).allowMainThreadQueries().build()
        // deterministic ids + clock so assertions are stable.
        repo = CollectionRepository(db.collectionDao(), now = { 100L }, newId = { "id-${seq++}" })
        runBlocking { db.bookDao().upsert(BookEntity(bookKey, "T", "epub", "a".repeat(64), 2048L, null, null, 1L, null)) }
    }

    @After fun tearDown() = db.close()

    private fun err(r: Result<*>) = (r.exceptionOrNull() as CollectionException).error

    @Test fun create_succeeds_andCountsZero() = runBlocking {
        val c = repo.createCollection("Fiction").getOrThrow()
        assertEquals("Fiction", c.name)
        assertEquals(0, c.bookCount)
        assertEquals(listOf("Fiction"), repo.observeCollections().first().map { it.name })
    }

    @Test fun create_rejectsEmptyAndWhitespace() = runBlocking {
        assertEquals(CollectionError.EmptyName, err(repo.createCollection("")))
        assertEquals(CollectionError.EmptyName, err(repo.createCollection("   ")))
    }

    @Test fun create_dedupesCaseInsensitively_acrossWhitespaceAndCase() = runBlocking {
        repo.createCollection("Fiction").getOrThrow()
        assertEquals(CollectionError.DuplicateName, err(repo.createCollection("  fiction  ")))
        assertEquals(CollectionError.DuplicateName, err(repo.createCollection("FICTION")))
        assertEquals("only one row exists", 1, repo.observeCollections().first().size)
    }

    @Test fun create_caseInsensitive_isLocaleInvariant() = runBlocking {
        // "INDEX".lowercase(Locale.ROOT) == "index" (NOT the Turkish dotless-ı) → these collide.
        repo.createCollection("INDEX").getOrThrow()
        assertEquals(CollectionError.DuplicateName, err(repo.createCollection("index")))
    }

    @Test fun create_dedupesCJK_afterTrim() = runBlocking {
        repo.createCollection("小说").getOrThrow()
        assertEquals(CollectionError.DuplicateName, err(repo.createCollection("  小说 ")))
    }

    @Test fun create_truncatesTo100Chars_notAnError() = runBlocking {
        val c = repo.createCollection("x".repeat(150)).getOrThrow()
        assertEquals(100, c.name.length)
    }

    @Test fun create_truncatesByGrapheme_notUtf16CodeUnits() = runBlocking {
        // "😀" = 1 grapheme / 1 code point / 2 UTF-16 units. iOS prefix(100) keeps 100 emoji; a naive
        // UTF-16 substring(0,100) would keep only 50. Assert we kept 100 code points (Gate-4 WI-2 fix).
        val c = repo.createCollection("😀".repeat(150)).getOrThrow()
        assertEquals(100, c.name.codePointCount(0, c.name.length))
    }

    @Test fun rename_succeeds_rejectsDuplicate_andNotFound() = runBlocking {
        val a = repo.createCollection("Alpha").getOrThrow()
        repo.createCollection("Beta").getOrThrow()
        assertTrue(repo.rename(a.id, "Apex").isSuccess)                       // free name
        assertEquals(CollectionError.DuplicateName, err(repo.rename(a.id, "beta"))) // taken by another
        assertTrue("renaming to its own (case-folded) name is allowed", repo.rename(a.id, "APEX").isSuccess)
        assertEquals(CollectionError.NotFound, err(repo.rename("ghost", "Zeta")))
        // a GONE id reports NotFound even when the target name EXISTS elsewhere (Gate-4 WI-2 fix — the
        // id-existence check runs BEFORE the duplicate check).
        assertEquals(CollectionError.NotFound, err(repo.rename("ghost", "Beta")))
    }

    @Test fun membership_assign_unassign_and_countReflectsIt() = runBlocking {
        val fic = repo.createCollection("Fiction").getOrThrow()
        repo.createCollection("Empty").getOrThrow()
        repo.assign(bookKey, fic.id)
        repo.assign(bookKey, fic.id) // idempotent
        val counts = repo.observeCollections().first().associate { it.name to it.bookCount }
        assertEquals(1, counts["Fiction"])
        assertEquals("empty collection counts 0 via the LEFT JOIN", 0, counts["Empty"])
        repo.unassign(bookKey, fic.id)
        assertEquals(0, repo.observeCollections().first().first { it.name == "Fiction" }.bookCount)
    }

    @Test fun deletingBook_cascadesMembership_keepsCollection() = runBlocking {
        val fic = repo.createCollection("Fiction").getOrThrow()
        repo.assign(bookKey, fic.id)
        db.bookDao().delete(bookKey)
        assertTrue(repo.observeBookKeysInCollection(fic.id).first().isEmpty())
        assertEquals("the collection survives", 1, repo.observeCollections().first().size)
    }

    @Test fun delete_isIdempotent() = runBlocking {
        val c = repo.createCollection("Temp").getOrThrow()
        repo.delete(c.id)
        repo.delete(c.id) // no throw on a gone collection
        assertFalse(repo.observeCollections().first().any { it.id == c.id })
    }
}
