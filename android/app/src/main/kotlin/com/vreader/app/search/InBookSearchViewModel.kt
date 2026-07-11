// Purpose: The book-scoped in-book-search state machine — feature #133 WI-8. Drives the WI-9 sheet: a
// debounced query -> paged results with append-on-scroll, gated by the WI-7 index state (TXT/MD only) and
// backed by the WI-6 [InBookSearcher] (which unifies the EPUB Readium engine + the TXT/MD FTS pipeline).
// Owns the single long-lived search session for a reader open: it holds ONE [InBookSearcher] instance and
// disposes its live EPUB Readium iterators (`closeAllEpubCursors`) on every reset/dismiss/onCleared so no
// iterator leaks. The composable (WI-9) is a pure function of [InBookSearchScreenState].
//
// Pipeline: onQueryChange -> _query -> trim -> debounce(250 ms) -> distinctUntilChanged ->
//   flatMapLatest (cancel the prior query's search) -> combine with IndexStateGate.observe(bookKey):
//     · empty query            -> Idle (and dispose EPUB cursors — a fresh search session for the next query)
//     · gate=Indexing (TXT/MD) -> Indexing hint, the FTS search is HELD (not run) until the index settles;
//                                 the gate's Flow re-emits Ready/NoResults on settle so the held query
//                                 auto-re-runs with no manual re-type (EPUB never enters Indexing).
//     · gate=Unsupported       -> Unsupported (host hides the Search entry)
//     · gate=NoResults (0 occ) -> NoResults (definitive, never a false empty while indexing)
//     · gate=Ready / Failed    -> run the backend page(...) -> map the outcome to content
//   Each settled batch is tagged with the exact live query so a late emission for a superseded query is
//   discarded (the #128 SearchViewModel stale-tag pattern). loadMore() threads the last page's nextCursor
//   back through page(...) for BOTH tracks and COALESCES same-section groups so append-on-scroll is complete.
//
// Key decisions:
// - The backend is consumed through the [InBookSearcher] interface (constructor-injected) so tests fake it;
//   production wires the concrete WI-6 InBookSearchRepository behind it. ONE instance per session.
// - `closeAllEpubCursors()` is the hard lifecycle invariant (WI-6: the live Readium SearchIterator leaks
//   otherwise). Called on empty-query reset, explicit dismiss, and onCleared — never a fresh repo per query.
// - Recents are the GLOBAL RecentSearchesStore (design shows no per-book persistence; iOS parity) reused
//   through two lambda seams (a Flow + a suspend record) — the VM records + surfaces; the store enforces the
//   case-insensitive dedupe + cap-8, so the VM never reimplements the cap.
// - An injected CoroutineScope + CoroutineDispatcher make debounce/flatMapLatest deterministic under a
//   StandardTestDispatcher; production defaults to viewModelScope + the passed dispatcher.
//
// @coordinates-with search/InBookSearchViewState.kt (the InBookSearcher seam + InBookSearchContent /
//   InBookSearchScreenState this VM exposes), search/InBookSearchRepository.kt (WI-6 — the InBookSearcher
//   backend), search/IndexStateGate.kt (WI-7 — the observed index-state gate), search/RecentSearchesStore.kt
//   (#128 — the global recents seam), search/InBookSearchModels.kt (the shared DTOs + SearchCursor),
//   data/SearchDao.kt (observeIndexState Flow, read-only).
package com.vreader.app.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vreader.app.data.SearchIndexStateEntity
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import vreader.contracts.BookFormat

