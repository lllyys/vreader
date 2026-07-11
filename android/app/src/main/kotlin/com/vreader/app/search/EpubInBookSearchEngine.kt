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
// - ENGINE-ONLY (no ViewModel / repository dispatch / UI). WI-6's `InBookSearchRepository` is the
//   format-dispatching boundary that calls this for EPUB and adapts the output into the shared
//   `InBookSearchModels` DTOs. The EPUB-track result types ([EpubInBookHit] / [EpubGroup] /
//   [EpubSearchPage] / [EpubSearchOutcome]) live in THIS file so the engine is self-contained (one-file
//   write-set); WI-6 owns the shared-DTO adaptation.
// - `isSearchable` is the FIRST gate: not searchable -> [EpubSearchOutcome.Unsupported], NEVER opening an
//   iterator / calling `search` (no crash, no wasted work).
// - Paging is COMPLETE (round-3 completeness contract — the EPUB analog of the FTS intra-chunk cursor): a
//   page fills up to `pageSize` hits and NEVER discards budget-overflow locators. When more remains the
//   page carries an [EpubSearchCursor] (the LIVE iterator + un-placed locators); the caller (WI-6) resumes
//   via [EpubInBookSearchEngine.nextPage]. The iterator is closed ONLY on a terminal page (exhaustion /
//   error / zero hits); while `moreAvailable` it stays open behind the cursor.
// - A `SearchError` from any `next()` -> [EpubSearchOutcome.Error] (SURFACED, never swallowed; iterator
//   closed) — the error wins even if some hits were already collected. Zero hits -> [NoResults].
// - Grouping is by `Locator.title` (chapter label), FIRST-SEEN order; a null title -> a single null-key
//   group (honest — the navigator still jumps by the raw locator).
// - The query is passed to Readium VERBATIM (no engine-side normalization — Readium's ICU
//   `StringSearchService` owns EPUB folding), so a CJK query reaches `search` unchanged.
//
// @coordinates-with reader/ReadiumLocatorReconstructor.kt (the same final-Publication seam pattern),
//   search/EpubTextExtractor.kt (the `@ExperimentalReadiumApi` + `publication.content` service the bundled
//   `StringSearchService` is backed by), search/InBookSearchRepository.kt (WI-6 — the caller).
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
 * A resume handle for EPUB paging: the LIVE Readium iterator [source] + any leftover locators that
 * overflowed the previous page's budget, so nothing is discarded (round-3 completeness). WI-6 keeps it
 * alive across `loadMore()` and passes it to [EpubInBookSearchEngine.nextPage]; a non-null cursor is
 * always resumable (a terminal page closes the iterator and hands back a null cursor).
 *
 * Lifecycle (round-2 audit — a live cursor owns a Readium iterator, so its disposal must be explicit):
 * - SINGLE-CONSUMPTION: [consume] flips an atomic guard so a cursor is used by exactly ONE `nextPage`
 *   call. A reused or concurrent call fails fast (returns false / gets no leftover) rather than replaying
 *   the immutable leftover as duplicate hits or racing the shared iterator. The engine consumes the
 *   PASSED-IN cursor and mints a FRESH one for the next page, so paging stays linear.
 * - IDEMPOTENT CLOSE: [close] closes the underlying iterator at most once. WI-6 MUST call it on an
 *   ABANDONED cursor (query replaced, search UI dismissed, "load more" declined) so the iterator never
 *   leaks; a terminal page already closes it, and a double close is a no-op.
 */
class EpubSearchCursor internal constructor(
    internal val source: SearchIteratorSource,
    internal val leftover: List<ReadiumLocator>,
) {
    private val consumed = java.util.concurrent.atomic.AtomicBoolean(false)

    /**
     * Atomically claim this cursor for a single resume; returns false if already consumed OR closed
     * (a reuse, a race, or a resume after abandonment). Claiming also blocks a later [close] from closing
     * the shared iterator the resume path now owns.
     */
    internal fun consume(): Boolean = consumed.compareAndSet(false, true)

    /**
     * Close the underlying Readium iterator at most once (idempotent). A no-op if the cursor was already
     * CONSUMED (the resume path owns the iterator's lifecycle through the fresh cursor it returned), so a
     * shared iterator is never prematurely / doubly closed. WI-6 calls this to dispose an ABANDONED cursor.
     */
    fun close() {
        // Claim the cursor for close (same guard as consume): only the FIRST of consume-or-close wins.
        if (consumed.compareAndSet(false, true)) source.close()
    }
}

/**
 * One page of EPUB in-book results: [groups] (by chapter, first-seen order), [moreAvailable], and the
 * [cursor] to resume from — non-null iff [moreAvailable]. When [moreAvailable] is false the cursor is null
 * and the iterator is already closed.
 */
data class EpubSearchPage(
    val groups: List<EpubGroup>,
    val moreAvailable: Boolean,
    val cursor: EpubSearchCursor?,
)

