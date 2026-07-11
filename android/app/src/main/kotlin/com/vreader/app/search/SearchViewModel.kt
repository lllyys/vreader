// Purpose: Drives the library search screen (feature #128 WI-6). Owns the debounced query, the live
// metadata filter (iOS LibraryContainerModel.matchesQuery parity — case/diacritic/width-insensitive
// title-or-author substring, a nil author never matching), the in-text hits (WI-6 SearchRepository,
// which grows as indexing completes), and the completeness gate for the definitive no-results copy.
// The composable (WI-7) is a pure function of SearchUiState.
//
// Pipeline (plan §WI-6): query → trim → 300 ms debounce → combine(
//   (a) metadata filter over observeLibrary(),
//   (b) SearchRepository.textHits (observable, grows live),
//   (c) indexComplete Flow (SearchDao settled-completeness),
// ) → ordered result rows + summary counts. Ordering: title-match > author-match > text-only; ties by
// lastOpenedAt desc then title. Empty query → recents + collections (the designed empty state).
package com.vreader.app.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vreader.app.data.Book
import com.vreader.app.data.Collection
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
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
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch

/** One search result row: the book + which metadata field matched + the (optional) in-text hit. */
data class SearchResultRow(
    val book: Book,
    val titleMatch: Boolean,
    val authorMatch: Boolean,
    val textHit: TextHit?,
)

/**
 * The search screen state. `results` is the ordered rows; `searched` is true once a non-blank query
 * has settled through the debounce (so the empty state shows recents/collections, not "no results");
 * `indexComplete` gates the definitive no-results copy (true only when the whole indexable corpus is
 * settled — plan §"honest empty state").
 */
data class SearchUiState(
    val query: String = "",
    val recents: List<String> = emptyList(),
    val collections: List<Collection> = emptyList(),
    val results: List<SearchResultRow> = emptyList(),
    val searched: Boolean = false,
    val indexComplete: Boolean = false,
) {
    /** N books matched. */
    val bookCount: Int get() = results.size

    /** M of the N have an in-text hit ("N books · M in-text match"). */
    val inTextMatchCount: Int get() = results.count { it.textHit != null }
}

