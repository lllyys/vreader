// Purpose: The EPUB in-book search engine over Readium 3.3.0's OWN `SearchService` — feature #133 WI-5
// (round-2 Critical-1 resolution). EPUB search/position does NOT use the #128 FTS index at all: the FTS
// index is chunk-level + location-less and `sectionIndex -> spine href` is unrecoverable, so an EPUB text
// hit cannot be turned into a jumpable position from it. Readium's `publication.search(query)` instead
// returns REAL href-bearing, snippet-bearing `Locator`s the navigator jumps to natively (`nav.go`), so the
// engine just gates on `isSearchable`, pages the `SearchIterator`, and maps each `Locator` to an
// [EpubInBookHit] grouped by chapter — no reconstruction, no href guessing, no FTS occurrence math.
//
// The Readium calls sit behind a mockable [PublicationSearchSource] seam because Readium's `Publication`
// is a `final` (unmockable) class — the SAME extracted-seam pattern #135's `PublicationLocatorSource`
// (`ReadiumLocatorReconstructor`) uses. Production wires the real publication via the `(publication)`
// constructor; unit tests fake ONLY the seam and hand back REAL Readium `Locator` value types.
//
// Key decisions:
// - This is ENGINE-ONLY: no ViewModel, no repository dispatch, no UI — WI-6's `InBookSearchRepository`
//   is the format-dispatching boundary that calls this for the EPUB format and adapts the engine's output
//   into the shared `InBookSearchModels` DTOs. The EPUB-track result types ([EpubInBookHit] / [EpubGroup]
//   / [EpubSearchPage] / [EpubSearchOutcome]) live in THIS file to keep the engine self-contained and its
//   write-set to a single file; WI-6 owns the shared-DTO adaptation.
// - `isSearchable()` is the FIRST gate: a not-searchable publication yields [EpubSearchOutcome.Unsupported]
//   and the engine NEVER opens an iterator / calls `search` — no crash, no wasted work.
// - The first page fills up to `pageSize` hits by pulling successive `SearchIterator.next()` pages;
//   `moreAvailable` is true iff the iterator was NOT exhausted while filling (more can be paged in later).
//   An empty first page (or immediate exhaustion) with zero hits -> [EpubSearchOutcome.NoResults].
// - A `SearchError` from any `next()` -> [EpubSearchOutcome.Error] (SURFACED, never swallowed) — even if
//   some hits were already collected in this fill, the error wins so the UI can show a failure state.
// - Grouping is by `Locator.title` (the chapter label), preserving FIRST-SEEN title order; a null title
//   groups under a single null-key group (honest — the navigator still jumps by the raw locator).
// - The query string is passed to Readium VERBATIM — the engine does NOT re-normalize (Readium's ICU
//   `StringSearchService` owns EPUB folding), so a CJK query reaches `search` unchanged.
//
// @coordinates-with reader/ReadiumLocatorReconstructor.kt (the same final-Publication seam pattern),
//   search/EpubTextExtractor.kt (the `@ExperimentalReadiumApi` + `publication.content` service the same
//   bundled `StringSearchService` is backed by), search/InBookSearchRepository.kt (WI-6 — the caller that
//   adapts [EpubSearchPage] into the shared in-book DTOs).
package com.vreader.app.search

import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator as ReadiumLocator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.services.search.SearchError
import org.readium.r2.shared.publication.services.search.isSearchable
import org.readium.r2.shared.publication.services.search.search

/** A stable, engine-neutral error for an EPUB in-book search failure (wraps Readium's `SearchError`). */
data class EpubSearchError(val message: String)

/**
 * A single located EPUB search hit: the RAW Readium [readiumLocator] the navigator jumps to via
 * `navigator.go`, plus the presentation fields the hit row needs — the chapter [sectionTitle] (grouping
 * key, from `Locator.title`), the [snippet] (from `Locator.text.highlight`) and its [before]/[after]
 * context. Exactly the Readium locator is retained; there is NO canonical-locator reconstruction for EPUB.
 */
