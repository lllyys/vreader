// Purpose: feature #120 WI-3 (#110 Phase 3) — drives the OPDS browse screen: fetches a feed and
// splits it into navigation rows + acquisition entries, tracks a per-entry download state, runs
// download→import via the acquisition seam (→ in-library), follows pagination, and maps errors to
// the design's offline/auth/notfound views. Depends on functional seams (fetch / import / library
// flow), not the final OpdsClient — so it's unit-testable without Room or the network.
package com.vreader.app.opds.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.vreader.app.data.Book
import com.vreader.app.opds.OpdsEntry
import com.vreader.app.opds.OpdsError
import com.vreader.app.opds.OpdsFeed
import com.vreader.app.opds.OpdsLink
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Download + import an entry's best acquisition (production = OpdsAcquisitionService::importEntry). */
fun interface OpdsEntryImporter {
    suspend fun importEntry(entry: OpdsEntry, baseUrl: String?): Book
}

/** Fetch + parse a feed (production = OpdsClient::fetchFeed). */
fun interface OpdsFeedFetcher {
    suspend fun fetchFeed(url: String): OpdsFeed
}

class OpdsBrowseViewModel(
    private val rootTitle: String,
    private val rootUrl: String,
    private val fetcher: OpdsFeedFetcher,
    private val importer: OpdsEntryImporter,
    libraryFlow: Flow<List<Book>>,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {

    private val _state = MutableStateFlow(OpdsBrowseState(title = rootTitle))
    val state: StateFlow<OpdsBrowseState> = _state.asStateFlow()

    /** An acquisition entry plus the baseUrl of the PAGE it came from — so a row's hrefs resolve
     *  against its own page's base even after pagination appends pages with a different base. */
    private data class FeedEntry(val entry: OpdsEntry, val base: String?)

    private var feedEntries: List<FeedEntry> = emptyList()
    private val seenKeys = mutableSetOf<String>()   // cross-page dedup
    private var nextPageUrl: String? = null
    private var feedUrl: String = rootUrl           // the primary feed (NOT the next-page url)
    private var librarySourceUris: Set<String> = emptySet()
    private var feedLoaded = false
    private val downloading = mutableSetOf<String>()  // keys mid-download
    private val failed = mutableMapOf<String, String>()  // key → message

    init {
        viewModelScope.launch {
            libraryFlow.collect { books ->
                librarySourceUris = books.mapNotNull { it.sourceUri }.filter { it.startsWith("opds://") }.toSet()
                // Only re-render once a feed exists — else an early library emission would flip the
                // initial loading phase to empty before the fetch returns.
                if (feedLoaded) rebuildRows()
            }
        }
        open()
    }

    /** Load the root (or re-load after an error → Retry). Always the PRIMARY feed, never page 2. */
    fun open() = load(feedUrl, append = false)

    fun retry() = open()

    fun loadMore() {
        val next = nextPageUrl ?: return
        if (_state.value.loadingMore) return
        load(next, append = true)
    }

    private fun load(url: String, append: Boolean) {
        if (append) _state.value = _state.value.copy(loadingMore = true)
        else _state.value = _state.value.copy(phase = OpdsBrowsePhase.loading, errorKind = null)
        viewModelScope.launch {
            val result = withContext(ioDispatcher) { runCatching { fetcher.fetchFeed(url) } }
            result.fold(
                onSuccess = { feed -> onFeed(feed, append); if (!append) feedUrl = url },  // keep the primary feed url
                onFailure = { e -> onError(e, append) },
            )
        }
    }

    private fun onFeed(feed: OpdsFeed, append: Boolean) {
        feedLoaded = true
        nextPageUrl = feed.nextPageUrl
        if (!append) { seenKeys.clear(); failed.clear() }
        // Only AUTO-IMPORTABLE acquisition entries become downloadable book rows (a buy/borrow/sample
        // entry isn't actionable in v1). Navigation entries (no acquisition link) become nav rows.
        // Dedup across pages by the resolved key so pagination can't append a duplicate.
        val fresh = OpdsFeed.dedupe(feed.entries)
            .filter { importableLinks(it).isNotEmpty() }
            .map { FeedEntry(it, feed.baseUrl) }
            .filter { seenKeys.add(keyOf(it)) }
        feedEntries = if (append) feedEntries + fresh else fresh
        rebuildRows(navFrom = if (append) null else feed)  // append keeps page-1 nav rows
    }

    private fun onError(e: Throwable, append: Boolean) {
        if (append) { _state.value = _state.value.copy(loadingMore = false); return }  // keep what we have
        _state.value = _state.value.copy(phase = OpdsBrowsePhase.error, errorKind = errorKind(e), loadingMore = false)
    }

    /** Download + import the entry behind [key]. Flips remote → downloading → library (or failed).
     *  Single-flight per key (a second tap while downloading/in-library is a no-op). */
    fun download(key: String) {
        if (key in downloading) return
        val fe = feedEntries.firstOrNull { keyOf(it) == key } ?: return
        if (importableSourceUris(fe).any { it in librarySourceUris }) return  // already in library
        downloading += key; failed -= key
        rebuildRows()
        viewModelScope.launch {
            val result = withContext(ioDispatcher) { runCatching { importer.importEntry(fe.entry, fe.base) } }
            downloading -= key
            result.fold(
                // mark in-library immediately (the library flow corroborates via the imported sourceUri)
                onSuccess = { librarySourceUris = librarySourceUris + importableSourceUris(fe) },
                onFailure = { e -> failed[key] = downloadFailMessage(e) },
            )
            rebuildRows()
        }
    }

    // ── row building ────────────────────────────────────────────────

    private var lastNavRows: List<OpdsNavRow> = emptyList()
    private var lastSectionTitle: String? = null

    private fun rebuildRows(navFrom: OpdsFeed? = null) {
        if (navFrom != null) { lastNavRows = currentNavRows(navFrom); lastSectionTitle = navFrom.title.takeIf { feedEntries.isNotEmpty() } }
        val rows = feedEntries.mapIndexed { i, fe ->
            val key = keyOf(fe)
            OpdsEntryRow(
                key = key, index = i, title = fe.entry.title, author = fe.entry.author,
                format = displayFormat(fe),
                state = when {
                    key in downloading -> OpdsItemState.downloading
                    importableSourceUris(fe).any { it in librarySourceUris } -> OpdsItemState.library
                    failed.containsKey(key) -> OpdsItemState.failed
                    else -> OpdsItemState.remote
                },
                failMessage = failed[key],
            )
        }
        val phase = if (rows.isEmpty() && lastNavRows.isEmpty()) OpdsBrowsePhase.empty else OpdsBrowsePhase.feed
        _state.value = _state.value.copy(
            phase = phase, navRows = lastNavRows, sectionTitle = lastSectionTitle,
            entries = rows, canLoadMore = nextPageUrl != null, loadingMore = false, errorKind = null,
        )
    }

    /** Navigation rows = entries that are navigation targets (no acquisition), with a sub-feed URL. */
    private fun currentNavRows(feed: OpdsFeed): List<OpdsNavRow> =
        feed.entries.filter { it.acquisitionLinks.isEmpty() }
            .mapNotNull { e -> e.navigationUrl(feed.baseUrl)?.let { OpdsNavRow(e.title, it) } }

    /** A stable per-entry key, resolved against the entry's OWN page base. The id-less fallback uses
     *  the LEXICALLY-SMALLEST resolved importable href (not feed order) so a page that reorders an
     *  entry's links can't mint a different key for the same book. */
    private fun keyOf(fe: FeedEntry): String =
        fe.entry.id.ifBlank {
            importableLinks(fe.entry).mapNotNull { it.resolvedHref(fe.base) }.minOrNull() ?: "entry-${fe.entry.title}"
        }

    private fun importableLinks(e: OpdsEntry): List<OpdsLink> =
        e.acquisitionLinks.filter { it.isAutoImportable && it.formatExtension != null }

    private fun importableSourceUris(fe: FeedEntry): List<String> =
        importableLinks(fe.entry).mapNotNull { it.resolvedHref(fe.base) }.map { "opds://$it" }

    private fun displayFormat(fe: FeedEntry): String =
        (importableLinks(fe.entry).firstOrNull()?.formatExtension ?: "epub").uppercase()

    private fun errorKind(e: Throwable): OpdsBrowseError = when (e) {
        is OpdsError.Network -> OpdsBrowseError.offline
        is OpdsError.Http -> when (e.code) { 401, 403 -> OpdsBrowseError.auth; 404 -> OpdsBrowseError.notfound; else -> OpdsBrowseError.generic }
        is OpdsError.InsecureAuth -> OpdsBrowseError.auth
        is OpdsError.InvalidXml, is OpdsError.EmptyData, is OpdsError.InvalidUrl -> OpdsBrowseError.notfound
        else -> OpdsBrowseError.generic
    }

    private fun downloadFailMessage(e: Throwable): String = when (e) {
        is OpdsError.UnsupportedAcquisition -> "No downloadable book on this entry."
        is OpdsError.NotABook -> "That download isn't a supported book."
        is OpdsError.Http -> "Download failed (HTTP ${e.code})."
        is OpdsError.Network -> "Download failed — check your connection."
        else -> "Download failed."
    }
}