class SearchViewModel(
    private val libraryFlow: Flow<List<Book>>,
    /** In-text hits for a query (production = SearchRepository::textHits) — a seam so tests inject a
     *  deterministic Flow instead of the Room-backed one. */
    private val textHitsFor: (String) -> Flow<List<TextHit>>,
    private val recentsFlow: Flow<List<String>>,
    private val collectionsFlow: Flow<List<Collection>>,
    private val indexCompleteFlow: Flow<Boolean>,
    /** Records a query into recents (production = RecentSearchesStore::record). */
    private val recordQuery: suspend (String) -> Unit,
    private val defaultDispatcher: CoroutineDispatcher = Dispatchers.Default,
    private val debounceMillis: Long = DEFAULT_DEBOUNCE_MILLIS,
) : ViewModel() {

    private val _query = MutableStateFlow("")

    private val _state = MutableStateFlow(SearchUiState())
    val state: StateFlow<SearchUiState> = _state.asStateFlow()

    /** A settled result batch, tagged with the exact (trimmed) query it was computed for, so a stale
     *  emission arriving during the NEXT query's debounce window can be discarded instead of overwriting
     *  the current state with mislabeled rows (Gate-4 High). */
    private data class SearchResults(val query: String, val searched: Boolean, val rows: List<SearchResultRow>)

    @OptIn(ExperimentalCoroutinesApi::class, FlowPreview::class)
    private val resultsFlow: Flow<SearchResults> =
        _query
            .map { it.trim() }
            .debounce(debounceMillis)           // 300 ms — collapse as-you-type keystrokes
            .distinctUntilChanged()
            .flatMapLatest { q ->               // stale-query cancellation: a new query drops the old
                if (q.isEmpty()) {
                    flowOf(SearchResults(q, searched = false, rows = emptyList()))
                } else {
                    // onStart(emptyList) so metadata results render IMMEDIATELY — in-text hits are always
                    // live but the Room-backed textHits Flow's first emission may lag; the combine must
                    // not stall metadata search waiting for it.
                    combine(
                        libraryFlow,
                        textHitsFor(q).onStart { emit(emptyList()) },
                    ) { books, hits ->
                        SearchResults(q, searched = true, rows = buildRows(q, books, hits))
                    }
                }
            }

    init {
        // The screen state = the empty-state feeds (recents + collections + completeness), always live,
        // combined with the debounced result feed. distinctUntilChanged on the sub-Flows keeps churn low.
        combine(
            resultsFlow,
            recentsFlow,
            collectionsFlow,
            indexCompleteFlow.distinctUntilChanged(),
        ) { results, recents, collections, complete ->
            State(results, recents, collections, complete)
        }
            .onEach { s ->
                // Discard a STALE result batch — one whose tagged query no longer equals the live raw
                // query (it arrived during the next query's debounce window). Keep the reset empty state
                // set by onQueryChange rather than flashing mislabeled rows / a wrong definitive copy.
                val liveQuery = _query.value.trim()
                if (s.results.query != liveQuery) {
                    // Still keep the always-live empty-state feeds fresh.
                    _state.value = _state.value.copy(
                        recents = s.recents, collections = s.collections, indexComplete = s.complete,
                    )
                    return@onEach
                }
                _state.value = SearchUiState(
                    query = _query.value,          // the raw typed text — matches s.results.query here
                    recents = s.recents,
                    collections = s.collections,
                    results = s.results.rows,
                    searched = s.results.searched,
                    indexComplete = s.complete,
                )
            }
            .launchIn(viewModelScope)
    }

    /** Internal combine tuple (avoids a 4-arg destructuring lambda). */
    private data class State(
        val results: SearchResults,
        val recents: List<String>,
        val collections: List<Collection>,
        val complete: Boolean,
    )

    /** Update the query text (drives the debounced search). Immediately reflects the raw text AND
     *  resets `searched`/`results` so no stale rows or a stale definitive-no-results copy linger while
     *  the debounce settles (Gate-4 High — the emitted state stays self-consistent for the new query). */
    fun onQueryChange(text: String) {
        _query.value = text
        _state.value = _state.value.copy(query = text, searched = false, results = emptyList())
    }

    /** Records the CURRENT (trimmed) query into recents — call on IME-search / result-open. No-op for
     *  a blank query (RecentSearchesStore also guards, but this avoids a needless write). */
    fun recordCurrentQuery() {
        val q = _query.value.trim()
        if (q.isEmpty()) return
        viewModelScope.launch(defaultDispatcher) { recordQuery(q) }
    }

    // ── result assembly ────────────────────────────────────────────────

    /**
     * Builds the ordered result rows for [query] over the live [books] + in-text [hits]. A book is a
     * result iff its title or author matches (iOS parity), OR it has an in-text hit. Ordering:
     * title-match > author-match > text-only; ties by lastOpenedAt desc then title (case-insensitive).
     */
    private fun buildRows(query: String, books: List<Book>, hits: List<TextHit>): List<SearchResultRow> {
        val normQuery = SearchTextNormalizer.normalize(query)
        if (normQuery.isEmpty()) return emptyList()
        val hitByKey = hits.associateBy { it.bookKey }

        val rows = books.mapNotNull { book ->
            val titleMatch = matchesNormalized(book.title, normQuery)
            // A nil author NEVER contributes a match (iOS LibraryContainerModel.matchesQuery).
            val authorMatch = book.author?.let { matchesNormalized(it, normQuery) } ?: false
            val textHit = hitByKey[book.fingerprintKey]
            if (!titleMatch && !authorMatch && textHit == null) return@mapNotNull null
            SearchResultRow(book, titleMatch, authorMatch, textHit)
        }

        return rows.sortedWith(
            compareBy<SearchResultRow> { rankOf(it) }
                .thenByDescending { it.book.lastOpenedAt ?: Long.MIN_VALUE }
                .thenBy { it.book.title.lowercase() },
        )
    }

    /** Rank: 0 = title match, 1 = author-only match, 2 = text-only match (title > author > text). */
    private fun rankOf(row: SearchResultRow): Int = when {
        row.titleMatch -> 0
        row.authorMatch -> 1
        else -> 2
    }

    /** Case/diacritic/width-insensitive substring: both sides run through the same normalizer (so a
     *  ß-query matches an `ss`-title, full-width matches half-width, etc.) then a substring test. */
    private fun matchesNormalized(field: String, normQuery: String): Boolean =
        SearchTextNormalizer.normalize(field).contains(normQuery)

    companion object {
        const val DEFAULT_DEBOUNCE_MILLIS: Long = 300L
    }
}
