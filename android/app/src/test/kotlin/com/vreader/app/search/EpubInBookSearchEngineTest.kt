package com.vreader.app.search

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.shared.publication.Locator as ReadiumLocator
import org.readium.r2.shared.util.Url
import org.robolectric.RobolectricTestRunner

/**
 * Feature #133 WI-5 — [EpubInBookSearchEngine]: the EPUB in-book search engine over Readium 3.3.0's OWN
 * `SearchService` (round-2 Critical-1 resolution — EPUB search/position does NOT use the #128 FTS index).
 *
 * The engine is exercised through a FAKE [PublicationSearchSource] (Readium `Publication` is final/unmockable
 * — same seam pattern #135's `PublicationLocatorSource` uses). The seam is faked; the LOCATORS the fake
 * returns are REAL Readium value types (`Locator`, `Locator.Text`) so the mapping (title -> group, text
 * highlight -> snippet, the raw locator retained for `navigator.go`) is asserted against genuine objects,
 * not stubs.
 *
 * Invariants asserted here (the plan §2 EPUB-track + WI-5 test catalogue):
 * - `isSearchable()` gates: a NOT-searchable publication yields the `Unsupported` outcome and NEVER opens
 *   an iterator / calls `search` (no crash).
 * - A page of Readium locators maps to [EpubInBookHit]s: `Locator.title` -> group key, `Locator.text.highlight`
 *   -> snippet (+ before/after context), and the RAW `readiumLocator` is retained verbatim on the hit.
 * - Hits are grouped by `Locator.title` (chapter), preserving first-seen order.
 * - An empty first page -> `NoResults`.
 * - Iterator exhaustion (`Exhausted`) -> the page carries `moreAvailable = false`.
 * - A page with more content available -> `moreAvailable = true`.
 * - A `SearchError` from the iterator -> the `Error` outcome (surfaced, not swallowed).
 * - A CJK query string is passed through to the source UNCHANGED (no re-normalization by the engine).
 *
 * Robolectric-run because building a REAL Readium `Locator` constructs a `Url` (backed by
 * `android.net.Uri`), which the plain JVM harness does not provide — the engine itself is pure JVM.
 */
@RunWith(RobolectricTestRunner::class)
class EpubInBookSearchEngineTest {

    // ---- Test doubles ------------------------------------------------------------------------------

    /** A canned page result the fake iterator hands back, in call order. */
    private sealed interface Canned {
        data class Page(val locators: List<ReadiumLocator>) : Canned
        object Exhausted : Canned
        data class Failure(val error: EpubSearchError) : Canned
    }

    private class FakeIterator(private val pages: MutableList<Canned>) : SearchIteratorSource {
        var closed = false
        override suspend fun nextPage(): SearchPageResult =
            when (val next = if (pages.isEmpty()) Canned.Exhausted else pages.removeAt(0)) {
                is Canned.Page -> SearchPageResult.Locators(next.locators)
                Canned.Exhausted -> SearchPageResult.Exhausted
                is Canned.Failure -> SearchPageResult.Failed(next.error)
            }

        override fun close() { closed = true }
    }

    private class FakeSource(
        private val searchable: Boolean,
        private val pages: List<Canned> = emptyList(),
    ) : PublicationSearchSource {
        var searchableCalls = 0
        var openedWithQuery: String? = null
        var lastIterator: FakeIterator? = null

        override suspend fun isSearchable(): Boolean {
            searchableCalls++
            return searchable
        }

        override suspend fun openIterator(query: String): SearchIteratorSource {
            openedWithQuery = query
            return FakeIterator(pages.toMutableList()).also { lastIterator = it }
        }
    }

    // ---- Locator builders (REAL Readium value types) -----------------------------------------------

    private fun href(path: String): Url = requireNotNull(Url(path)) { "bad test href: $path" }

    private fun loc(
        chapterTitle: String?,
        highlight: String,
        before: String = "",
        after: String = "",
        path: String = "chapter1.xhtml",
    ): ReadiumLocator = ReadiumLocator(
        href = href(path),
        mediaType = org.readium.r2.shared.util.mediatype.MediaType.XHTML,
        title = chapterTitle,
        text = ReadiumLocator.Text(before = before, highlight = highlight, after = after),
    )

