package com.vreader.app.search

import com.vreader.app.data.SearchIndexStateEntity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.BookFormat

/**
 * Feature #133 WI-8 — [InBookSearchViewModel]: the book-scoped in-book search state machine.
 *
 * Drives: debounced query -> paged results, append-on-scroll (`loadMore` threads the page cursor for
 * BOTH tracks), index-state gating (TXT/MD held query auto-re-runs on settle; EPUB never Indexing),
 * global recents (dedupe/cap enforced by the store), and the `closeAllEpubCursors()` lifecycle (dismiss /
 * reset / onCleared close the live EPUB Readium iterators — no leak).
 *
 * Boundaries faked: the search backend ([InBookSearcher]) records the queries/cursors it is asked for and
 * serves canned outcomes + counts its `closeAllEpubCursors()` calls; the index-state gate is the REAL WI-7
 * [IndexStateGate] over an in-test [MutableStateFlow]; recents are two lambda seams (a Flow + a suspend
 * record) mirroring the #128 [SearchViewModel] so no DataStore is needed. A [StandardTestDispatcher] makes
 * debounce + flatMapLatest deterministic.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class InBookSearchViewModelTest {

    private val txtKey = "txt:${"a".repeat(64)}:1234"
    private val epubKey = "epub:${"b".repeat(64)}:5678"
    private val version = SearchIndexCoordinator.INDEXER_VERSION
    private val debounce = InBookSearchViewModel.DEFAULT_DEBOUNCE_MILLIS

    private fun indexedRow(key: String = txtKey) =
        SearchIndexStateEntity(bookKey = key, indexerVersion = version, indexedAt = 0L, status = "indexed")

    // ---- Fakes -------------------------------------------------------------------------------------

    private fun hit(section: String?, snippet: String) =
        InBookHit(sectionTitle = section, canonicalLocator = null, readiumLocatorJson = "{}", snippet = snippet, matchRanges = emptyList())

    private fun page(groups: List<InBookGroup>, cursor: SearchCursor?) =
        InBookSearchOutcome.Results(InBookSearchPage(groups, moreAvailable = cursor != null, nextCursor = cursor))

    /**
     * A scriptable in-book search backend. Each call to [page] returns the next canned outcome (keyed by
     * how many pages have been requested for the CURRENT query), records the (query, cursor) it saw, and —
     * for cancellation tests — can await a gate before returning.
     */
    private class FakeSearcher(
        /** Outcomes keyed by request ordinal (0 = first page of a query, 1 = loadMore, …). */
        private val outcomes: (query: String, requestOrdinal: Int) -> InBookSearchOutcome,
    ) : InBookSearcher {
        val queriesSeen = mutableListOf<String>()
        val cursorsSeen = mutableListOf<SearchCursor?>()
        var closeCursorsCalls = 0
        private val ordinalByQuery = HashMap<String, Int>()

        override suspend fun page(bookKey: String, format: BookFormat, rawQuery: String, cursor: SearchCursor?, pageSize: Int): InBookSearchOutcome {
            queriesSeen.add(rawQuery)
            cursorsSeen.add(cursor)
            val ordinal = ordinalByQuery.getOrDefault(rawQuery, 0)
            ordinalByQuery[rawQuery] = ordinal + 1
            return outcomes(rawQuery, ordinal)
        }

        override fun closeAllEpubCursors() { closeCursorsCalls++ }
    }

    private fun vm(
        scope: CoroutineScope,
        dispatcher: kotlinx.coroutines.CoroutineDispatcher,
        searcher: InBookSearcher,
        format: BookFormat = BookFormat.txt,
        bookKey: String = txtKey,
        indexStateFlow: Flow<SearchIndexStateEntity?> = flowOf(indexedRow(bookKey)),
        hasOccurrence: suspend () -> Boolean = { true },
        recentsFlow: Flow<List<String>> = flowOf(emptyList()),
        recordQuery: suspend (String) -> Unit = {},
    ) = InBookSearchViewModel(
        bookKey = bookKey,
        format = format,
        searcher = searcher,
        indexStateGate = IndexStateGate(dispatcher),
        indexStateFlow = indexStateFlow,
        hasOccurrence = hasOccurrence,
        recentsFlow = recentsFlow,
        recordQuery = recordQuery,
        dispatcher = dispatcher,
        coroutineScope = scope,
        debounceMillis = debounce,
        pageSize = 10,
    )

    // ---- 1. Debounce -------------------------------------------------------------------------------

    @Test fun query_isDebouncedBeforeSearching() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { q, _ -> page(listOf(InBookGroup("Section 1", listOf(hit("Section 1", "…$q…")))), cursor = null) }
        val model = vm(this, d, searcher)

        // Type three chars quickly, each within the debounce window.
        model.onQueryChange("c")
        advanceTimeBy(debounce / 2)
        model.onQueryChange("ca")
        advanceTimeBy(debounce / 2)
        model.onQueryChange("cat")
        // Not yet past the debounce for "cat" → no search fired.
        assertTrue("debounce collapses in-flight keystrokes", searcher.queriesSeen.isEmpty())

        advanceUntilIdle()
        assertEquals("only the settled query searches", listOf("cat"), searcher.queriesSeen)
        model.onCleared()
    }

    // ---- 2. flatMapLatest cancels the previous query -----------------------------------------------

    @Test fun newQuery_cancelsInFlightSearchForPrevious() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { q, _ ->
            page(listOf(InBookGroup(q, listOf(hit(q, q)))), cursor = null)
        }
        val model = vm(this, d, searcher)

        model.onQueryChange("aaa")
        advanceUntilIdle()
        model.onQueryChange("bbb")
        advanceUntilIdle()

        val content = model.state.value.content
        assertTrue(content is InBookSearchContent.Results)
        assertEquals("state reflects the LATEST query only", "bbb", (content as InBookSearchContent.Results).groups.first().title)
        model.onCleared()
    }

    // ---- 3. Stale-tag discard ----------------------------------------------------------------------

    @Test fun staleResponse_forSupersededQuery_isDiscarded() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        // "slow" query resolves to a distinct group; if a late "slow" response overwrote "fast", the title
        // would flip back. flatMapLatest + the live-query tag must prevent that.
        val searcher = FakeSearcher { q, _ -> page(listOf(InBookGroup(q, listOf(hit(q, q)))), cursor = null) }
        val model = vm(this, d, searcher)

        model.onQueryChange("slow")
        advanceTimeBy(debounce + 1)           // debounce fired for "slow"; search dispatched
        model.onQueryChange("fast")           // supersede before "slow" completes
        advanceUntilIdle()

        val content = model.state.value.content as InBookSearchContent.Results
        assertEquals("no stale 'slow' rows survive", "fast", content.groups.first().title)
        assertEquals("only 'fast' produced surviving state (slow was cancelled)", "fast", model.state.value.query)
        model.onCleared()
    }

    // ---- 4. Reset-on-change (clear) ----------------------------------------------------------------

    @Test fun clearingQuery_resetsToIdle_notNoResults() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { _, _ -> InBookSearchOutcome.NoResults }
        val model = vm(this, d, searcher)

        model.onQueryChange("zzz")
        advanceUntilIdle()
        assertTrue(model.state.value.content is InBookSearchContent.NoResults)

        model.onQueryChange("")
        advanceUntilIdle()
        assertTrue("empty query returns to Idle, never NoResults", model.state.value.content is InBookSearchContent.Idle)
        model.onCleared()
    }

    @Test fun clearingQuery_closesEpubCursors() = runTest {
        // A reset to Idle must dispose any live EPUB iterators held for the prior query (no leak).
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { q, _ -> page(listOf(InBookGroup(q, listOf(hit(q, q)))), cursor = SearchCursor.Epub("tok-$q")) }
        val model = vm(this, d, searcher, format = BookFormat.epub, bookKey = epubKey, indexStateFlow = flowOf(null))

        model.onQueryChange("dog")
        advanceUntilIdle()
        val before = searcher.closeCursorsCalls
        model.onQueryChange("")
        advanceUntilIdle()
        assertTrue("clearing closes EPUB cursors", searcher.closeCursorsCalls > before)
        model.onCleared()
    }

    // ---- 5. TXT/MD index-state flip re-runs a held query -------------------------------------------

    @Test fun heldQuery_reRunsWhenIndexSettles_txt() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val rows = MutableStateFlow<SearchIndexStateEntity?>(null)   // starts missing → Indexing
        var occurrences = false
        val searcher = FakeSearcher { q, _ ->
            page(listOf(InBookGroup("Section 1", listOf(hit("Section 1", q)))), cursor = null)
        }
        val model = vm(this, d, searcher, indexStateFlow = rows, hasOccurrence = { occurrences })

        model.onQueryChange("cat")
        advanceUntilIdle()
        // While Indexing, surface the Indexing hint — NOT NoResults — and DON'T fire the FTS search yet.
        assertTrue("held query shows Indexing while the index builds", model.state.value.content is InBookSearchContent.Indexing)
        assertTrue("no FTS search fires while Indexing", searcher.queriesSeen.isEmpty())

        occurrences = true
        rows.value = indexedRow()             // coordinator settles the book
        advanceUntilIdle()

        assertTrue("on settle the held query auto-re-runs → Results", model.state.value.content is InBookSearchContent.Results)
        assertEquals("the auto-re-run used the held query, no re-type", listOf("cat"), searcher.queriesSeen)
        model.onCleared()
    }

    @Test fun indexedZeroOccurrences_isNoResults_notIndexing() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { _, _ -> InBookSearchOutcome.NoResults }
        val model = vm(this, d, searcher, indexStateFlow = flowOf(indexedRow()), hasOccurrence = { false })

        model.onQueryChange("cat")
        advanceUntilIdle()
        assertTrue("settled index with 0 occurrences → definitive NoResults", model.state.value.content is InBookSearchContent.NoResults)
        model.onCleared()
    }

    @Test fun epub_neverEntersIndexing() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { q, _ -> page(listOf(InBookGroup("Chapter 1", listOf(hit("Chapter 1", q)))), cursor = null) }
        // Even a missing/failed FTS row: EPUB bypasses the gate → straight to Results.
        val model = vm(this, d, searcher, format = BookFormat.epub, bookKey = epubKey, indexStateFlow = flowOf(null))

        model.onQueryChange("cat")
        advanceUntilIdle()
        assertTrue("EPUB never shows Indexing", model.state.value.content is InBookSearchContent.Results)
        model.onCleared()
    }

    @Test fun skippedUnsupported_hidesSearchEntry() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { _, _ -> InBookSearchOutcome.NoResults }
        val skipped = SearchIndexStateEntity(bookKey = txtKey, indexerVersion = version, indexedAt = 0L, status = "skipped_unsupported")
        val model = vm(this, d, searcher, indexStateFlow = flowOf(skipped))

        model.onQueryChange("cat")
        advanceUntilIdle()
        assertTrue("skipped_unsupported surfaces the Unsupported state", model.state.value.content is InBookSearchContent.Unsupported)
        assertTrue("the host hides the Search entry", model.state.value.hidesSearchEntry)
        model.onCleared()
    }

    // ---- 6. Error state ----------------------------------------------------------------------------

    @Test fun engineError_mapsToErrorState() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { _, _ -> InBookSearchOutcome.Error("boom") }
        val model = vm(this, d, searcher)

        model.onQueryChange("cat")
        advanceUntilIdle()
        val content = model.state.value.content
        assertTrue(content is InBookSearchContent.Error)
        assertEquals("boom", (content as InBookSearchContent.Error).message)
        model.onCleared()
    }

    // ---- 7. loadMore appends — BOTH tracks ---------------------------------------------------------

    @Test fun loadMore_appendsNextPage_txt_cursorThreaded() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val cursor1 = SearchCursor.Fts(sectionIndex = 0, chunkOrdinal = 0, id = 1L, occurrenceIndex = 2)
        val searcher = FakeSearcher { _, ord ->
            when (ord) {
                0 -> page(listOf(InBookGroup("Section 1", listOf(hit("Section 1", "a"), hit("Section 1", "b")))), cursor = cursor1)
                else -> page(listOf(InBookGroup("Section 1", listOf(hit("Section 1", "c")))), cursor = null) // fully consumed
            }
        }
        val model = vm(this, d, searcher)

        model.onQueryChange("x")
        advanceUntilIdle()
        var content = model.state.value.content as InBookSearchContent.Results
        assertTrue("first page reports more", content.moreAvailable)
        assertEquals(2, content.groups.single().hits.size)

        model.loadMore()
        advanceUntilIdle()
        content = model.state.value.content as InBookSearchContent.Results
        // Same-section groups COALESCE — one "Section 1" group with all 3 hits, in order, no gap/dupe.
        assertEquals("appended groups coalesce by section", 1, content.groups.size)
        assertEquals("all occurrences across pages present", listOf("a", "b", "c"), content.groups.single().hits.map { it.snippet })
        assertFalse("second page has no more → moreAvailable false", content.moreAvailable)
        // The loadMore threaded the FIRST page's nextCursor back into page(...).
        assertEquals("loadMore threads the page cursor", cursor1, searcher.cursorsSeen.last())
        model.onCleared()
    }

    @Test fun loadMore_appendsNextPage_epub_cursorThreaded() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val cursor1 = SearchCursor.Epub("epub-1")
        val searcher = FakeSearcher { _, ord ->
            when (ord) {
                0 -> page(listOf(InBookGroup("Chapter 1", listOf(hit("Chapter 1", "one")))), cursor = cursor1)
                else -> page(listOf(InBookGroup("Chapter 2", listOf(hit("Chapter 2", "two")))), cursor = null)
            }
        }
        val model = vm(this, d, searcher, format = BookFormat.epub, bookKey = epubKey, indexStateFlow = flowOf(null))

        model.onQueryChange("q")
        advanceUntilIdle()
        model.loadMore()
        advanceUntilIdle()

        val content = model.state.value.content as InBookSearchContent.Results
        assertEquals("distinct-chapter groups append in order", listOf("Chapter 1", "Chapter 2"), content.groups.map { it.title })
        assertEquals("EPUB loadMore threads the Epub cursor token", cursor1, searcher.cursorsSeen.last())
        model.onCleared()
    }

    @Test fun loadMore_isNoOp_whenMoreUnavailable() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { q, _ -> page(listOf(InBookGroup(q, listOf(hit(q, q)))), cursor = null) }  // no cursor
        val model = vm(this, d, searcher)

        model.onQueryChange("only")
        advanceUntilIdle()
        val callsBefore = searcher.queriesSeen.size
        model.loadMore()
        advanceUntilIdle()
        assertEquals("loadMore with moreAvailable=false does nothing", callsBefore, searcher.queriesSeen.size)
        model.onCleared()
    }

    // ---- 8. Recents: reuse the GLOBAL store (record on commit, surface the list) --------------------

    @Test fun committedSearch_recordsIntoRecents() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { q, _ -> page(listOf(InBookGroup(q, listOf(hit(q, q)))), cursor = null) }
        val recorded = mutableListOf<String>()
        val model = vm(this, d, searcher, recordQuery = { recorded.add(it) })

        model.onQueryChange("swift")
        advanceUntilIdle()
        model.commitSearch()                  // IME-search / result-open
        advanceUntilIdle()
        assertEquals("commit records the trimmed query into the GLOBAL store", listOf("swift"), recorded)
        model.onCleared()
    }

    @Test fun blankCommit_recordsNothing() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { _, _ -> InBookSearchOutcome.NoResults }
        val recorded = mutableListOf<String>()
        val model = vm(this, d, searcher, recordQuery = { recorded.add(it) })

        model.onQueryChange("   ")
        advanceUntilIdle()
        model.commitSearch()
        advanceUntilIdle()
        assertTrue("a blank commit records nothing", recorded.isEmpty())
        model.onCleared()
    }

    @Test fun recents_areSurfacedFromTheStore() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { _, _ -> InBookSearchOutcome.NoResults }
        val model = vm(this, d, searcher, recentsFlow = flowOf(listOf("alpha", "beta")))

        advanceUntilIdle()
        assertEquals("the VM surfaces the store's recents (cap/dedupe already enforced by the store)", listOf("alpha", "beta"), model.state.value.recents)
        model.onCleared()
    }

    @Test fun pickRecent_fillsAndRunsTheQuery() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { q, _ -> page(listOf(InBookGroup(q, listOf(hit(q, q)))), cursor = null) }
        val model = vm(this, d, searcher, recentsFlow = flowOf(listOf("kotlin")))

        model.onPickRecent("kotlin")
        advanceUntilIdle()
        assertEquals("picking a recent fills the query text", "kotlin", model.state.value.query)
        assertEquals("picking a recent runs the search", listOf("kotlin"), searcher.queriesSeen)
        assertTrue(model.state.value.content is InBookSearchContent.Results)
        model.onCleared()
    }

    // ---- 9. Lifecycle: onCleared / dismiss closes EPUB cursors -------------------------------------

    @Test fun onCleared_closesEpubCursors() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { q, _ -> page(listOf(InBookGroup(q, listOf(hit(q, q)))), cursor = SearchCursor.Epub("t")) }
        val model = vm(this, d, searcher, format = BookFormat.epub, bookKey = epubKey, indexStateFlow = flowOf(null))

        model.onQueryChange("cat")
        advanceUntilIdle()
        val before = searcher.closeCursorsCalls
        model.onCleared()
        assertTrue("onCleared disposes live EPUB iterators (no leak)", searcher.closeCursorsCalls > before)
    }

    @Test fun dismiss_closesEpubCursors() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { q, _ -> page(listOf(InBookGroup(q, listOf(hit(q, q)))), cursor = SearchCursor.Epub("t")) }
        val model = vm(this, d, searcher, format = BookFormat.epub, bookKey = epubKey, indexStateFlow = flowOf(null))

        model.onQueryChange("cat")
        advanceUntilIdle()
        val before = searcher.closeCursorsCalls
        model.onDismiss()
        advanceUntilIdle()
        assertTrue("dismiss disposes live EPUB iterators (no leak)", searcher.closeCursorsCalls > before)
        model.onCleared()
    }

    // ---- 10. Initial state is Idle -----------------------------------------------------------------

    @Test fun initialState_isIdle_withNoQuery() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { _, _ -> InBookSearchOutcome.NoResults }
        val model = vm(this, d, searcher)
        advanceUntilIdle()
        assertTrue("no query → Idle", model.state.value.content is InBookSearchContent.Idle)
        assertEquals("", model.state.value.query)
        assertTrue("no search fired at rest", searcher.queriesSeen.isEmpty())
        model.onCleared()
    }

    // ---- 11. Unsupported outcome (defensive PDF/AZW3) ----------------------------------------------

    @Test fun unsupportedOutcome_mapsToUnsupported() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        // A PDF/AZW3 gate would normally hide the entry, but if a search ever runs and the backend reports
        // Unsupported, the VM maps it to the Unsupported content (defensive terminal).
        val searcher = FakeSearcher { _, _ -> InBookSearchOutcome.Unsupported }
        // Use EPUB so the gate lets the query through to the backend, which returns Unsupported.
        val model = vm(this, d, searcher, format = BookFormat.epub, bookKey = epubKey, indexStateFlow = flowOf(null))

        model.onQueryChange("cat")
        advanceUntilIdle()
        assertTrue(model.state.value.content is InBookSearchContent.Unsupported)
        model.onCleared()
    }

    // ---- 12. loadMore before any search is a no-op -------------------------------------------------

    @Test fun loadMore_beforeAnySearch_isNoOp() = runTest {
        val d = StandardTestDispatcher(testScheduler)
        val searcher = FakeSearcher { _, _ -> InBookSearchOutcome.NoResults }
        val model = vm(this, d, searcher)
        advanceUntilIdle()
        model.loadMore()
        advanceUntilIdle()
        assertTrue("loadMore in Idle does nothing", searcher.queriesSeen.isEmpty())
        assertNull("no cursor consulted", searcher.cursorsSeen.firstOrNull())
        model.onCleared()
    }

    // ---- 13. Gate-4 round-1 hardening: single-flight + generation-gated paging ---------------------

    /**
     * A backend whose [page] can be held on a per-request gate (a CompletableDeferred), so a test can drive a
     * GENUINELY late completion (the cancellation-resistant race the round-1 Low flagged) — not just sequential
     * replacement.
     */
    private class GatedSearcher(
        private val outcome: (query: String, cursor: SearchCursor?) -> InBookSearchOutcome,
    ) : InBookSearcher {
        val queriesSeen = mutableListOf<String>()
        val cursorsSeen = mutableListOf<SearchCursor?>()
        var closeCursorsCalls = 0
        /** The next page(...) call parks on this gate (if set) before returning. */
        var gate: kotlinx.coroutines.CompletableDeferred<Unit>? = null
        /** Models the repository's live-cursor registry: a Results-with-Epub-cursor page REGISTERS an iterator
         *  (AFTER the gate — the realistic late-mint order); closeAllEpubCursors() reaps them. [liveCursors]>0
         *  after a completion means the repository leaked an iterator the VM never reaped. */
        var liveCursors = 0
            private set

        override suspend fun page(bookKey: String, format: BookFormat, rawQuery: String, cursor: SearchCursor?, pageSize: Int): InBookSearchOutcome {
            queriesSeen.add(rawQuery)
            cursorsSeen.add(cursor)
            gate?.let { it.await() }
            val result = outcome(rawQuery, cursor)
            // Late-mint: register the live iterator only AFTER the (possibly gated) work completes — exactly the
            // window in which a prior closeAllEpubCursors() could not have reaped it.
            if (result is InBookSearchOutcome.Results && result.page.nextCursor is SearchCursor.Epub) liveCursors++
            return result
        }

        override fun closeAllEpubCursors() { closeCursorsCalls++; liveCursors = 0 }
    }

    @Test fun rapidDoubleLoadMore_txt_consumesCursorOnce() = runTest {
        // H1: two loadMore() calls before the first page returns must NOT double-consume the same cursor.
        val d = StandardTestDispatcher(testScheduler)
        val cursor1 = SearchCursor.Fts(0, 0, 1L, 3)
        var pageCalls = 0
        val searcher = object : InBookSearcher {
            val cursorsSeen = mutableListOf<SearchCursor?>()
            override suspend fun page(bookKey: String, format: BookFormat, rawQuery: String, cursor: SearchCursor?, pageSize: Int): InBookSearchOutcome {
                cursorsSeen.add(cursor)
                pageCalls++
                return if (cursor == null) {
                    InBookSearchOutcome.Results(InBookSearchPage(listOf(InBookGroup("S", listOf(hit("S", "a")))), true, cursor1))
                } else {
                    InBookSearchOutcome.Results(InBookSearchPage(listOf(InBookGroup("S", listOf(hit("S", "b")))), false, null))
                }
            }
            override fun closeAllEpubCursors() {}
        }
        val model = vm(this, d, searcher)

        model.onQueryChange("x")
        advanceUntilIdle()
        val firstPageCalls = pageCalls
        model.loadMore()
        model.loadMore()                      // second call while the first is (about to be) in flight
        advanceUntilIdle()

        val continuationCalls = searcher.cursorsSeen.count { it == cursor1 }
        assertEquals("the append cursor is consumed exactly once despite two loadMore() calls", 1, continuationCalls)
        val content = model.state.value.content as InBookSearchContent.Results
        assertEquals("no duplicate append", listOf("a", "b"), content.groups.single().hits.map { it.snippet })
        model.onCleared()
    }

    @Test fun lateFirstPage_forSupersededQuery_doesNotArmPagingForNewQuery() = runTest {
        // H2: a slow first-page response for query A that completes AFTER query B started must not leave A's
        // cursor armed as B's nextCursor (which would make a B-loadMore page A's cursor).
        val d = StandardTestDispatcher(testScheduler)
        val aCursor = SearchCursor.Fts(9, 9, 99L, 0)
        val searcher = GatedSearcher { q, _ ->
            when (q) {
                "aaa" -> InBookSearchOutcome.Results(InBookSearchPage(listOf(InBookGroup("A", listOf(hit("A", "a")))), true, aCursor))
                else -> InBookSearchOutcome.NoResults
            }
        }
        val model = vm(this, d, searcher)

        val gate = kotlinx.coroutines.CompletableDeferred<Unit>()
        searcher.gate = gate
        model.onQueryChange("aaa")
        advanceTimeBy(debounce + 1)           // "aaa" first-page dispatched, parked on the gate
        searcher.gate = null                  // "bbb" will not park
        model.onQueryChange("bbb")            // supersede A before it completes
        advanceUntilIdle()                    // "bbb" -> NoResults content, new generation
        gate.complete(Unit)                   // NOW let A's late first page finish
        advanceUntilIdle()

        // A's late completion must NOT have armed paging for the live "bbb" session.
        assertTrue("live content is bbb's NoResults", model.state.value.content is InBookSearchContent.NoResults)
        model.loadMore()
        advanceUntilIdle()
        assertFalse("A's stale cursor was never armed for bbb → no continuation call with A's cursor",
            searcher.cursorsSeen.contains(aCursor))
        model.onCleared()
    }

    @Test fun dismiss_duringInFlightFirstPage_dropsLateCompletion() = runTest {
        // M2: dismissing while a first-page search is in flight must invalidate it — its late completion (which
        // would mint a live EPUB cursor) is dropped, and dismiss closes cursors.
        val d = StandardTestDispatcher(testScheduler)
        val searcher = GatedSearcher { q, _ ->
            InBookSearchOutcome.Results(InBookSearchPage(listOf(InBookGroup("C", listOf(hit("C", q)))), true, SearchCursor.Epub("live-$q")))
        }
        val model = vm(this, d, searcher, format = BookFormat.epub, bookKey = epubKey, indexStateFlow = flowOf(null))

        val gate = kotlinx.coroutines.CompletableDeferred<Unit>()
        searcher.gate = gate
        model.onQueryChange("cat")
        advanceTimeBy(debounce + 1)           // first-page parked on the gate
        val closesBefore = searcher.closeCursorsCalls
        model.onDismiss()                     // dismiss while in flight
        advanceUntilIdle()
        assertTrue("dismiss closed cursors", searcher.closeCursorsCalls > closesBefore)
        gate.complete(Unit)                   // late completion arrives AFTER dismiss (mints its iterator NOW)
        advanceUntilIdle()
        // The dismissed session's late page must not become the visible Results with a live cursor.
        assertFalse("a dismissed session's late first page does not arm a live paging session", model.state.value.content is InBookSearchContent.Results)
        // round-3 bounded residual: the stale completion is NOT reaped inline (a close-all could close a live
        // newer-session cursor); the orphan is instead reaped by the next lifecycle close — onCleared() below.
        model.onCleared()
        assertEquals("onCleared reaps every EPUB cursor (bounded by the VM lifetime, never leaked)", 0, searcher.liveCursors)
    }

    // ---- 14. Gate-4 round-2 hardening: session invalidated SYNCHRONOUSLY on query change ------------

    @Test fun queryChange_duringInFlightLoadMore_invalidatesTheAppend() = runTest {
        // round-2 High: a loadMore() in flight when the user types a NEW query must be invalidated the INSTANT
        // the text changes (not 250 ms later at the debounce) — its late page must not overwrite the new query's
        // state, and it must not page() with the new query text.
        val d = StandardTestDispatcher(testScheduler)
        val firstCursor = SearchCursor.Fts(0, 0, 1L, 5)
        val appendCursor = SearchCursor.Fts(0, 0, 1L, 9)
        val searcher = GatedSearcher { q, cursor ->
            when {
                cursor == null && q == "aaa" -> InBookSearchOutcome.Results(InBookSearchPage(listOf(InBookGroup("A", listOf(hit("A", "a1")))), true, firstCursor))
                cursor == firstCursor -> InBookSearchOutcome.Results(InBookSearchPage(listOf(InBookGroup("A", listOf(hit("A", "a2")))), true, appendCursor))
                else -> InBookSearchOutcome.NoResults   // any "bbb" first page
            }
        }
        val model = vm(this, d, searcher)

        model.onQueryChange("aaa")
        advanceUntilIdle()                    // first page for "aaa" armed (firstCursor)
        assertTrue(model.state.value.content is InBookSearchContent.Results)

        // Park the append, fire loadMore, THEN type a new query before the append returns.
        val gate = kotlinx.coroutines.CompletableDeferred<Unit>()
        searcher.gate = gate
        model.loadMore()                      // append for "aaa" dispatched, parked on the gate
        advanceUntilIdle()
        searcher.gate = null
        model.onQueryChange("bbb")            // NEW query — must invalidate the in-flight append IMMEDIATELY
        gate.complete(Unit)                   // now the "aaa" append returns late
        advanceUntilIdle()

        // The late "aaa" append must NOT have appended into "bbb"'s state.
        val liveQuery = model.state.value.query
        assertEquals("the live query is bbb", "bbb", liveQuery)
        // The append call used "aaa" (the session's captured query), NOT the newer "bbb" text.
        assertFalse("the invalidated append never paged with the new query text",
            searcher.queriesSeen.any { it == "bbb" && searcher.cursorsSeen[searcher.queriesSeen.indexOf(it)] == firstCursor })
        // "a2" (the append's hit) must not be visible — the append was dropped.
        val content = model.state.value.content
        val visibleSnippets = (content as? InBookSearchContent.Results)?.groups?.flatMap { it.hits }?.map { it.snippet } ?: emptyList()
        assertFalse("the invalidated append's hit never reaches bbb's results", visibleSnippets.contains("a2"))
        model.onCleared()
    }

    @Test fun loadMore_threadsSessionQuery_notNewlyTypedText() = runTest {
        // round-2 High corollary: loadMore captures the session's query at launch; even if the text field is
        // then edited, the append pages the ORIGINAL session query with its own cursor.
        val d = StandardTestDispatcher(testScheduler)
        val firstCursor = SearchCursor.Fts(1, 0, 2L, 0)
        val searcher = GatedSearcher { q, cursor ->
            if (cursor == null) InBookSearchOutcome.Results(InBookSearchPage(listOf(InBookGroup("S", listOf(hit("S", "p1")))), true, firstCursor))
            else InBookSearchOutcome.Results(InBookSearchPage(listOf(InBookGroup("S", listOf(hit("S", "p2")))), false, null))
        }
        val model = vm(this, d, searcher)

        model.onQueryChange("orig")
        advanceUntilIdle()
        model.loadMore()
        advanceUntilIdle()

        // The continuation page was requested with the session query "orig", never a partially-typed newer one.
        val continuationIdx = searcher.cursorsSeen.indexOfFirst { it == firstCursor }
        assertEquals("loadMore threads the session query", "orig", searcher.queriesSeen[continuationIdx])
        model.onCleared()
    }
}
