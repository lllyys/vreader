package com.vreader.app.search

import com.vreader.app.data.SearchSectionEntity
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator as ReadiumLocator
import org.readium.r2.shared.util.Url
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat
import vreader.contracts.Locator

/**
 * Feature #133 WI-6 — [InBookSearchRepository]: the FORMAT-DISPATCHING integrator that unifies WI-1..WI-5.
 *
 * It routes EPUB → [EpubInBookSearchEngine] (adapting its self-contained EpubInBookHit/EpubGroup into the
 * shared InBookHit/InBookGroup DTOs) and TXT/MD → the FTS pipeline (SearchQueryBuilder → SearchDao →
 * RawOffsetMatcher → InBookSearchHitResolver), grouping hits by "Section N" and threading the
 * resume-within-chunk `SearchCursor.Fts(...,occurrenceIndex)` so append-on-scroll is COMPLETE.
 *
 * Boundaries faked here (not internal logic): the DAO (in-memory canned chunks), the TXT/MD resolver
 * (returns a deterministic canonical Locator — the offset math is WI-4's tested concern), and the EPUB
 * `PublicationSearchSource` seam (Readium `Publication` is final; the engine + real Readium `Locator`
 * value types are exercised through it). Robolectric-run because a REAL Readium `Locator` builds a `Url`
 * backed by `android.net.Uri`; the repository itself is pure JVM.
 *
 * Invariants asserted (plan §2 + WI-6 catalogue):
 * - EPUB page delegates to the engine (adapted to the shared DTOs; the Readium locator survives as JSON).
 * - TXT/MD groups by "Section N"; a multi-hit chunk expands to N hits in one group; the FTS cursor advances.
 * - RESUME-WITHIN-CHUNK completeness (round-3): a single chunk with more occurrences than `pageSize` is
 *   emitted across successive `page(...)` calls that thread the Fts(...,occurrenceIndex) cursor — the union
 *   across pages equals every occurrence (no gap, no dupe); `nextCursor` stays on the SAME chunk (re-fetched
 *   inclusively via `chunkAtOrAfter`) until fully consumed, then advances to the next chunk via
 *   `matchingChunksPage` with occurrenceIndex=0; moreAvailable is false ONLY at whole-book exhaustion.
 * - Blank / special-only query → empty (no DAO/MATCH call).
 * - MATCH-char safety: every query is routed through SearchQueryBuilder (quotes/`*`/parens/colon/caret/
 *   leading-`-`/AND-OR-NOT-case/special-only→empty/very-long) — a raw MATCH string never reaches the DAO.
 * - Cancellation mid-expansion: a cancelled scope stops expanding (no further DAO pages fetched).
 * - No cross-wiring: the EPUB path never touches the DAO; the TXT/MD path never touches the engine.
 */
@RunWith(RobolectricTestRunner::class)
class InBookSearchRepositoryTest {

    private val bookKey = "txt:${"a".repeat(64)}:1234"
    private val sha = "a".repeat(64)
    private val byteCount = 1234L

    // ---- Fake DAO (records the MATCH strings it is asked for; serves canned pages) -----------------

    /** A canned FTS store: matching chunks in reading order, paged by the (sectionIndex, chunkOrdinal, id)
     *  cursor tuple exactly as the real DAO does. */
    private class FakeSearchDao(private val chunks: List<SearchSectionEntity>) {
        val matchStringsSeen = mutableListOf<String>()
        var matchingChunksPageCalls = 0
        var chunkAtOrAfterCalls = 0

        private fun matched(ftsQuery: String): List<SearchSectionEntity> {
            matchStringsSeen.add(ftsQuery)
            // The fake does not re-run FTS; a non-empty query "matches" every canned chunk (the canned set
            // IS the match set). It only enforces the ordering + cursor semantics under test.
            return chunks.sortedWith(compareBy({ it.sectionIndex }, { it.chunkOrdinal }, { it.id }))
        }

        suspend fun matchingChunksPage(
            ftsQuery: String,
            afterSectionIndex: Int,
            afterChunkOrdinal: Int,
            afterId: Long,
            limit: Int,
        ): List<SearchSectionEntity> {
            matchingChunksPageCalls++
            return matched(ftsQuery).filter { s ->
                s.sectionIndex > afterSectionIndex ||
                    (s.sectionIndex == afterSectionIndex && s.chunkOrdinal > afterChunkOrdinal) ||
                    (s.sectionIndex == afterSectionIndex && s.chunkOrdinal == afterChunkOrdinal && s.id > afterId)
            }.take(limit)
        }

