package com.vreader.app.data

import android.content.Context
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import com.vreader.app.search.SearchTextNormalizer
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #128 WI-4 — [SearchDao] against an in-memory v7 Room DB (real SQLite FTS4/unicode61 under
 * Robolectric). Covers: unicode61 prefix + CJK per-char-phrase MATCH, content-table visibility, book
 * delete cascading ALL FOUR search tables (incl. staging), the atomic staging→sections `publishBook`
 * (swap + clear + state + author backfill), the `bookExists` no-op on a mid-index delete,
 * first-hit-per-book (one heavily-matching book does not hide another), deterministic first hit via
 * `chunkOrdinal`, staging invisibility before publish, and settled-completeness.
 */
@RunWith(RobolectricTestRunner::class)
class SearchDaoTest {
    private lateinit var db: VReaderDatabase
    private lateinit var dao: SearchDao
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private fun keyFor(sha: Char) = "epub:${sha.toString().repeat(64)}:2048"
    private val bookA = keyFor('a')
    private val bookB = keyFor('b')

    @Before fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java)
            .allowMainThreadQueries().build()
        dao = db.searchDao()
    }

    @After fun tearDown() = db.close()

    private fun seedBook(key: String, format: String = "epub", author: String? = null) = runBlocking {
        db.bookDao().upsert(
            BookEntity(
                fingerprintKey = key, title = "T", originalFormat = format,
                contentSHA256 = key.substringAfter(':').substringBefore(':'),
                fileByteCount = 2048L, localFilePath = null, sourceUri = null,
                addedAt = 1L, lastOpenedAt = null, author = author,
            ),
        )
    }

    /** Build a section entity whose FTS `indexedText` is normalized+CJK-segmented exactly as WI-5 will. */
    private fun section(key: String, sectionIndex: Int, chunkOrdinal: Int, text: String, title: String? = null) =
        SearchSectionEntity(
            bookKey = key, sectionIndex = sectionIndex, chunkOrdinal = chunkOrdinal, sectionTitle = title,
            text = text, indexedText = SearchTextNormalizer.segmentCJK(SearchTextNormalizer.normalize(text)),
        )

    private fun staging(key: String, sectionIndex: Int, chunkOrdinal: Int, text: String, title: String? = null) =
        SearchStagingEntity(
            bookKey = key, sectionIndex = sectionIndex, chunkOrdinal = chunkOrdinal, sectionTitle = title,
            text = text, indexedText = SearchTextNormalizer.segmentCJK(SearchTextNormalizer.normalize(text)),
        )

    private fun ftsFor(raw: String): String =
        SearchTextNormalizer.segmentCJK(SearchTextNormalizer.normalize(raw)).trim().split(Regex("\\s+"))
            .joinToString(" ") { it }

    // ---- FTS matching ----

    @Test fun unicode61_prefixMatch_findsSection() = runBlocking {
        seedBook(bookA)
        db.searchDaoInsertPublishedSection(section(bookA, 0, 0, "The pragmatic programmer adapts quickly"))
        val hit = dao.firstMatchingSection(bookA, "pragmat*")
        assertNotNull("prefix MATCH finds the section", hit)
        assertTrue(hit!!.text.contains("pragmatic"))
    }

    @Test fun cjk_perCharPhrase_matches() = runBlocking {
        seedBook(bookA)
        db.searchDaoInsertPublishedSection(section(bookA, 0, 0, "关于编程的书籍很有趣"))
        // A CJK query is normalized + per-char segmented, matched as a phrase of per-char tokens.
        val ftsPhrase = "\"" + ftsFor("编程") + "\""
        val hit = dao.firstMatchingSection(bookA, ftsPhrase)
        assertNotNull("CJK per-char phrase MATCH finds the section", hit)
    }

    @Test fun contentTableInsert_isVisibleThroughFts() = runBlocking {
        seedBook(bookA)
        // Insert straight into the content table (search_sections). Room's FTS triggers make it MATCHable.
        db.searchDaoInsertPublishedSection(section(bookA, 0, 0, "visible through the shadow table"))
        assertNotNull("a content-table row is MATCHable via the FTS shadow", dao.firstMatchingSection(bookA, "shadow"))
    }

    @Test fun stagingRows_areNotVisibleToMatch_beforePublish() = runBlocking {
        seedBook(bookA)
        dao.insertStagingBatch(listOf(staging(bookA, 0, 0, "invisible staged text")))
        assertNull("staging is NOT in the FTS content table", dao.firstMatchingSection(bookA, "invisible"))
    }

    // ---- delete cascade over all four tables ----

    @Test fun deleteBook_cascadesAllFourSearchTables() = runBlocking {
        seedBook(bookA)
        db.searchDaoInsertPublishedSection(section(bookA, 0, 0, "cascade target text"))
        dao.markIndexed(SearchIndexStateEntity(bookA, 1, 1L, "indexed"))
        dao.insertStagingBatch(listOf(staging(bookA, 1, 1, "still staged")))

        db.bookDao().delete(bookA)

        assertTrue("search_sections cascaded", dao.sectionsFor(bookA).isEmpty())
        assertNull("search_index_state cascaded", dao.indexState(bookA))
        assertTrue("search_sections_staging cascaded", dao.stagingFor(bookA).isEmpty())
        assertNull("FTS shadow no longer matches", dao.firstMatchingSection(bookA, "cascade"))
    }

    // ---- publishBook atomicity + guards ----

    @Test fun publishBook_swapsStagingToSections_clearsStaging_writesState_backfillsAuthor() = runBlocking {
        seedBook(bookA, author = null)
        dao.insertStagingBatch(
            listOf(
                staging(bookA, 0, 0, "chapter one text", title = "Ch. 1"),
                staging(bookA, 1, 1, "chapter two text", title = "Ch. 2"),
            ),
        )
        dao.publishBook(bookA, SearchIndexStateEntity(bookA, 1, 5L, "indexed"), author = "Jane Austen")

        val sections = dao.sectionsFor(bookA)
        assertEquals("both staged sections published", 2, sections.size)
        assertTrue("staging cleared after publish", dao.stagingFor(bookA).isEmpty())
        assertEquals("state row written", "indexed", dao.indexState(bookA)?.status)
        assertEquals("author backfilled", "Jane Austen", db.bookDao().find(bookA)?.author)
        assertNotNull("published section is MATCHable", dao.firstMatchingSection(bookA, "chapter"))
    }

    @Test fun publishBook_reindex_replacesPriorSections() = runBlocking {
        seedBook(bookA)
        dao.insertStagingBatch(listOf(staging(bookA, 0, 0, "original alpha content")))
        dao.publishBook(bookA, SearchIndexStateEntity(bookA, 1, 1L, "indexed"))
        assertNotNull(dao.firstMatchingSection(bookA, "alpha"))

        // A fresh extract (stale version) re-stages + republishes → the old section is gone.
        dao.insertStagingBatch(listOf(staging(bookA, 0, 0, "replacement beta content")))
        dao.publishBook(bookA, SearchIndexStateEntity(bookA, 2, 2L, "indexed"))
        assertNull("old section replaced on reindex", dao.firstMatchingSection(bookA, "alpha"))
        assertNotNull("new section present", dao.firstMatchingSection(bookA, "beta"))
        assertEquals("no leftover duplicates", 1, dao.sectionsFor(bookA).size)
    }

    @Test fun publishBook_doesNotBackfillAuthor_whenAlreadySet() = runBlocking {
        seedBook(bookA, author = "Existing Author")
        dao.insertStagingBatch(listOf(staging(bookA, 0, 0, "some text")))
        dao.publishBook(bookA, SearchIndexStateEntity(bookA, 1, 1L, "indexed"), author = "Different Author")
        assertEquals("backfill never overwrites a set author", "Existing Author", db.bookDao().find(bookA)?.author)
    }

    @Test fun publishBook_noOps_whenParentBookDeletedMidIndex() = runBlocking {
        seedBook(bookA)
        dao.insertStagingBatch(listOf(staging(bookA, 0, 0, "staged before delete")))
        // Simulate the delete-mid-index window: the book (and its cascaded staging) is gone.
        db.bookDao().delete(bookA)
        assertFalse("bookExists guard sees the deletion", dao.bookExists(bookA))

        // publishBook must NOT throw an FK failure and must NOT write an orphan state row.
        dao.publishBook(bookA, SearchIndexStateEntity(bookA, 1, 1L, "indexed"), author = "X")

        assertNull("no orphan state row after a mid-index delete", dao.indexState(bookA))
        assertTrue("no orphan sections after a mid-index delete", dao.sectionsFor(bookA).isEmpty())
    }

    // ---- first-hit-per-book (Gate-2 HIGH) ----

    @Test fun firstHitsPerBook_oneHeavyBookDoesNotHideAnother() = runBlocking {
        seedBook(bookA)
        seedBook(bookB)
        // bookA: 300 matching sections. bookB: exactly one match.
        val heavy = (0 until 300).map { section(bookA, it, it, "widget number $it appears here") }
        heavy.forEach { db.searchDaoInsertPublishedSection(it) }
        db.searchDaoInsertPublishedSection(section(bookB, 0, 300, "a single widget in book B"))

        val hits = dao.firstHitsPerBook("widget", limit = 200)
        val keys = hits.map { it.bookKey }.toSet()
        assertEquals("exactly one row per matching book", hits.size, keys.size)
        assertTrue("book A is present", keys.contains(bookA))
        assertTrue("book B is NOT hidden by book A's 300 matches", keys.contains(bookB))
    }

    @Test fun firstMatchingSection_isDeterministicByChunkOrdinal() = runBlocking {
        seedBook(bookA)
        // Insert out of chunkOrdinal order; the first hit must be the min (sectionIndex, chunkOrdinal).
        db.searchDaoInsertPublishedSection(section(bookA, 2, 5, "target term here", title = "later"))
        db.searchDaoInsertPublishedSection(section(bookA, 0, 1, "target term here", title = "earliest"))
        db.searchDaoInsertPublishedSection(section(bookA, 1, 3, "target term here", title = "middle"))
        val hit = dao.firstMatchingSection(bookA, "target")
        assertEquals("first hit is the lowest (sectionIndex, chunkOrdinal)", "earliest", hit?.sectionTitle)
    }

    // ---- settled-completeness (Gate-2 round-3 HIGH) ----

    @Test fun completeness_settledStatesCountAsComplete() = runBlocking {
        seedBook(bookA, format = "epub")
        seedBook(bookB, format = "txt")
        dao.markIndexed(SearchIndexStateEntity(bookA, 1, 1L, "indexed"))
        dao.markIndexed(SearchIndexStateEntity(bookB, 1, 1L, "skipped_unsupported"))
        assertEquals("indexed + skipped_unsupported are both settled", 0, dao.countUnsettledIndexable())
        assertTrue(dao.isIndexComplete())
    }

    @Test fun completeness_missingRow_isIncomplete() = runBlocking {
        seedBook(bookA, format = "epub")
        seedBook(bookB, format = "txt")
        dao.markIndexed(SearchIndexStateEntity(bookA, 1, 1L, "indexed"))
        // bookB has no state row → unsettled.
        assertEquals("a missing state row keeps completeness open", 1, dao.countUnsettledIndexable())
        assertFalse(dao.isIndexComplete())
    }

    @Test fun completeness_failedRow_isIncomplete() = runBlocking {
        seedBook(bookA, format = "epub")
        dao.markIndexed(SearchIndexStateEntity(bookA, 1, 1L, "failed"))
        assertEquals("a retryable failed row keeps completeness open", 1, dao.countUnsettledIndexable())
        assertFalse(dao.isIndexComplete())
    }

    @Test fun completeness_nonIndexableFormats_doNotBlock() = runBlocking {
        seedBook(bookA, format = "pdf")   // pdf/azw3 are metadata-only, not indexable
        seedBook(bookB, format = "azw3")
        assertEquals("pdf/azw3 books never block completeness", 0, dao.countUnsettledIndexable())
        assertTrue(dao.isIndexComplete())
    }

    @Test fun observeUnsettledIndexableCount_reEmitsAsBooksSettle() = runBlocking {
        seedBook(bookA, format = "epub")
        assertEquals("initially unsettled (no state row)", 1, dao.observeUnsettledIndexableCount().first())
        dao.markIndexed(SearchIndexStateEntity(bookA, 1, 1L, "indexed"))
        assertEquals("settles to 0 after indexing", 0, dao.observeUnsettledIndexableCount().first())
    }
}

/** Test-only helper: insert a section straight into the published content table (bypassing staging). */
private fun VReaderDatabase.searchDaoInsertPublishedSection(section: SearchSectionEntity) = runBlocking {
    searchDao().insertStagingBatch(
        listOf(
            SearchStagingEntity(
                bookKey = section.bookKey, sectionIndex = section.sectionIndex,
                chunkOrdinal = section.chunkOrdinal, sectionTitle = section.sectionTitle,
                text = section.text, indexedText = section.indexedText,
            ),
        ),
    )
    searchDao().copyStagingToSections(section.bookKey)
    searchDao().clearStaging(section.bookKey)
}