class InBookSearchViewModel(
    private val bookKey: String,
    private val format: BookFormat,
    private val searcher: InBookSearcher,
    private val indexStateGate: IndexStateGate,
    /** The DAO's `observeIndexState(bookKey)` Flow (production); a MutableStateFlow in tests. */
    private val indexStateFlow: Flow<SearchIndexStateEntity?>,
    /** Whether the CURRENT index has any match for the live query (production = `matchingChunkCount > 0`). */
    private val hasOccurrence: suspend () -> Boolean,
    private val recentsFlow: Flow<List<String>>,
    /** Records a committed query into the GLOBAL recents store (production = RecentSearchesStore::record). */
    private val recordQuery: suspend (String) -> Unit,
    private val dispatcher: CoroutineDispatcher = Dispatchers.Default,
    /** The scope every flow/collector runs in — [viewModelScope] in production, a test scope in tests. */
    private val coroutineScope: CoroutineScope,
    private val debounceMillis: Long = DEFAULT_DEBOUNCE_MILLIS,
    private val pageSize: Int = DEFAULT_PAGE_SIZE,
) : ViewModel() {

    /** A cancellable child of the injected scope: every collector/launch runs here so [onCleared] can stop
     *  them all deterministically (the injected scope — viewModelScope or a test scope — is NOT cancelled by
     *  onCleared, so a plain launchIn on it would leak the long-lived collector). */
    private val scope: CoroutineScope =
        CoroutineScope(coroutineScope.coroutineContext + SupervisorJob(coroutineScope.coroutineContext[kotlinx.coroutines.Job]))

    private val _query = MutableStateFlow("")
    private val _state = MutableStateFlow(InBookSearchScreenState())
    val state: StateFlow<InBookSearchScreenState> = _state.asStateFlow()

    /** The cursor for the NEXT append-on-scroll page (null = no more / not yet searched). Only meaningful
     *  when [content] is Results with moreAvailable — guarded by [loadMore]. */
    private var nextCursor: SearchCursor? = null

    /** The currently displayed groups (kept so [loadMore] can COALESCE the appended page). */
    private var currentGroups: List<InBookGroup> = emptyList()

    /** The query the displayed results belong to — a loadMore for a stale query is dropped. */
    private var resultsQuery: String = ""

    @OptIn(ExperimentalCoroutinesApi::class, FlowPreview::class)
    private val contentFlow: Flow<TaggedContent> =
        _query
            .map { it.trim() }
            .debounce(debounceMillis)
            .distinctUntilChanged()
            .flatMapLatest { q ->
                if (q.isEmpty()) {
                    // A cleared query resets the session: dispose any live EPUB iterators before Idle.
                    searcher.closeAllEpubCursors()
                    flowOf(TaggedContent(q, InBookSearchContent.Idle))
                } else {
                    // The gate re-emits on index settle so a HELD (Indexing) query auto-re-runs; each emission
                    // maps the gate state → either a held/terminal content or a fresh backend search.
                    indexStateGate
                        .observe(format, bookKey, hasOccurrence = hasOccurrence, indexStateFlow = indexStateFlow)
                        .flatMapContent(q)
                }
            }

    init {
        combine(contentFlow, recentsFlow) { tagged, recents -> tagged to recents }
            .onEach { (tagged, recents) ->
                val live = _query.value.trim()
                // Discard a batch tagged for a superseded query (arrived during the next query's window);
                // keep the always-live recents fresh, but do not flash mislabeled content.
                if (tagged.query != live) {
                    _state.value = _state.value.copy(recents = recents)
                    return@onEach
                }
                if (tagged.content is InBookSearchContent.Results) {
                    currentGroups = tagged.content.groups
                    resultsQuery = tagged.query
                }
                _state.value = InBookSearchScreenState(
                    query = _query.value,
                    recents = recents,
                    content = tagged.content,
                )
            }
            .launchIn(scope)
    }

    /** Map the observed [InBookIndexState] Flow → the search content for [q]; a Ready/Failed gate runs the
     *  backend page(1), a non-searchable gate short-circuits to the matching terminal content. */
    @OptIn(ExperimentalCoroutinesApi::class)
    private fun Flow<InBookIndexState>.flatMapContent(q: String): Flow<TaggedContent> =
        this.map { gate ->
            when (gate) {
                InBookIndexState.Indexing -> TaggedContent(q, InBookSearchContent.Indexing)
                InBookIndexState.NoResults -> TaggedContent(q, InBookSearchContent.NoResults)
                InBookIndexState.Unsupported -> TaggedContent(q, InBookSearchContent.Unsupported)
                // Ready (searchable now) and Failed (retryable — attempt the search) both run the backend.
                InBookIndexState.Ready, InBookIndexState.Failed -> {
                    nextCursor = null
                    currentGroups = emptyList()
                    resultsQuery = q
                    TaggedContent(q, mapOutcome(searcher.page(bookKey, format, q, cursor = null, pageSize)))
                }
            }
        }

    /** Map a backend outcome → content, capturing the first-page cursor for append-on-scroll. */
    private fun mapOutcome(outcome: InBookSearchOutcome): InBookSearchContent = when (outcome) {
        is InBookSearchOutcome.Results -> {
            nextCursor = outcome.page.nextCursor
            InBookSearchContent.Results(outcome.page.groups, outcome.page.moreAvailable)
        }
        InBookSearchOutcome.NoResults -> { nextCursor = null; InBookSearchContent.NoResults }
        InBookSearchOutcome.Unsupported -> { nextCursor = null; InBookSearchContent.Unsupported }
        is InBookSearchOutcome.Error -> { nextCursor = null; InBookSearchContent.Error(outcome.message) }
    }

    /** Update the query text. Immediately reflects the raw text (so the field is responsive) and resets the
     *  content so no stale rows / definitive copy linger while the debounce settles. */
    fun onQueryChange(text: String) {
        _query.value = text
        val reset = if (text.trim().isEmpty()) InBookSearchContent.Idle else InBookSearchContent.Loading
        _state.value = _state.value.copy(query = text, content = reset)
    }

    /** Fill + run the query for a tapped recent (the field is filled; the debounced pipeline runs it). */
    fun onPickRecent(query: String) = onQueryChange(query)

    /** Record the CURRENT (trimmed) query into the GLOBAL recents store — call on IME-search / result-open.
     *  No-op for blank (the store also guards; this avoids a needless write). */
    fun commitSearch() {
        val q = _query.value.trim()
        if (q.isEmpty()) return
        scope.launch(dispatcher) { recordQuery(q) }
    }

    /**
     * Append the next page of results (append-on-scroll). Threads the last page's [nextCursor] back through
     * page(...) for BOTH tracks, COALESCES same-section groups so no gap/duplicate, and stops when the page
     * reports no more. A no-op when there is no more, no cursor, or the results are for a stale query.
     */
    fun loadMore() {
        val cursor = nextCursor ?: return
        val current = state.value.content
        if (current !is InBookSearchContent.Results || !current.moreAvailable) return
        val q = resultsQuery
        if (q.isEmpty() || q != _query.value.trim()) return
        scope.launch(dispatcher) {
            when (val outcome = searcher.page(bookKey, format, q, cursor, pageSize)) {
                is InBookSearchOutcome.Results -> {
                    // Only append if the query is still current when the page arrives (guard a race with a
                    // just-typed query whose flatMapLatest reset already ran).
                    if (resultsQuery != q || _query.value.trim() != q) return@launch
                    nextCursor = outcome.page.nextCursor
                    currentGroups = coalesce(currentGroups, outcome.page.groups)
                    _state.value = _state.value.copy(
                        content = InBookSearchContent.Results(currentGroups, outcome.page.moreAvailable),
                    )
                }
                // A terminal outcome on a continuation is unexpected; stop paging without discarding what
                // is already shown.
                else -> { nextCursor = null }
            }
        }
    }

    /** Explicit dismiss (host closed the sheet): dispose the live EPUB iterators for this session. */
    fun onDismiss() {
        searcher.closeAllEpubCursors()
    }

    public override fun onCleared() {
        searcher.closeAllEpubCursors()
        scope.cancel()
        super.onCleared()
    }

    /** A settled content batch tagged with the (trimmed) query it was computed for (stale-tag discard). */
    private data class TaggedContent(val query: String, val content: InBookSearchContent)

    companion object {
        const val DEFAULT_DEBOUNCE_MILLIS: Long = 250L
        const val DEFAULT_PAGE_SIZE: Int = 50

        /**
         * Merge an appended page's [next] groups into the [existing] ones: a group whose title matches the
         * LAST existing group coalesces (its hits append), any other new group is appended as-is. Because a
         * page always continues in reading order, only the boundary group can straddle a page split, so
         * matching the last existing group is sufficient — no gap, no duplicate.
         */
        internal fun coalesce(existing: List<InBookGroup>, next: List<InBookGroup>): List<InBookGroup> {
            if (next.isEmpty()) return existing
            if (existing.isEmpty()) return next
            val merged = existing.toMutableList()
            val first = next.first()
            val last = merged.last()
            if (last.title == first.title) {
                merged[merged.lastIndex] = last.copy(hits = last.hits + first.hits)
                merged.addAll(next.drop(1))
            } else {
                merged.addAll(next)
            }
            return merged
        }
    }
}