        suspend fun chunkAtOrAfter(
            ftsQuery: String,
            atSectionIndex: Int,
            atChunkOrdinal: Int,
            atId: Long,
        ): SearchSectionEntity? {
            chunkAtOrAfterCalls++
            return matched(ftsQuery).firstOrNull { s ->
                s.sectionIndex > atSectionIndex ||
                    (s.sectionIndex == atSectionIndex && s.chunkOrdinal > atChunkOrdinal) ||
                    (s.sectionIndex == atSectionIndex && s.chunkOrdinal == atChunkOrdinal && s.id >= atId)
            }
        }
    }

    private fun chunk(sectionIndex: Int, chunkOrdinal: Int, id: Long, text: String) = SearchSectionEntity(
        id = id, bookKey = bookKey, sectionIndex = sectionIndex, chunkOrdinal = chunkOrdinal,
        sectionTitle = null, text = text, indexedText = text.lowercase(),
    )

    /** A resolver that maps (sectionIndex, occurrence) → a deterministic in-range canonical Locator so the
     *  repository test asserts dispatch/grouping/cursor, not the WI-4 offset math (tested separately). */
    private inner class FakeResolver : InBookSearchHitResolver {
        override fun resolve(sectionIndex: Int, occurrence: RawOccurrence): Locator? = Locator(
            contentSHA256 = sha, fileByteCount = byteCount, format = "txt",
            charOffsetUTF16 = sectionIndex * 100_000 + occurrence.startUtf16,
            charRangeStartUTF16 = sectionIndex * 100_000 + occurrence.startUtf16,
            charRangeEndUTF16 = sectionIndex * 100_000 + occurrence.endUtf16,
        ).validatedOrNull()
    }

    /** The repository built over the FTS-track fakes (no EPUB engine — TXT/MD tests). */
    private fun ftsRepo(dao: FakeSearchDao, dispatcher: kotlinx.coroutines.CoroutineDispatcher) =
        InBookSearchRepository(
            dispatcher = dispatcher,
            fts = InBookFtsDeps(
                matchingChunksPage = { q, si, co, id, limit -> dao.matchingChunksPage(q, si, co, id, limit) },
                chunkAtOrAfter = { q, si, co, id -> dao.chunkAtOrAfter(q, si, co, id) },
                resolverFor = { FakeResolver() },
            ),
            epubEngineFor = { error("EPUB engine must NOT be built on the TXT/MD path") },
        )

    // ---- EPUB fakes (reuse the WI-5 seam) ----------------------------------------------------------

    private fun href(path: String): Url = requireNotNull(Url(path)) { "bad test href: $path" }

    private fun rloc(title: String?, highlight: String?, before: String? = "", after: String? = "",
                     path: String = "chapter1.xhtml"): ReadiumLocator = ReadiumLocator(
        href = href(path),
        mediaType = org.readium.r2.shared.util.mediatype.MediaType.XHTML,
        title = title,
        text = ReadiumLocator.Text(before = before, highlight = highlight, after = after),
    )

    private sealed interface Canned {
        data class Page(val locators: List<ReadiumLocator>) : Canned
        object Exhausted : Canned
    }

    private class FakeIterator(private val pages: MutableList<Canned>) : SearchIteratorSource {
        override suspend fun nextPage(): SearchPageResult =
            when (val next = if (pages.isEmpty()) Canned.Exhausted else pages.removeAt(0)) {
                is Canned.Page -> SearchPageResult.Locators(next.locators)
                Canned.Exhausted -> SearchPageResult.Exhausted
            }
        override fun close() = Unit
    }

    private class FakeSource(
        private val searchable: Boolean,
        private val pages: List<Canned> = emptyList(),
    ) : PublicationSearchSource {
        var openedWithQuery: String? = null
        override suspend fun isSearchable(): Boolean = searchable
        override suspend fun openIterator(query: String): SearchIteratorSource {
            openedWithQuery = query
            return FakeIterator(pages.toMutableList())
        }
    }

    private fun epubRepo(source: FakeSource, dispatcher: kotlinx.coroutines.CoroutineDispatcher,
                         pageSize: Int = 50) = InBookSearchRepository(
        dispatcher = dispatcher,
        fts = InBookFtsDeps(
            matchingChunksPage = { _, _, _, _, _ -> error("FTS DAO must NOT be called on the EPUB path") },
            chunkAtOrAfter = { _, _, _, _ -> error("FTS DAO must NOT be called on the EPUB path") },
            resolverFor = { error("TXT/MD resolver must NOT be built on the EPUB path") },
        ),
        epubEngineFor = { EpubInBookSearchEngine(source, pageSize = pageSize) },
    )