    // ---- Tests -------------------------------------------------------------------------------------

    @Test
    fun notSearchable_yieldsUnsupported_andNeverOpensIterator() = runTest {
        val source = FakeSource(searchable = false)
        val engine = EpubInBookSearchEngine(source)

        val outcome = engine.searchFirstPage("anything")

        assertTrue(outcome is EpubSearchOutcome.Unsupported)
        assertEquals(1, source.searchableCalls)
        assertNull("search must NOT be opened when not searchable", source.openedWithQuery)
        assertNull(source.lastIterator)
    }

    @Test
    fun firstPage_mapsLocatorsToHits_titleGroup_snippetFromText_rawLocatorRetained() = runTest {
        val l1 = loc(chapterTitle = "Chapter 1", highlight = "cat", before = "the ", after = " sat")
        val l2 = loc(chapterTitle = "Chapter 1", highlight = "cat", before = "a ", after = " ran")
        val source = FakeSource(searchable = true, pages = listOf(Canned.Page(listOf(l1, l2)), Canned.Exhausted))
        val engine = EpubInBookSearchEngine(source)

        val outcome = engine.searchFirstPage("cat")
        assertTrue(outcome is EpubSearchOutcome.Results)
        val page = (outcome as EpubSearchOutcome.Results).page

        // One group ("Chapter 1"), two hits.
        assertEquals(1, page.groups.size)
        assertEquals("Chapter 1", page.groups[0].title)
        assertEquals(2, page.groups[0].hits.size)

        val hit0 = page.groups[0].hits[0]
        assertEquals("cat", hit0.snippet)
        assertEquals("the ", hit0.before)
        assertEquals(" sat", hit0.after)
        assertEquals("Chapter 1", hit0.sectionTitle)
        // The RAW Readium locator is retained verbatim for navigator.go.
        assertSame(l1, hit0.readiumLocator)
        assertSame(l2, page.groups[0].hits[1].readiumLocator)
    }

    @Test
    fun hits_groupedByTitle_preservingFirstSeenOrder() = runTest {
        val a1 = loc(chapterTitle = "Alpha", highlight = "x")
        val b1 = loc(chapterTitle = "Beta", highlight = "x")
        val a2 = loc(chapterTitle = "Alpha", highlight = "x")
        val source = FakeSource(
            searchable = true,
            pages = listOf(Canned.Page(listOf(a1, b1, a2)), Canned.Exhausted),
        )
        val engine = EpubInBookSearchEngine(source)

        val page = (engine.searchFirstPage("x") as EpubSearchOutcome.Results).page

        // First-seen order of titles is Alpha, Beta; a2 folds back into the Alpha group.
        assertEquals(listOf("Alpha", "Beta"), page.groups.map { it.title })
        assertEquals(2, page.groups[0].hits.size)
        assertEquals(1, page.groups[1].hits.size)
    }

    @Test
    fun nullTitle_groupsUnderNullKey() = runTest {
        val l1 = loc(chapterTitle = null, highlight = "x")
        val source = FakeSource(searchable = true, pages = listOf(Canned.Page(listOf(l1)), Canned.Exhausted))
        val engine = EpubInBookSearchEngine(source)

        val page = (engine.searchFirstPage("x") as EpubSearchOutcome.Results).page
        assertEquals(1, page.groups.size)
        assertNull(page.groups[0].title)
        assertNull(page.groups[0].hits[0].sectionTitle)
    }

    @Test
    fun emptyFirstPage_yieldsNoResults() = runTest {
        // First next() returns an EMPTY page, then exhausted — no locators at all.
        val source = FakeSource(
            searchable = true,
            pages = listOf(Canned.Page(emptyList()), Canned.Exhausted),
        )
        val engine = EpubInBookSearchEngine(source)

        val outcome = engine.searchFirstPage("cat")
        assertTrue(outcome is EpubSearchOutcome.NoResults)
    }

