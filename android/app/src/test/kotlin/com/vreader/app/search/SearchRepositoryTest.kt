package com.vreader.app.search

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.data.BookEntity
import com.vreader.app.data.SearchDao
import com.vreader.app.data.SearchIndexStateEntity
import com.vreader.app.data.SearchStagingEntity
import com.vreader.app.data.VReaderDatabase
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #128 WI-6 — [SearchRepository] against an in-memory v7 Room DB (real FTS4/unicode61 under
 * Robolectric). Covers: observable Flow that GROWS as sections publish (fix #1), null/blank-query
 * short-circuit with NO SQL error (fix #2), first-hit-per-book, CJK in-text, and ß↔ss case-fold query
 * matching an `ss`-text book.
 */
@RunWith(RobolectricTestRunner::class)
class SearchRepositoryTest {
    private lateinit var db: VReaderDatabase
    private lateinit var dao: SearchDao
    private lateinit var repo: SearchRepository
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun keyFor(sha: Char) = "epub:${sha.toString().repeat(64)}:2048"
    private val bookA = keyFor('a')
    private val bookB = keyFor('b')

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java)
            .allowMainThreadQueries().build()
        dao = db.searchDao()
        repo = SearchRepository(dao)
    }

    @After fun tearDown() = db.close()

    private fun seedBook(key: String, format: String = "epub") = runBlocking {
        db.bookDao().upsert(
            BookEntity(
                fingerprintKey = key, title = "T", originalFormat = format,
                contentSHA256 = key.substringAfter(':').substringBefore(':'),
                fileByteCount = 2048L, localFilePath = null, sourceUri = null,
                addedAt = 1L, lastOpenedAt = null, author = null,
            ),
        )
    }

    /** Publish one section straight into the content table (the effect of the coordinator's publish). */
    private fun publishSection(key: String, sectionIndex: Int, chunkOrdinal: Int, text: String, title: String? = null) = runBlocking {
        dao.insertStagingBatch(
            listOf(
                SearchStagingEntity(
                    bookKey = key, sectionIndex = sectionIndex, chunkOrdinal = chunkOrdinal, sectionTitle = title,
                    text = text, indexedText = SearchTextNormalizer.segmentCJK(SearchTextNormalizer.normalize(text)),
                ),
            ),
        )
        dao.copyStagingToSections(key)
        dao.clearStaging(key)
        dao.markIndexed(SearchIndexStateEntity(key, 1, 1L, "indexed"))
    }

    // ---- fix #2: null/blank query short-circuits (no FTS MATCH, no crash) ----

    @Test fun blankQuery_yieldsEmpty_noSqlError() = runBlocking {
        seedBook(bookA)
        publishSection(bookA, 0, 0, "some searchable text")
        assertTrue("blank query → empty", repo.textHits("").first().isEmpty())
        assertTrue("whitespace query → empty", repo.textHits("   ").first().isEmpty())
        // An operator-only query also builds to null → empty, never a MATCH error.
        assertTrue("operator-only query → empty", repo.textHits("\"*()").first().isEmpty())
    }

    // ---- fix #1: observable Flow grows as indexing publishes more sections ----

    @Test fun textHits_growAsSectionsPublish_forAHeldQuery() = runBlocking {
        seedBook(bookA)
        seedBook(bookB)
        // ONE held collector across the whole indexing pass — proving the SAME Flow re-emits enlarged
        // results as sections publish (fix #1). A one-shot implementation would NOT re-emit here.
        val emissions = java.util.concurrent.CopyOnWriteArrayList<Int>()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        try {
            scope.launch { repo.textHits("widget").collect { emissions.add(it.size) } }

            // Wait for the initial (empty) emission.
            awaitCount(emissions) { it.isNotEmpty() }
            assertEquals("initial emission is empty", 0, emissions.last())

            publishSection(bookA, 0, 0, "a widget appears here")
            awaitCount(emissions) { it.lastOrNull() == 1 }
            assertEquals("held Flow re-emits 1 after book A publishes", 1, emissions.last())

            publishSection(bookB, 0, 1, "another widget over there")
            awaitCount(emissions) { it.lastOrNull() == 2 }
            assertEquals("held Flow GROWS to 2 after book B publishes (observable, not one-shot)", 2, emissions.last())
        } finally {
            scope.cancel()
        }
    }

    /** Poll [list] until [predicate] holds (Room-Flow re-emission is async) — bounded so a stuck Flow
     *  fails the test rather than hangs. */
    private suspend fun awaitCount(list: List<Int>, predicate: (List<Int>) -> Boolean) {
        withTimeout(5_000) {
            while (!predicate(list)) kotlinx.coroutines.delay(20)
        }
    }

    // ---- first-hit-per-book ----

    @Test fun textHits_oneHitPerBook_evenWhenHeavilyMatching() = runBlocking {
        seedBook(bookA)
        (0 until 50).forEach { publishSection(bookA, it, it, "gadget number $it") }
        val hits = repo.textHits("gadget").first()
        assertEquals("exactly one hit for the heavily-matching book", 1, hits.size)
        assertEquals(bookA, hits.single().bookKey)
    }

    // ---- CJK in-text ----

    @Test fun textHits_cjkInText_matches() = runBlocking {
        seedBook(bookA)
        publishSection(bookA, 0, 0, "关于编程的书籍很有趣")
        val hits = repo.textHits("编程").first()
        assertEquals("CJK in-text match", 1, hits.size)
        assertNotNull(hits.single().snippet)
    }

    // ---- ß↔ss case-fold query matches an `ss`-text book ----

    @Test fun textHits_eszettQuery_matchesSsText() = runBlocking {
        seedBook(bookA)
        publishSection(bookA, 0, 0, "the strasse was empty at dawn")
        // "Straße" normalizes to "strasse" → matches the `ss`-text section.
        val hits = repo.textHits("Straße").first()
        assertEquals("ß-query folds to ss and matches", 1, hits.size)
    }

    // ---- snippet + attribution ----

    @Test fun textHits_carrySectionTitleAndSnippet() = runBlocking {
        seedBook(bookA)
        publishSection(bookA, 0, 0, "the pragmatic programmer adapts quickly", title = "Ch. 1")
        val hit = repo.textHits("pragmatic").first().single()
        assertEquals("Ch. 1", hit.sectionTitle)
        assertTrue("snippet contains the matched text", hit.snippet.contains("pragmatic"))
        assertTrue("has a highlight range", hit.matchRanges.isNotEmpty())
    }
}