/** The outcome of an EPUB in-book search request (the engine's terminal states). */
sealed interface EpubSearchOutcome {
    /** The publication is not searchable (`isSearchable() == false`) — no search was attempted. */
    data object Unsupported : EpubSearchOutcome

    /** The search ran but produced zero hits (iterator already closed). */
    data object NoResults : EpubSearchOutcome

    /** The search produced [page]. */
    data class Results(val page: EpubSearchPage) : EpubSearchOutcome

    /** The Readium iterator surfaced an [error] (not swallowed; iterator already closed). */
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

    init {
        require(pageSize > 0) { "pageSize must be > 0, was $pageSize" }
    }

    /** Production constructor: wraps the real Readium [publication]. */
    @OptIn(ExperimentalReadiumApi::class)
    constructor(publication: Publication, pageSize: Int = DEFAULT_PAGE_SIZE) :
        this(RealPublicationSearchSource(publication), pageSize)

    /**
     * Run [query] and produce the first page outcome:
     *  - not searchable -> [EpubSearchOutcome.Unsupported] (no iterator opened),
     *  - a `SearchError` while paging -> [EpubSearchOutcome.Error] (surfaced; iterator closed),
     *  - zero hits -> [EpubSearchOutcome.NoResults] (iterator closed),
     *  - otherwise -> [EpubSearchOutcome.Results]; if more remains, the page carries a live [EpubSearchCursor].
     *
     * The [query] is passed to Readium verbatim (no engine-side normalization).
     */
    suspend fun searchFirstPage(query: String): EpubSearchOutcome {
        if (!source.isSearchable()) return EpubSearchOutcome.Unsupported
        val iterator = source.openIterator(query)
        return fillPage(iterator, leftover = emptyList())
    }

    /**
     * Resume paging from a live [cursor] (its iterator + any leftover locators from the prior page's
     * overflow), producing the next page. Same terminal semantics as [searchFirstPage] except a fully
     * consumed cursor with zero further hits yields [EpubSearchOutcome.NoResults] (no more results).
     *
     * SINGLE-CONSUMPTION (round-2 audit): the cursor is claimed atomically — a reused or concurrently
     * dispatched cursor returns [EpubSearchOutcome.Error] WITHOUT replaying its leftover or touching the
     * shared iterator, so paging can never emit duplicate hits or race the iterator. The engine mints a
     * FRESH cursor for the next page, so a linear caller keeps paging with the returned cursor.
     */
    suspend fun nextPage(cursor: EpubSearchCursor): EpubSearchOutcome {
        if (!cursor.consume()) {
            // Reuse / concurrent dispatch: do NOT touch the iterator (its rightful consumer owns it).
            return EpubSearchOutcome.Error(EpubSearchError("search cursor already consumed"))
        }
        return fillPage(cursor.source, cursor.leftover)
    }

    /**
     * Fill one page (up to [pageSize] hits) from [iterator], consuming [leftover] Readium locators FIRST
     * (overflow carried from the previous page — never discarded), then pulling successive iterator pages.
     * On a terminal state (exhaustion, error, or zero hits) the iterator is closed and the returned page's
     * cursor is null; otherwise the iterator stays OPEN and the page carries a resumable cursor holding it
     * plus any locators that overflowed this page's budget.
     */
    private suspend fun fillPage(
        iterator: SearchIteratorSource,
        leftover: List<ReadiumLocator>,
    ): EpubSearchOutcome {
        val hits = ArrayList<EpubInBookHit>(pageSize)
        // A mutable queue of locators still to place: the carried-over overflow drains first.
        val pending = ArrayDeque(leftover)
        var exhausted = false

        try {
            while (hits.size < pageSize) {
                // Place any pending locators (overflow / a just-fetched page) before fetching more.
                while (pending.isNotEmpty() && hits.size < pageSize) {
                    hits.add(pending.removeFirst().toHit())
                }
                if (hits.size >= pageSize) break
                when (val result = iterator.nextPage()) {
                    is SearchPageResult.Failed -> {
                        iterator.close()
                        return EpubSearchOutcome.Error(result.error)
                    }
                    SearchPageResult.Exhausted -> { exhausted = true; break }
                    is SearchPageResult.Locators -> pending.addAll(result.locators)
                }
            }
        } catch (t: Throwable) {
            iterator.close()
            throw t
        }

        if (hits.isEmpty()) {
            iterator.close()
            return EpubSearchOutcome.NoResults
        }
        // More remains iff the iterator was not exhausted (either overflow is queued in `pending`, or the
        // iterator still has unfetched pages). Only a confirmed exhaustion with nothing pending is terminal.
        val moreAvailable = !(exhausted && pending.isEmpty())
        return if (moreAvailable) {
            EpubSearchOutcome.Results(
                EpubSearchPage(groupByChapter(hits), moreAvailable = true, cursor = EpubSearchCursor(iterator, pending.toList())),
            )
        } else {
            iterator.close()
            EpubSearchOutcome.Results(EpubSearchPage(groupByChapter(hits), moreAvailable = false, cursor = null))
        }
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
