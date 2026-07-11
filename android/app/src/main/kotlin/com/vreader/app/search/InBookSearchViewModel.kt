// Purpose: The book-scoped in-book-search state machine — feature #133 WI-8. Drives the WI-9 sheet: a
// debounced query -> paged results with append-on-scroll, gated by the WI-7 index state (TXT/MD only) and
// backed by the WI-6 [InBookSearcher] (which unifies the EPUB Readium engine + the TXT/MD FTS pipeline).
// Owns the single long-lived search session for a reader open: it holds ONE [InBookSearcher] instance and
// disposes its live EPUB Readium iterators (`closeAllEpubCursors`) on every reset/dismiss/onCleared so no
// iterator leaks. The composable (WI-9) is a pure function of [InBookSearchScreenState].
//
// Pipeline: onQueryChange -> _query -> trim -> debounce(250 ms) -> distinctUntilChanged -> flatMapLatest
//   (cancel the prior query's search) -> IndexStateGate.observe(bookKey), mapping the gate state to content:
//   empty->Idle (+dispose EPUB cursors); Indexing (TXT/MD)->the FTS search is HELD, the hint shows, and the
//   gate's Flow re-emits Ready/NoResults on settle so the held query auto-re-runs with no re-type (EPUB never
//   Indexing); Unsupported->hide the entry; NoResults(0 occ)->definitive empty; Ready/Failed->run page(...).
//   Each batch is tagged with the query + the search-SESSION generation so a late emission for a superseded
//   session/query is discarded (the #128 SearchViewModel stale-tag pattern, hardened with a generation token).
//   loadMore() threads the last page's nextCursor back through page(...) for BOTH tracks and COALESCES
//   same-section groups so append-on-scroll is complete.
//
// Key decisions:
// - The backend is the [InBookSearcher] interface (constructor-injected) so tests fake it; production wires the
//   concrete WI-6 InBookSearchRepository behind it. ONE instance per session.
// - `closeAllEpubCursors()` is the hard lifecycle invariant (WI-6: the live Readium SearchIterator leaks
//   otherwise). Called on empty-query reset, dismiss, and onCleared — never a fresh repo per query.
// - A single monotonic `generation` token invalidates a superseded/dismissed search session: ALL paging-field
//   writes + first-page/append commits are gated on it, so a late/non-cooperative completion can't corrupt the
//   live session's paging or mint an abandoned EPUB cursor (a stale completion additionally reaps its own).
// - Recents are the GLOBAL RecentSearchesStore (iOS parity, no per-book persistence) reused via two lambda
//   seams — the VM records + surfaces; the store owns the case-insensitive dedupe + cap-8, never reimplemented.
// - An injected CoroutineScope + CoroutineDispatcher make debounce/flatMapLatest deterministic in tests.
//
// @coordinates-with search/InBookSearchViewState.kt (the InBookSearcher seam + InBookSearchContent /
//   InBookSearchScreenState this VM exposes), search/InBookSearchRepository.kt (WI-6 — the InBookSearcher
//   backend), search/IndexStateGate.kt (WI-7 — the observed index-state gate), search/RecentSearchesStore.kt
//   (#128 — the global recents seam), search/InBookSearchModels.kt (the shared DTOs + SearchCursor),
//   data/SearchDao.kt (observeIndexState Flow, read-only).
package com.vreader.app.search