    @Test
    fun immediateExhaustion_yieldsNoResults() = runTest {
        val source = FakeSource(searchable = true, pages = listOf(Canned.Exhausted))
        val engine = EpubInBookSearchEngine(source)

        val outcome = engine.searchFirstPage("cat")
        assertTrue(outcome is EpubSearchOutcome.NoResults)
    }

    @Test
    fun exhaustedAfterOnePage_marksMoreAvailableFalse() = runTest {
        val l1 = loc(chapterTitle = "C", highlight = "cat")
        val source = FakeSource(
            searchable = true,
            pages = listOf(Canned.Page(listOf(l1)), Canned.Exhausted),
        )
        val engine = EpubInBookSearchEngine(source)

        val page = (engine.searchFirstPage("cat") as EpubSearchOutcome.Results).page
        assertFalse(page.moreAvailable)
    }

    @Test
    fun morePagesAvailable_marksMoreAvailableTrue() = runTest {
        val l1 = loc(chapterTitle = "C", highlight = "cat")
        val l2 = loc(chapterTitle = "D", highlight = "cat")
        // Two content locators queued, pageSize=1 -> the fill stops after the first hit while the
        // iterator still has more, so moreAvailable is true and only one hit is collected.
        val source = FakeSource(
            searchable = true,
            pages = listOf(Canned.Page(listOf(l1)), Canned.Page(listOf(l2))),
        )
        val engine = EpubInBookSearchEngine(source, pageSize = 1)

        val page = (engine.searchFirstPage("cat") as EpubSearchOutcome.Results).page
        assertEquals(1, page.groups.sumOf { it.hits.size })
        assertTrue(page.moreAvailable)
    }

    @Test
    fun searchError_yieldsErrorOutcome_notSwallowed() = runTest {
        val err = EpubSearchError("engine boom")
        val source = FakeSource(searchable = true, pages = listOf(Canned.Failure(err)))
        val engine = EpubInBookSearchEngine(source)

        val outcome = engine.searchFirstPage("cat")
        assertTrue(outcome is EpubSearchOutcome.Error)
        assertSame(err, (outcome as EpubSearchOutcome.Error).error)
    }

    @Test
    fun errorMidPaging_afterSomeHits_stillSurfacesError() = runTest {
        val l1 = loc(chapterTitle = "C", highlight = "cat")
        val err = EpubSearchError("boom later")
        // First page has hits, but the SAME first-page fill needs a second next() (it did not
        // fill the page budget), which fails -> the error must surface, not be swallowed.
        val source = FakeSource(
            searchable = true,
            pages = listOf(Canned.Page(listOf(l1)), Canned.Failure(err)),
        )
        val engine = EpubInBookSearchEngine(source, pageSize = 10)

        val outcome = engine.searchFirstPage("cat")
        assertTrue("an error after partial hits must surface", outcome is EpubSearchOutcome.Error)
        assertSame(err, (outcome as EpubSearchOutcome.Error).error)
    }

    @Test
    fun cjkQuery_passesThroughToSource_unchanged() = runTest {
        val cjk = "编程"
        val l1 = loc(chapterTitle = "第一章", highlight = cjk)
        val source = FakeSource(searchable = true, pages = listOf(Canned.Page(listOf(l1)), Canned.Exhausted))
        val engine = EpubInBookSearchEngine(source)

        engine.searchFirstPage(cjk)
        // The engine does NOT re-normalize; the query reaches Readium verbatim.
        assertEquals(cjk, source.openedWithQuery)
    }

    @Test
    fun pageSize_bounds_firstPageFill_stopsAtBudget() = runTest {
        val hits = (1..5).map { loc(chapterTitle = "C", highlight = "cat$it") }
        // Each Readium page is one locator; pageSize=3 -> fill stops after 3, more available.
        val source = FakeSource(
            searchable = true,
            pages = hits.map { Canned.Page(listOf(it)) },
        )
        val engine = EpubInBookSearchEngine(source, pageSize = 3)

        val page = (engine.searchFirstPage("cat") as EpubSearchOutcome.Results).page
        assertEquals(3, page.groups.sumOf { it.hits.size })
        assertTrue(page.moreAvailable)
    }
}