data class EpubInBookHit(
    val sectionTitle: String?,
    val snippet: String,
    val before: String,
    val after: String,
    val readiumLocator: ReadiumLocator,
)

/** A chapter group of EPUB hits (keyed by `Locator.title`, in first-seen order). */
data class EpubGroup(
    val title: String?,
    val hits: List<EpubInBookHit>,
)

/**
 * One page of EPUB in-book results: [groups] (grouped by chapter, first-seen order) and [moreAvailable]
 * (true iff the Readium iterator was not exhausted while filling this page — more can be paged in later).
 */
data class EpubSearchPage(
    val groups: List<EpubGroup>,
    val moreAvailable: Boolean,
)

/** The outcome of an EPUB in-book search request (the engine's terminal states). */
sealed interface EpubSearchOutcome {
    /** The publication is not searchable (`isSearchable() == false`) — no search was attempted. */
    data object Unsupported : EpubSearchOutcome

    /** The search ran but produced zero hits. */
    data object NoResults : EpubSearchOutcome

    /** The search produced [page]. */
    data class Results(val page: EpubSearchPage) : EpubSearchOutcome

    /** The Readium iterator surfaced an [error] (not swallowed). */
    data class Error(val error: EpubSearchError) : EpubSearchOutcome
}

/** The result of pulling one page from a [SearchIteratorSource]. */
sealed interface SearchPageResult {
    /** A page of Readium locators (possibly empty). */
    data class Locators(val locators: List<ReadiumLocator>) : SearchPageResult

    /** No more pages — the iterator is exhausted. */
    data object Exhausted : SearchPageResult

    /** The iterator failed. */
    data class Failed(val error: EpubSearchError) : SearchPageResult
}

/**
 * The paging half of the Readium search seam: a thin wrapper over a live Readium `SearchIterator` so the
 * engine can page it without knowing about `Try<LocatorCollection, SearchError>`. Faked in tests.
 */
interface SearchIteratorSource {
    /** Pull the next page of locators from the underlying iterator (or exhaustion / failure). */
    suspend fun nextPage(): SearchPageResult

    /** Release the underlying Readium iterator. */
    fun close()
}

/**
 * The Readium search seam the engine consumes: capability probe + iterator open. Extracted because
 * Readium's `Publication` is `final` (unmockable) — the fake seam lets the engine's gating / paging /
 * mapping / error handling be unit-tested with REAL Readium `Locator` value types (only the Publication
 * calls are faked). Production wires the real publication via [EpubInBookSearchEngine]'s `(publication)`
 * constructor.
 */
interface PublicationSearchSource {
    /** Whether the publication supports search (Readium `SearchServiceKt.isSearchable`). */
    suspend fun isSearchable(): Boolean

    /** Open a search iterator for [query] (Readium `Publication.search`). */
    suspend fun openIterator(query: String): SearchIteratorSource
}

/**
 * Adapts a real Readium [Publication] to the [PublicationSearchSource] seam. The iterator wrapper folds
 * Readium's `Try<LocatorCollection?, SearchError>` into [SearchPageResult]: a successful `Try` whose
 * `LocatorCollection` is `null` means the iterator is exhausted (Readium's end-of-results convention);
 * a failure carries the `SearchError`.
 */
@OptIn(ExperimentalReadiumApi::class)
private class RealPublicationSearchSource(
    private val publication: Publication,
) : PublicationSearchSource {

    override suspend fun isSearchable(): Boolean = publication.isSearchable

    override suspend fun openIterator(query: String): SearchIteratorSource {
        // `search` is NULLABLE (no SearchService -> null); `isSearchable` already gated it, so this is
        // a belt-and-suspenders — a null iterator degrades to immediately-exhausted (zero results),
        // never a crash.
        val iterator = publication.search(query)
            ?: return object : SearchIteratorSource {
                override suspend fun nextPage(): SearchPageResult = SearchPageResult.Exhausted
                override fun close() = Unit
            }
        return object : SearchIteratorSource {
            override suspend fun nextPage(): SearchPageResult {
                val result = iterator.next()
                return result.fold(
                    onSuccess = { collection ->
                        if (collection == null) SearchPageResult.Exhausted
                        else SearchPageResult.Locators(collection.locators)
                    },
                    onFailure = { error: SearchError ->
                        SearchPageResult.Failed(EpubSearchError(error.message))
                    },
                )
            }

            override fun close() = iterator.close()
        }
    }
}