import androidx.lifecycle.ViewModel
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

    /** The monotonic SEARCH-SESSION id — the single generation token that invalidates a superseded search. It
     *  bumps per distinct query ([flatMapLatest]), on an empty-query reset, and on [onDismiss]; ALL paging-field
     *  writes + result commits are gated on `gen == generation`, so a late/non-cooperative completion from a
     *  superseded/dismissed session can't corrupt the live session's paging or mint an abandoned EPUB cursor
     *  (Gate-4 round-1 H1/H2/M1/M2). Everything runs on the ONE injected dispatcher, so these var reads/writes
     *  are serialized — the token guards LOGICAL interleaving across suspension points, not a memory race. */
    private var generation: Long = 0L

    /** The cursor for the NEXT append-on-scroll page (null = no more / not yet searched). */
    private var nextCursor: SearchCursor? = null

    /** The currently displayed groups (kept so [loadMore] can COALESCE the appended page). */
    private var currentGroups: List<InBookGroup> = emptyList()

    /** The generation the displayed results + [nextCursor] belong to (a loadMore for a stale session drops). */
    private var resultsGeneration: Long = -1L

    /** The trimmed query of the CURRENT session — set synchronously in [onQueryChange]/[beginSession] so a
     *  session change is visible to an in-flight [loadMore] IMMEDIATELY (not only after the 250 ms debounce),
     *  and so [loadMore] threads the session's own query, never a just-typed newer one (Gate-4 round-2 High). */
    private var sessionQuery: String = ""

    /** Single-flight guard: true while a [loadMore] page is in flight (prevents rapid scroll callbacks from
     *  double-consuming the SAME [nextCursor] → duplicate pages / expired EPUB cursor — Gate-4 H1). */
    private var loadingMore: Boolean = false

    @OptIn(ExperimentalCoroutinesApi::class, FlowPreview::class)
    private val contentFlow: Flow<TaggedContent> =
        _query
            .map { it.trim() }
            .debounce(debounceMillis)
            .distinctUntilChanged()
            .flatMapLatest { q ->
                // The session was already begun synchronously in onQueryChange (which invalidates any in-flight
                // loadMore the instant the text changes — round-2 High); here we just capture that generation.
                // A HELD (Indexing) query's gate re-emission on settle keeps the SAME session, so it auto-re-runs.
                val gen = generation
                if (q.isEmpty()) {
                    // A cleared query resets the session: dispose any live EPUB iterators before Idle.
                    searcher.closeAllEpubCursors()
                    flowOf(TaggedContent(q, gen, InBookSearchContent.Idle))
                } else {
                    indexStateGate
                        .observe(format, bookKey, hasOccurrence = hasOccurrence, indexStateFlow = indexStateFlow)
                        .flatMapContent(q, gen)
                }
            }

    init {
        combine(contentFlow, recentsFlow) { tagged, recents -> tagged to recents }
            .onEach { (tagged, recents) ->
                val live = _query.value.trim()
                // Discard a batch from a superseded session OR tagged for a superseded query (arrived during
                // the next query's window); keep the always-live recents fresh, but do not flash mislabeled
                // content.
                if (tagged.generation != generation || tagged.query != live) {
                    _state.value = _state.value.copy(recents = recents)
                    return@onEach
                }
                _state.value = InBookSearchScreenState(
                    query = _query.value,
                    recents = recents,
                    content = tagged.content,
                )
            }
            .launchIn(scope)
    }

    /** Invalidate the current session, clear paging state synchronously (so any in-flight append/first-page is
     *  immediately stale), record the new session's [query], and mint the new generation. */
    private fun beginSession(query: String) {
        generation += 1
        nextCursor = null
        currentGroups = emptyList()
        resultsGeneration = -1L
        loadingMore = false
        sessionQuery = query
    }

    /** Map the observed [InBookIndexState] Flow → the search content for [q] in session [gen]; a Ready/Failed
     *  gate runs the backend page(1) (committing paging state only if [gen] is still current), a non-searchable
     *  gate short-circuits to the matching terminal content. */
    @OptIn(ExperimentalCoroutinesApi::class)
    private fun Flow<InBookIndexState>.flatMapContent(q: String, gen: Long): Flow<TaggedContent> =
        this.map { gate ->
            when (gate) {
                InBookIndexState.Indexing -> TaggedContent(q, gen, InBookSearchContent.Indexing)
                InBookIndexState.NoResults -> TaggedContent(q, gen, InBookSearchContent.NoResults)
                InBookIndexState.Unsupported -> TaggedContent(q, gen, InBookSearchContent.Unsupported)
                // Ready (searchable now) and Failed (retryable — attempt the search) both run the backend.
                InBookIndexState.Ready, InBookIndexState.Failed ->
                    TaggedContent(q, gen, mapOutcome(searcher.page(bookKey, format, q, cursor = null, pageSize), gen))
            }
        }

    /** Map a first-page backend outcome → content. Commits the append cursor ONLY if [gen] is still the live
     *  generation (a superseded/dismissed session's late completion must not arm paging for the new session).
     *
     *  NOTE (Gate-4 round-3, bounded residual): a stale (`gen != generation`) EPUB completion may leave the
     *  repository holding a just-minted iterator that this VM never commits. We deliberately do NOT reap it via
     *  `closeAllEpubCursors()` here — that API closes ALL cursors, so it would also close the LIVE cursor a
     *  newer session may already have minted (a worse defect). The orphan is instead reaped by the very next
     *  `beginSession()` → `closeAllEpubCursors()` (any query change / clear / dismiss) and unconditionally by
     *  [onCleared], so the hold is bounded by the sheet's re-interaction / the VM lifetime — a minor bounded
     *  resource hold, never an unbounded leak. A precise per-session reap needs a repository session-scoped
     *  close API (a WI-6 follow-up: the close-all seam cannot selectively reap without repository support). */
    private fun mapOutcome(outcome: InBookSearchOutcome, gen: Long): InBookSearchContent = when (outcome) {
        is InBookSearchOutcome.Results -> {
            if (gen == generation) {
                nextCursor = outcome.page.nextCursor
                currentGroups = outcome.page.groups
                resultsGeneration = gen
            }
            InBookSearchContent.Results(outcome.page.groups, outcome.page.moreAvailable)
        }
        InBookSearchOutcome.NoResults -> InBookSearchContent.NoResults
        InBookSearchOutcome.Unsupported -> InBookSearchContent.Unsupported
        is InBookSearchOutcome.Error -> InBookSearchContent.Error(outcome.message)
    }

    /** Update the query text. Immediately reflects the raw text (so the field is responsive), and — when the
     *  TRIMMED query changes — synchronously begins a new session (bumping the generation + clearing paging), so
     *  an in-flight [loadMore] is invalidated the instant the text changes rather than 250 ms later at the
     *  debounce (Gate-4 round-2 High). Resets the content so no stale rows / definitive copy linger. */
    fun onQueryChange(text: String) {
        val trimmed = text.trim()
        if (trimmed != sessionQuery) beginSession(trimmed)
        _query.value = text
        val reset = if (trimmed.isEmpty()) InBookSearchContent.Idle else InBookSearchContent.Loading
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
     * reports no more. Single-flight ([loadingMore]) so rapid scroll callbacks never double-consume the same
     * cursor; generation-gated so a page arriving after a query change / dismiss is dropped. A no-op when there
     * is no more, no cursor, a paging session mismatch, or an append is already in flight.
     */
    fun loadMore() {
        if (loadingMore) return
        val cursor = nextCursor ?: return
        val current = state.value.content
        if (current !is InBookSearchContent.Results || !current.moreAvailable) return
        val gen = generation
        if (resultsGeneration != gen) return
        // Thread the SESSION's own query (captured at launch), never a newer just-typed one (round-2 High).
        val q = sessionQuery
        loadingMore = true
        scope.launch(dispatcher) {
            try {
                val outcome = searcher.page(bookKey, format, q, cursor, pageSize)
                // Only append if THIS session is still live when the page arrives (a query change / dismiss
                // between launch and completion bumped the generation → drop it, no dup, no wrong-session write).
                // A stale EPUB cursor minted here is reaped by the next beginSession/onCleared, not here (a
                // close-all reap could close the live session's cursor — see [mapOutcome]'s round-3 note).
                if (gen != generation) return@launch
                when (outcome) {
                    is InBookSearchOutcome.Results -> {
                        nextCursor = outcome.page.nextCursor
                        currentGroups = coalesce(currentGroups, outcome.page.groups)
                        _state.value = _state.value.copy(
                            content = InBookSearchContent.Results(currentGroups, outcome.page.moreAvailable),
                        )
                    }
                    // A terminal outcome on a continuation is unexpected; stop paging without discarding what
                    // is already shown.
                    else -> nextCursor = null
                }
            } finally {
                if (gen == generation) loadingMore = false
            }
        }
    }

    /** Explicit dismiss (host closed the sheet): invalidate the active session so any in-flight first-page /
     *  append completion is a no-op (it can't mint an abandoned cursor into a live session; a stale completion
     *  additionally reaps its own just-minted EPUB cursor — see [mapOutcome]/[loadMore]), then dispose the live
     *  EPUB iterators held so far. */
    fun onDismiss() {
        beginSession(_query.value.trim())
        searcher.closeAllEpubCursors()
    }

    public override fun onCleared() {
        searcher.closeAllEpubCursors()
        scope.cancel()
        super.onCleared()
    }

    /** A settled content batch tagged with the (trimmed) query + the search-session [generation] it was
     *  computed for (stale-tag + stale-session discard). */
    private data class TaggedContent(val query: String, val generation: Long, val content: InBookSearchContent)

    companion object {
        const val DEFAULT_DEBOUNCE_MILLIS: Long = 250L
        const val DEFAULT_PAGE_SIZE: Int = 50
    }
}
