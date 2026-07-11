package com.vreader.app.search

import com.vreader.app.data.Book
import com.vreader.app.data.Collection
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.BookFormat

/**
 * Feature #128 WI-6 — [SearchViewModel]: debounce, stale-query cancellation, empty→recents+collections,
 * iOS-parity metadata substring (incl. nil-author-never-matches + ß↔ss fold), CJK, ordering, counts,
 * `indexComplete` gating of the definitive no-results copy, and huge-library responsiveness.
 *
 * The in-text hits arrive through an injected deterministic [textHitsFor] seam (production =
 * SearchRepository::textHits) so the VM's pipeline is tested without a Room executor under runTest.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
class SearchViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    private fun book(key: String, title: String, author: String? = null, lastOpenedAt: Long? = null, format: BookFormat = BookFormat.epub) =
        Book(
            fingerprintKey = key, title = title, originalFormat = format,
            contentSHA256 = "x", fileByteCount = 1L, addedAt = 0L, lastOpenedAt = lastOpenedAt, author = author,
        )

    private fun hit(key: String, snippet: String = "…snippet…", title: String? = null) =
        TextHit(bookKey = key, sectionTitle = title, snippet = snippet, matchRanges = emptyList())

    /** A deterministic text-hit seam: the given hits are returned for any non-blank query. */
    private fun hits(vararg hits: TextHit): (String) -> Flow<List<TextHit>> = { flowOf(hits.toList()) }
    private val noHits: (String) -> Flow<List<TextHit>> = { flowOf(emptyList()) }

    private fun vm(
        library: Flow<List<Book>>,
        textHits: (String) -> Flow<List<TextHit>> = noHits,
        recents: Flow<List<String>> = flowOf(emptyList()),
        collections: Flow<List<Collection>> = flowOf(emptyList()),
        indexComplete: Flow<Boolean> = flowOf(true),
        record: suspend (String) -> Unit = {},
        d: CoroutineDispatcher = dispatcher,
    ) = SearchViewModel(
        libraryFlow = library, textHitsFor = textHits, recentsFlow = recents,
        collectionsFlow = collections, indexCompleteFlow = indexComplete, recordQuery = record,
        defaultDispatcher = d,
    )

    // ---- debounce + stale-query cancellation ----

    @Test fun debounce_collapsesRapidKeystrokes() = runTest(dispatcher) {
        val v = vm(flowOf(listOf(book("k", "The Pragmatic Programmer"))))
        advanceUntilIdle()
        v.onQueryChange("P")
        v.onQueryChange("Pr")
        v.onQueryChange("Pragmatic")
        advanceTimeBy(100)   // below the 300ms debounce — no result settle yet
        assertFalse("not searched before debounce elapses", v.state.value.searched)
        advanceUntilIdle()
        assertTrue("searched after debounce", v.state.value.searched)
        assertEquals(1, v.state.value.results.size)
    }

    @Test fun staleQuery_isSuperseded() = runTest(dispatcher) {
        val v = vm(flowOf(listOf(book("a", "Alpha"), book("b", "Beta"))))
        advanceUntilIdle()
        v.onQueryChange("Alpha")
        advanceTimeBy(50)
        v.onQueryChange("Beta")   // supersedes before the first debounce fires
        advanceUntilIdle()
        assertEquals("only the latest query's results", listOf("Beta"), v.state.value.results.map { it.book.title })
    }

    // ---- empty query → recents + collections ----

    @Test fun emptyQuery_exposesRecentsAndCollections() = runTest(dispatcher) {
        val recents = listOf("darcy", "elizabeth")
        val collections = listOf(Collection("c1", "Favorites", 0L, 3))
        val v = vm(flowOf(emptyList()), recents = flowOf(recents), collections = flowOf(collections))
        advanceUntilIdle()
        assertFalse("not searched with a blank query", v.state.value.searched)
        assertEquals(recents, v.state.value.recents)
        assertEquals(collections, v.state.value.collections)
        assertTrue("no results for a blank query", v.state.value.results.isEmpty())
    }

    // ---- metadata substring (iOS parity) ----

    @Test fun metadata_titleAndAuthorSubstring_caseInsensitive() = runTest(dispatcher) {
        val v = vm(flowOf(listOf(
            book("a", "Pride and Prejudice", author = "Jane Austen"),
            book("b", "Moby Dick", author = "Herman Melville"),
        )))
        advanceUntilIdle()
        v.onQueryChange("jane")
        advanceUntilIdle()
        assertEquals(listOf("Pride and Prejudice"), v.state.value.results.map { it.book.title })
        assertTrue("matched by author", v.state.value.results.single().authorMatch)
    }

    @Test fun metadata_nilAuthor_neverMatchesAuthor() = runTest(dispatcher) {
        val v = vm(flowOf(listOf(book("a", "Some Title", author = null))))
        advanceUntilIdle()
        v.onQueryChange("Title")   // title matches
        advanceUntilIdle()
        assertEquals(1, v.state.value.results.size)
        assertFalse("nil author never a match", v.state.value.results.single().authorMatch)

        v.onQueryChange("zzz-no-such-author")   // would only match a (nonexistent) author
        advanceUntilIdle()
        assertTrue("nil-author book not matched by an author query", v.state.value.results.isEmpty())
    }

    @Test fun metadata_eszettFold_matchesSsTitle() = runTest(dispatcher) {
        val v = vm(flowOf(listOf(book("a", "Die Strasse", author = null))))
        advanceUntilIdle()
        v.onQueryChange("Straße")   // ß folds to ss → matches "Strasse"
        advanceUntilIdle()
        assertEquals(1, v.state.value.results.size)
    }

    // ---- ordering: title > author > text-only; ties by lastOpenedAt desc then title ----

    @Test fun ordering_titleBeforeAuthorBeforeTextOnly() = runTest(dispatcher) {
        val v = vm(
            flowOf(listOf(
                book("textkey", "No Match Title", author = "No Match Author"),   // text-only hit
                book("authorkey", "Different", author = "Search Author"),        // author match
                book("titlekey", "Search In Title", author = null),              // title match
            )),
            textHits = hits(hit("textkey")),
        )
        advanceUntilIdle()
        v.onQueryChange("search")
        advanceUntilIdle()
        assertEquals(
            "title > author > text-only",
            listOf("titlekey", "authorkey", "textkey"),
            v.state.value.results.map { it.book.fingerprintKey },
        )
    }

    @Test fun ordering_tieBrokenByLastOpenedThenTitle() = runTest(dispatcher) {
        val v = vm(flowOf(listOf(
            book("a", "Alpha term", author = null, lastOpenedAt = 100L),
            book("b", "Beta term", author = null, lastOpenedAt = 500L),
            book("c", "Gamma term", author = null, lastOpenedAt = null),
        )))
        advanceUntilIdle()
        v.onQueryChange("term")
        advanceUntilIdle()
        // All title matches → tie broken by lastOpenedAt desc (b=500 > a=100 > c=null), then title.
        assertEquals(listOf("b", "a", "c"), v.state.value.results.map { it.book.fingerprintKey })
    }

    // ---- counts (N books · M in-text) ----

    @Test fun counts_reflectBooksAndInTextMatches() = runTest(dispatcher) {
        val v = vm(
            flowOf(listOf(
                book("hit1", "Metadata No Match", author = null),   // in-text hit only
                book("m1", "Widget Guide", author = null),          // title match, no text hit
            )),
            textHits = hits(hit("hit1")),
        )
        advanceUntilIdle()
        v.onQueryChange("widget")
        advanceUntilIdle()
        assertEquals("2 books matched", 2, v.state.value.bookCount)
        assertEquals("1 in-text match", 1, v.state.value.inTextMatchCount)
    }

    // ---- CJK title + in-text ----

    @Test fun cjk_titleAndInText() = runTest(dispatcher) {
        val v = vm(
            flowOf(listOf(
                book("cjktitle", "编程指南", author = null),
                book("cjktext", "无关标题", author = null),
            )),
            textHits = hits(hit("cjktext")),
        )
        advanceUntilIdle()
        v.onQueryChange("编程")
        advanceUntilIdle()
        assertEquals("both CJK books match (title + in-text)", 2, v.state.value.results.size)
    }

    // ---- indexComplete gates the definitive no-results copy ----

    @Test fun indexComplete_false_thenTrue() = runTest(dispatcher) {
        val complete = MutableStateFlow(false)
        val v = vm(flowOf(listOf(book("a", "Alpha"))), indexComplete = complete)
        advanceUntilIdle()
        v.onQueryChange("nomatchquery")   // no metadata + no text hit
        advanceUntilIdle()
        assertTrue("searched", v.state.value.searched)
        assertTrue("zero results", v.state.value.results.isEmpty())
        assertFalse("definitive copy suppressed while indexing incomplete", v.state.value.indexComplete)

        complete.value = true
        advanceUntilIdle()
        assertTrue("definitive copy shown once corpus is settled", v.state.value.indexComplete)
    }

    // ---- recordCurrentQuery ----

    @Test fun recordCurrentQuery_recordsTrimmedQuery() = runTest(dispatcher) {
        val recorded = mutableListOf<String>()
        val v = vm(flowOf(emptyList()), record = { recorded.add(it) })
        advanceUntilIdle()
        v.onQueryChange("  hobbit  ")
        v.recordCurrentQuery()
        advanceUntilIdle()
        assertEquals(listOf("hobbit"), recorded)
    }

    @Test fun recordCurrentQuery_blankIsNoOp() = runTest(dispatcher) {
        val recorded = mutableListOf<String>()
        val v = vm(flowOf(emptyList()), record = { recorded.add(it) })
        advanceUntilIdle()
        v.onQueryChange("   ")
        v.recordCurrentQuery()
        advanceUntilIdle()
        assertTrue("blank query not recorded", recorded.isEmpty())
    }

    // ---- huge-library responsiveness (1000 fake books) ----

    @Test fun hugeLibrary_1000books_respondsAndFiltersCorrectly() = runTest(dispatcher) {
        val books = (0 until 1000).map { book("k$it", "Book number $it", author = null) }
        val v = vm(flowOf(books))
        advanceUntilIdle()
        v.onQueryChange("number 42")   // matches "Book number 42" and 420-429 etc. — substring on title
        advanceUntilIdle()
        assertTrue("query over 1000 books settles with results", v.state.value.searched)
        // "number 42" is a substring of "Book number 42", "Book number 420".."429".
        assertTrue("finds the exact-number book", v.state.value.results.any { it.book.title == "Book number 42" })
        assertTrue("all results contain the query substring",
            v.state.value.results.all { SearchTextNormalizer.normalize(it.book.title).contains("number 42") })
    }
}