/**
 * EPUB in-book search over Readium's own `SearchService`. Gate on [PublicationSearchSource.isSearchable],
 * page the iterator up to [pageSize] hits, map each Readium [ReadiumLocator] to an [EpubInBookHit] grouped
 * by chapter, and surface exhaustion / errors — see the file header for the full contract.
 *
 * @param source the Readium search seam (production: the real publication; tests: a fake).
 * @param pageSize the maximum number of hits collected for the first page (a per-page window, not a cap on
 *   total results — WI-6 pages further via the iterator).
 */
class EpubInBookSearchEngine internal constructor(
    private val source: PublicationSearchSource,
    private val pageSize: Int = DEFAULT_PAGE_SIZE,
) {

    /** Production constructor: wraps the real Readium [publication]. */
    @OptIn(ExperimentalReadiumApi::class)
    constructor(publication: Publication, pageSize: Int = DEFAULT_PAGE_SIZE) :
        this(RealPublicationSearchSource(publication), pageSize)

    /**
     * Run [query] and produce the first page outcome:
     *  - not searchable -> [EpubSearchOutcome.Unsupported] (no iterator opened),
     *  - a `SearchError` while paging -> [EpubSearchOutcome.Error] (surfaced),
     *  - zero hits -> [EpubSearchOutcome.NoResults],
     *  - otherwise -> [EpubSearchOutcome.Results] with the grouped page.
     *
     * The [query] is passed to Readium verbatim (no engine-side normalization).
     */
    suspend fun searchFirstPage(query: String): EpubSearchOutcome {
        if (!source.isSearchable()) return EpubSearchOutcome.Unsupported

        val iterator = source.openIterator(query)
        val hits = ArrayList<EpubInBookHit>(pageSize)
        var moreAvailable = false
        try {
            // Fill up to pageSize hits, pulling successive iterator pages. An error at any point wins.
            while (hits.size < pageSize) {
                when (val result = iterator.nextPage()) {
                    is SearchPageResult.Failed -> return EpubSearchOutcome.Error(result.error)
                    SearchPageResult.Exhausted -> {
                        // No more content — the iterator is drained; nothing more to page in.
                        moreAvailable = false
                        break
                    }
                    is SearchPageResult.Locators -> {
                        for (locator in result.locators) {
                            hits.add(locator.toHit())
                            if (hits.size >= pageSize) {
                                // Budget reached mid-Readium-page: more results remain to be paged.
                                moreAvailable = true
                                break
                            }
                        }
                    }
                }
            }
        } finally {
            iterator.close()
        }

        if (hits.isEmpty()) return EpubSearchOutcome.NoResults
        return EpubSearchOutcome.Results(EpubSearchPage(groupByChapter(hits), moreAvailable))
    }

    /** Group hits by `Locator.title`, preserving first-seen title order. */
    private fun groupByChapter(hits: List<EpubInBookHit>): List<EpubGroup> {
        val order = LinkedHashMap<String?, MutableList<EpubInBookHit>>()
        for (hit in hits) {
            order.getOrPut(hit.sectionTitle) { mutableListOf() }.add(hit)
        }
        return order.map { (title, groupHits) -> EpubGroup(title, groupHits) }
    }

    private fun ReadiumLocator.toHit(): EpubInBookHit {
        val text = this.text
        return EpubInBookHit(
            sectionTitle = this.title,
            snippet = text.highlight.orEmpty(),
            before = text.before.orEmpty(),
            after = text.after.orEmpty(),
            readiumLocator = this,
        )
    }

    companion object {
        /** The default first-page hit budget (a per-page window, not a total cap). */
        const val DEFAULT_PAGE_SIZE = 50
    }
}