    // ---- EPUB dispatch -----------------------------------------------------------------------------

    @Test
    fun epub_delegatesToEngine_adaptsHitsToSharedDtos() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val l1 = rloc(title = "Chapter 1", highlight = "cat", before = "the ", after = " sat")
        val l2 = rloc(title = "Chapter 2", highlight = "cat")
        val source = FakeSource(searchable = true, pages = listOf(Canned.Page(listOf(l1, l2)), Canned.Exhausted))
        val repo = epubRepo(source, d)

        val outcome = repo.page(bookKey, BookFormat.epub, "cat", cursor = null, pageSize = 50)

        assertTrue(outcome is InBookSearchOutcome.Results)
        val page = (outcome as InBookSearchOutcome.Results).page
        assertEquals(listOf("Chapter 1", "Chapter 2"), page.groups.map { it.title })
        val hit = page.groups[0].hits[0]
        // The snippet is before+highlight+after ("the cat sat"); the highlight range covers exactly "cat".
        assertEquals("the cat sat", hit.snippet)
        assertEquals(listOf(IntRange(4, 6)), hit.matchRanges) // "cat" at [4,6] within "the cat sat"
        assertEquals("cat", hit.snippet.substring(4, 7))
        assertEquals("Chapter 1", hit.sectionTitle)
        assertNull("EPUB hits carry NO canonical locator", hit.canonicalLocator)
        assertNotNull("EPUB hits carry a Readium locator JSON", hit.readiumLocatorJson)
        // The query reached Readium verbatim (no engine-side normalization).
        assertEquals("cat", source.openedWithQuery)
    }

    @Test
    fun epub_notSearchable_yieldsUnsupported() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val repo = epubRepo(FakeSource(searchable = false), d)
        val outcome = repo.page(bookKey, BookFormat.epub, "cat", cursor = null, pageSize = 50)
        assertTrue(outcome is InBookSearchOutcome.Unsupported)
    }

    @Test
    fun epub_zeroHits_yieldsNoResults() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val source = FakeSource(searchable = true, pages = listOf(Canned.Exhausted))
        val outcome = epubRepo(source, d).page(bookKey, BookFormat.epub, "cat", cursor = null, pageSize = 50)
        assertTrue(outcome is InBookSearchOutcome.NoResults)
    }

    @Test
    fun epub_moreAvailable_resumesViaOpaqueCursor_completeAcrossPages() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val all = (1..5).map { rloc(title = "C", highlight = "cat$it") }
        val source = FakeSource(searchable = true, pages = listOf(Canned.Page(all), Canned.Exhausted))
        val repo = epubRepo(source, d, pageSize = 2)

        val collected = mutableListOf<String?>()
        var outcome = repo.page(bookKey, BookFormat.epub, "cat", cursor = null, pageSize = 2)
        while (outcome is InBookSearchOutcome.Results) {
            val page = outcome.page
            page.groups.forEach { g -> g.hits.forEach { collected.add(it.snippet) } }
            outcome = if (page.moreAvailable) {
                assertTrue("a non-terminal EPUB page carries an Epub cursor", page.nextCursor is SearchCursor.Epub)
                repo.page(bookKey, BookFormat.epub, "cat", cursor = page.nextCursor, pageSize = 2)
            } else {
                assertNull(page.nextCursor); break
            }
        }
        assertEquals((1..5).map { "cat$it" }, collected)
    }

    // ---- TXT/MD dispatch: grouping + multi-hit chunk expansion + cursor advance ---------------------

    @Test
    fun txt_groupsBySection_expandsMultiHitChunk() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        // ONE chunk (section 0) with the query "cat" appearing 3 times → 3 hits in one "Section 0" group.
        val dao = FakeSearchDao(listOf(chunk(0, 0, 10L, "cat and cat then cat end")))
        val repo = ftsRepo(dao, d)

        val outcome = repo.page(bookKey, BookFormat.txt, "cat", cursor = null, pageSize = 50)

        assertTrue(outcome is InBookSearchOutcome.Results)
        val page = (outcome as InBookSearchOutcome.Results).page
        assertEquals(1, page.groups.size)
        assertEquals("Section 1", page.groups[0].title) // human 1-based section label
        assertEquals(3, page.groups[0].hits.size)
        page.groups[0].hits.forEach {
            assertNotNull("TXT hits carry a canonical locator", it.canonicalLocator)
            assertNull("TXT hits carry NO Readium locator JSON", it.readiumLocatorJson)
        }
        assertFalse("one fully-consumed chunk with no more chunks is terminal", page.moreAvailable)
        assertNull(page.nextCursor)
    }

    @Test
    fun txt_multipleChunks_groupPerSection_cursorAdvances() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        // Three chunks in three sections; pageSize 2 so page 1 = sections 0..(budget) and a cursor advances.
        val dao = FakeSearchDao(listOf(
            chunk(0, 0, 10L, "cat one"),
            chunk(1, 1, 11L, "cat two"),
            chunk(2, 2, 12L, "cat three"),
        ))
        val repo = ftsRepo(dao, d)

        val collectedSections = mutableListOf<String?>()
        var outcome = repo.page(bookKey, BookFormat.txt, "cat", cursor = null, pageSize = 2)
        var guard = 0
        while (outcome is InBookSearchOutcome.Results && guard++ < 10) {
            val page = outcome.page
            page.groups.forEach { collectedSections.add(it.title) }
            if (page.moreAvailable) {
                assertTrue(page.nextCursor is SearchCursor.Fts)
                outcome = repo.page(bookKey, BookFormat.txt, "cat", cursor = page.nextCursor, pageSize = 2)
            } else break
        }
        // Every section's group is emitted across pages, in order, once.
        assertEquals(listOf("Section 1", "Section 2", "Section 3"), collectedSections)
    }

    // ---- RESUME-WITHIN-CHUNK completeness (round-3 Medium) ------------------------------------------

    @Test
    fun txt_resumeWithinChunk_unionIsComplete_noGapNoDupe() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        // ONE chunk with 5 occurrences of "cat", pageSize=2 → emitted across 3 pages via the intra-chunk
        // occurrenceIndex cursor. Union = all 5, no gap, no dupe; the chunk repeats until consumed.
        val text = "cat cat cat cat cat"
        val dao = FakeSearchDao(listOf(chunk(0, 0, 10L, text)))
        val repo = ftsRepo(dao, d)

        val offsets = mutableListOf<Int>()
        var cursor: SearchCursor? = null
        var pageCount = 0
        var sameChunkResumes = 0
        var outcome = repo.page(bookKey, BookFormat.txt, "cat", cursor = cursor, pageSize = 2)
        var guard = 0
        while (outcome is InBookSearchOutcome.Results && guard++ < 20) {
            val page = outcome.page
            pageCount++
            page.groups.forEach { g -> g.hits.forEach { offsets.add(it.canonicalLocator!!.charOffsetUTF16!!) } }
            val next = page.nextCursor
            if (page.moreAvailable) {
                assertTrue(next is SearchCursor.Fts)
                // A partial chunk keeps the same chunk id, only occurrenceIndex advances.
                if ((next as SearchCursor.Fts).id == 10L && next.occurrenceIndex > 0) sameChunkResumes++
                cursor = next
                outcome = repo.page(bookKey, BookFormat.txt, "cat", cursor = cursor, pageSize = 2)
            } else {
                assertNull(page.nextCursor); break
            }
        }
        // 5 occurrences at raw offsets 0,4,8,12,16 (chunk 0 → base 0), union complete + ordered + unique.
        assertEquals(listOf(0, 4, 8, 12, 16), offsets)
        assertEquals("distinct offsets — no duplicate emitted", offsets.size, offsets.distinct().size)
        assertTrue("more than one page was needed", pageCount >= 3)
        assertTrue("the same chunk was resumed at least once", sameChunkResumes >= 1)
        // Completeness relies on the inclusive re-fetch for the partial chunk.
        assertTrue("the partial chunk was re-fetched inclusively", dao.chunkAtOrAfterCalls >= 1)
    }

    @Test
    fun txt_moreAvailable_falseOnlyAtWholeBookExhaustion() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        // Two chunks, first has 3 occurrences, pageSize=2 → the book is exhausted only after BOTH chunks'
        // occurrences are emitted; moreAvailable must be true until then.
        val dao = FakeSearchDao(listOf(
            chunk(0, 0, 10L, "cat cat cat"),
            chunk(1, 1, 11L, "cat"),
        ))
        val repo = ftsRepo(dao, d)

        var outcome = repo.page(bookKey, BookFormat.txt, "cat", cursor = null, pageSize = 2)
        var lastMore = true
        var total = 0
        var guard = 0
        while (outcome is InBookSearchOutcome.Results && guard++ < 20) {
            val page = outcome.page
            total += page.groups.sumOf { it.hits.size }
            lastMore = page.moreAvailable
            if (page.moreAvailable) {
                outcome = repo.page(bookKey, BookFormat.txt, "cat", cursor = page.nextCursor, pageSize = 2)
            } else break
        }
        assertEquals("all 4 occurrences (3 + 1) retrieved", 4, total)
        assertFalse("moreAvailable is false only at whole-book exhaustion", lastMore)
    }

    // ---- Blank / MATCH-char safety -----------------------------------------------------------------

    @Test
    fun blankQuery_yieldsNoResults_withNoDaoCall() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val dao = FakeSearchDao(listOf(chunk(0, 0, 10L, "cat")))
        val repo = ftsRepo(dao, d)

        val outcome = repo.page(bookKey, BookFormat.txt, "   ", cursor = null, pageSize = 50)
        assertTrue(outcome is InBookSearchOutcome.NoResults)
        assertEquals("no DAO MATCH call for a blank query", 0, dao.matchingChunksPageCalls)
        assertEquals(0, dao.chunkAtOrAfterCalls)
    }

    @Test
    fun specialOnlyQuery_yieldsNoResults_withNoDaoCall() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val dao = FakeSearchDao(listOf(chunk(0, 0, 10L, "cat")))
        val repo = ftsRepo(dao, d)

        // A query that sanitizes to nothing (all FTS operator chars) → SearchQueryBuilder.ftsQuery == null.
        val outcome = repo.page(bookKey, BookFormat.txt, "\"*()-:^\"", cursor = null, pageSize = 50)
        assertTrue(outcome is InBookSearchOutcome.NoResults)
        assertEquals("no DAO MATCH call for a special-only query", 0, dao.matchingChunksPageCalls)
    }

    @Test
    fun matchSafety_allQueriesRoutedThroughBuilder_neverRawMatch() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        // A hostile raw query with every FTS4 operator; the DAO must only ever see the BUILT (sanitized)
        // MATCH string, never the raw text.
        val raw = "cat\" OR dog* (paren) -neg :col ^car AND not near"
        val dao = FakeSearchDao(listOf(chunk(0, 0, 10L, "cat dog")))
        val repo = ftsRepo(dao, d)

        repo.page(bookKey, BookFormat.txt, raw, cursor = null, pageSize = 50)

        assertTrue("the DAO was asked to MATCH", dao.matchStringsSeen.isNotEmpty())
        val expected = SearchQueryBuilder.ftsQuery(raw)!!.fts
        dao.matchStringsSeen.forEach { seen ->
            assertEquals("the DAO only ever sees the built MATCH string", expected, seen)
            assertFalse("the raw query never reaches the DAO", seen == raw)
        }
    }

    // ---- Cancellation mid-expansion ----------------------------------------------------------------

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    @Test
    fun cancellation_midExpansion_stopsFetchingPages() = runTest {
        val started = CompletableDeferred<Unit>()
        val gate = CompletableDeferred<Unit>()
        // A DAO whose first page BLOCKS on a gate so we can cancel the coroutine while it is expanding.
        val blockingDao = object {
            var pagesFetched = 0
            suspend fun matchingChunksPage(): List<SearchSectionEntity> {
                pagesFetched++
                if (pagesFetched == 1) { started.complete(Unit); gate.await() }
                return emptyList()
            }
        }
        val repo = InBookSearchRepository(
            dispatcher = StandardTestDispatcher(testScheduler),
            fts = InBookFtsDeps(
                matchingChunksPage = { _, _, _, _, _ -> blockingDao.matchingChunksPage() },
                chunkAtOrAfter = { _, _, _, _ -> null },
                resolverFor = { FakeResolver() },
            ),
            epubEngineFor = { error("no epub") },
        )

        val job: Job = launch {
            repo.page(bookKey, BookFormat.txt, "cat", cursor = null, pageSize = 50)
        }
        runCurrent()
        started.await()
        job.cancel()
        gate.complete(Unit)
        advanceUntilIdle()

        assertTrue("the coroutine was cancelled", job.isCancelled)
        assertEquals("no further DAO page fetched after cancellation", 1, blockingDao.pagesFetched)
    }
}
