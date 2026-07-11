// Purpose: The FORMAT-DISPATCHING in-book search boundary — feature #133 WI-6. Unifies WI-1..WI-5 into
// one seam the ViewModel (WI-8) calls: `page(bookKey, format, query, cursor?, pageSize)`. Routes EPUB to
// the Readium engine (WI-5) and TXT/MD to the FTS pipeline (SearchQueryBuilder → SearchDao →
// RawOffsetMatcher → InBookSearchHitResolver), adapting each track's native result types into the shared
// format-neutral InBookHit / InBookGroup / InBookSearchPage / InBookSearchOutcome DTOs so downstream code
// is format-agnostic. Pure orchestration — no DB/Readium/UI code of its own beyond the dispatch.
//
// Key decisions:
// - EACH format uses the position engine that owns its coordinates (plan §2 two-track model): EPUB never
//   touches the FTS index (Readium's SearchService returns navigable Locators); TXT/MD never touches
//   Readium (the FTS index + a raw re-scan resolve to a canonical Locator). The dispatch enforces this — a
//   miswired call would fail fast (the injected factories for the other track are error-throwing in tests).
// - The page BUDGET (`pageSize`) counts HITS (occurrences), not chunks (plan §"pagination completeness"):
//   a page fills to `pageSize` occurrences across as many chunks as needed.
// - RESUME-WITHIN-CHUNK completeness (round-3 Medium): the TXT/MD cursor is
//   SearchCursor.Fts(sectionIndex, chunkOrdinal, id, occurrenceIndex). The repository starts at the
//   cursor's chunk — re-fetched INCLUSIVELY via `chunkAtOrAfter` so a partially-consumed chunk
//   (occurrenceIndex > 0) is not skipped by the DAO's strict `>` — and expands it with
//   `RawOffsetMatcher.occurrences(from = cursor.occurrenceIndex, maxThisPage = remainingBudget)`. If a
//   chunk still has un-emitted occurrences when the budget fills, `nextCursor` stays on the SAME chunk with
//   `occurrenceIndex = slice.nextOccurrenceIndex`; only when a chunk is fully consumed does the cursor
//   advance to the next chunk via `matchingChunksPage` with `occurrenceIndex = 0`. The union across pages =
//   every occurrence in every matched chunk, no gap, no duplicate. `moreAvailable` is false ONLY when the
//   whole book is exhausted.
// - MATCH-safety: EVERY TXT/MD query is routed through SearchQueryBuilder — a blank / operator-only query
//   yields `ftsQuery == null` → NoResults with NO DAO/MATCH call; a valid query's BUILT (sanitized) MATCH
//   string is the ONLY string handed to the DAO, never the raw user text.
// - Cancellation-cooperative: `ensureActive()` before every DAO page fetch and around occurrence
//   expansion, so a cancelled scope (a superseded query — WI-8 flatMapLatest) stops promptly without a
//   further page fetch, and no Readium iterator is left mid-page.
// - EPUB cursor indirection: the shared SearchCursor.Epub carries an opaque token; the live Readium
//   EpubSearchCursor is held HERE per session (never in the pure InBookSearchModels file). An abandoned /
//   superseded token is closed so the Readium iterator never leaks.
//
// @coordinates-with search/EpubInBookSearchEngine.kt (the EPUB track), search/RawOffsetMatcher.kt +
//   search/SearchQueryBuilder.kt + search/TxtMdInBookHitResolver.kt (the TXT/MD track),
//   data/SearchDao.kt (the FTS DAO queries), search/InBookSearchModels.kt (the shared DTOs).
package com.vreader.app.search

import com.vreader.app.data.SearchSectionEntity
import java.util.concurrent.atomic.AtomicLong
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext
import vreader.contracts.BookFormat

/**
 * The FTS-track (TXT/MD) dependency bundle. Each lambda is a thin adapter over a WI-1 [com.vreader.app.data.SearchDao]
 * method or (for [resolverFor]) a per-book [InBookSearchHitResolver] factory (WI-4), injected at the boundary
 * so the repository is unit-testable without Room or file I/O.
 *
 * @param matchingChunksPage one page of matching chunks AFTER the cursor tuple (strict `>`).
 * @param chunkAtOrAfter the first matching chunk AT-OR-AFTER the cursor tuple (inclusive `>=` on id) — used
 *   to RE-FETCH a partially-consumed chunk for a resume so it is not skipped by [matchingChunksPage].
 * @param resolverFor builds the TXT/MD resolver for [bookKey] (memoized decode per session inside the resolver).
 */
class InBookFtsDeps(
    val matchingChunksPage: suspend (ftsQuery: String, afterSectionIndex: Int, afterChunkOrdinal: Int, afterId: Long, limit: Int) -> List<SearchSectionEntity>,
    val chunkAtOrAfter: suspend (ftsQuery: String, atSectionIndex: Int, atChunkOrdinal: Int, atId: Long) -> SearchSectionEntity?,
    val resolverFor: (bookKey: String) -> InBookSearchHitResolver,
)

/**
 * Routes an in-book search page request to the format's engine and adapts the result into the shared
 * [InBookSearchOutcome] DTOs.
 *
 * @param dispatcher the CoroutineDispatcher all DB/expansion work runs on (never hardcode Dispatchers.IO — rule 50 §1).
 * @param fts the TXT/MD FTS-track dependencies.
 * @param epubEngineFor builds the EPUB engine (over the host's live Readium publication) for [bookKey].
 */
class InBookSearchRepository(
    private val dispatcher: CoroutineDispatcher,
    private val fts: InBookFtsDeps,
    private val epubEngineFor: (bookKey: String) -> EpubInBookSearchEngine,
) {

    // ---- EPUB session state: the live Readium cursor behind an opaque token (kept OUT of the pure model) ----

    private val epubTokenSeq = AtomicLong(0L)
    private val liveEpubCursors = HashMap<String, EpubSearchCursor>()
    private var epubEngine: EpubInBookSearchEngine? = null
    private var epubEngineKey: String? = null

    /**
     * One page of in-book results for [bookKey] of [format] for [rawQuery], resuming from [cursor] (null =
     * first page). [pageSize] is the per-page HIT (occurrence) budget. EPUB delegates to the Readium engine;
     * TXT/MD walks the FTS pipeline. PDF/AZW3 (no index, no publication) → [InBookSearchOutcome.Unsupported].
     */
    suspend fun page(
        bookKey: String,
        format: BookFormat,
        rawQuery: String,
        cursor: SearchCursor?,
        pageSize: Int,
    ): InBookSearchOutcome = withContext(dispatcher) {
        when (format) {
            BookFormat.epub -> epubPage(bookKey, rawQuery, cursor)
            BookFormat.txt, BookFormat.md -> txtMdPage(bookKey, rawQuery, cursor, pageSize)
            BookFormat.pdf, BookFormat.azw3 -> InBookSearchOutcome.Unsupported
        }
    }

    // ---- EPUB track -------------------------------------------------------------------------------

    private suspend fun epubPage(
        bookKey: String,
        rawQuery: String,
        cursor: SearchCursor?,
    ): InBookSearchOutcome {
        val engine = engineFor(bookKey)
        val outcome = when (cursor) {
            null -> {
                // A FRESH first-page request supersedes any live cursor held for a prior query on THIS book
                // (WI-8 replaces query A with B via flatMapLatest); close them so their Readium iterators
                // never leak (Gate-4 High — a same-book query swap must dispose the old iterator).
                closeAllEpubCursors()
                engine.searchFirstPage(rawQuery)
            }
            is SearchCursor.Epub -> {
                val live = liveEpubCursors.remove(cursor.iteratorToken)
                    ?: return InBookSearchOutcome.Error("search cursor expired")
                engine.nextPage(live)
            }
            is SearchCursor.Fts -> return InBookSearchOutcome.Error("FTS cursor on the EPUB track")
        }
        return adaptEpub(outcome)
    }

    /** Build (and memoize per book) the EPUB engine; a book change closes any stale live cursors. */
    private fun engineFor(bookKey: String): EpubInBookSearchEngine {
        if (epubEngine == null || epubEngineKey != bookKey) {
            closeAllEpubCursors()
            epubEngine = epubEngineFor(bookKey)
            epubEngineKey = bookKey
        }
        return epubEngine!!
    }

    /** Adapt the EPUB engine's self-contained result types into the shared DTOs, minting an opaque token for
     *  a live cursor so the Readium iterator lifecycle stays entirely inside this repository. */
    private fun adaptEpub(outcome: EpubSearchOutcome): InBookSearchOutcome = when (outcome) {
        EpubSearchOutcome.Unsupported -> InBookSearchOutcome.Unsupported
        EpubSearchOutcome.NoResults -> InBookSearchOutcome.NoResults
        is EpubSearchOutcome.Error -> InBookSearchOutcome.Error(outcome.error.message)
        is EpubSearchOutcome.Results -> {
            val page = outcome.page
            val groups = page.groups.map { g ->
                InBookGroup(title = g.title, hits = g.hits.map { it.toSharedHit() })
            }
            val nextCursor: SearchCursor? = page.cursor?.let { live ->
                val token = "epub-" + epubTokenSeq.incrementAndGet()
                liveEpubCursors[token] = live
                SearchCursor.Epub(token)
            }
            InBookSearchOutcome.Results(InBookSearchPage(groups, page.moreAvailable, nextCursor))
        }
    }

    /** Serialize the Readium locator to a JSON string (the app's existing Readium-locator handle) + wash the
     *  snippet's highlight span (the `before`-length prefix, `highlight`-length body). */
    private fun EpubInBookHit.toSharedHit(): InBookHit {
        val readiumJson = runCatching { readiumLocator.toJSON().toString() }.getOrNull()
        // The visible snippet is before+highlight+after; the highlight range is exactly the highlight run.
        val snippet = before + snippet + after
        val ranges = if (snippet.isNotEmpty() && this.snippet.isNotEmpty()) {
            val start = before.length
            listOf(IntRange(start, start + this.snippet.length - 1))
        } else {
            emptyList()
        }
        return InBookHit(
            sectionTitle = sectionTitle,
            canonicalLocator = null,
            readiumLocatorJson = readiumJson,
            snippet = snippet,
            matchRanges = ranges,
        )
    }

    /** Close every live EPUB cursor (a book change / dispose) so no Readium iterator leaks. */
    fun closeAllEpubCursors() {
        liveEpubCursors.values.forEach { runCatching { it.close() } }
        liveEpubCursors.clear()
    }

    // ---- TXT/MD track -----------------------------------------------------------------------------

    private suspend fun txtMdPage(
        bookKey: String,
        rawQuery: String,
        cursor: SearchCursor?,
        pageSize: Int,
    ): InBookSearchOutcome {
        // MATCH-safety: a blank / operator-only query builds to null → empty, NO DAO/MATCH call.
        val built = SearchQueryBuilder.ftsQuery(rawQuery) ?: return InBookSearchOutcome.NoResults
        val structured = SearchQueryBuilder.structuredQuery(rawQuery) ?: return InBookSearchOutcome.NoResults
        if (pageSize <= 0) return InBookSearchOutcome.NoResults

        val fromCursor: SearchCursor.Fts? = when (cursor) {
            null -> null
            is SearchCursor.Fts -> cursor
            is SearchCursor.Epub -> return InBookSearchOutcome.Error("EPUB cursor on the TXT/MD track")
        }
        val resolver = fts.resolverFor(bookKey)

        val hits = ArrayList<InBookHit>(pageSize)
        var nextCursor: SearchCursor.Fts? = null

        // The chunk we are currently expanding: the cursor's chunk (re-fetched INCLUSIVELY so a
        // partially-consumed chunk resumes) on a resume, else the first matching chunk.
        var current: SearchSectionEntity? = firstChunk(built.fts, fromCursor)
        var fromOccurrence = fromCursor?.occurrenceIndex ?: 0

        loop@ while (current != null && hits.size < pageSize) {
            coroutineContext.ensureActive()
            val chunkEntity = current
            val remaining = pageSize - hits.size
            val slice = RawOffsetMatcher.occurrences(
                rawChunkText = chunkEntity.text,
                query = structured,
                fromOccurrenceIndex = fromOccurrence,
                maxThisPage = remaining,
            )
            for (occ in slice.occurrences) {
                coroutineContext.ensureActive()
                val locator = resolver.resolve(chunkEntity.sectionIndex, occ) ?: continue
                val (snippet, ranges) = collapsedWindow(chunkEntity.text, occ)
                hits.add(
                    InBookHit(
                        sectionTitle = sectionLabel(chunkEntity),
                        canonicalLocator = locator,
                        readiumLocatorJson = null,
                        snippet = snippet,
                        matchRanges = ranges,
                    ),
                )
            }

            if (slice.nextOccurrenceIndex != null) {
                // This chunk still has un-emitted occurrences → the page is full; resume ON THIS CHUNK.
                nextCursor = SearchCursor.Fts(
                    sectionIndex = chunkEntity.sectionIndex,
                    chunkOrdinal = chunkEntity.chunkOrdinal,
                    id = chunkEntity.id,
                    occurrenceIndex = slice.nextOccurrenceIndex,
                )
                break@loop
            }

            // This chunk is fully consumed → advance to the next chunk (strict `>`, occurrenceIndex reset).
            fromOccurrence = 0
            coroutineContext.ensureActive()
            val nextChunks = fts.matchingChunksPage(
                built.fts,
                chunkEntity.sectionIndex,
                chunkEntity.chunkOrdinal,
                chunkEntity.id,
                1,
            )
            current = nextChunks.firstOrNull()
            if (current != null && hits.size >= pageSize) {
                // Budget hit exactly at a chunk boundary → resume at the NEXT chunk, occurrenceIndex 0.
                nextCursor = SearchCursor.Fts(
                    sectionIndex = current.sectionIndex,
                    chunkOrdinal = current.chunkOrdinal,
                    id = current.id,
                    occurrenceIndex = 0,
                )
                break@loop
            }
        }

        // NoResults ONLY when the book is genuinely exhausted with nothing to show. If a continuation
        // cursor survived (a slice whose occurrences ALL failed resolution, or a budget that filled at a
        // chunk boundary), keep paging — otherwise later resolvable occurrences past the un-resolvable
        // slice would be lost and `moreAvailable` would go false before whole-book exhaustion (Gate-4
        // Medium — resolver-null must not prematurely terminate the search).
        if (hits.isEmpty() && nextCursor == null) return InBookSearchOutcome.NoResults
        val groups = groupBySection(hits)
        return InBookSearchOutcome.Results(InBookSearchPage(groups, moreAvailable = nextCursor != null, nextCursor = nextCursor))
    }

    /** The chunk to start THIS page at: on a resume, the cursor's chunk re-fetched INCLUSIVELY (so a partial
     *  chunk is not skipped); else the first matching chunk after (-1,-1,-1). */
    private suspend fun firstChunk(ftsQuery: String, fromCursor: SearchCursor.Fts?): SearchSectionEntity? =
        if (fromCursor == null) {
            fts.matchingChunksPage(ftsQuery, -1, -1, -1L, 1).firstOrNull()
        } else {
            fts.chunkAtOrAfter(ftsQuery, fromCursor.sectionIndex, fromCursor.chunkOrdinal, fromCursor.id)
        }

    /** The 1-based human section label ("Section 1", …) or the stored chapter title when present. */
    private fun sectionLabel(chunk: SearchSectionEntity): String =
        chunk.sectionTitle?.takeIf { it.isNotBlank() } ?: "Section ${chunk.sectionIndex + 1}"

    /** Group hits by section label, first-seen order (hits already arrive in reading order). */
    private fun groupBySection(hits: List<InBookHit>): List<InBookGroup> {
        val order = LinkedHashMap<String?, MutableList<InBookHit>>()
        for (hit in hits) order.getOrPut(hit.sectionTitle) { mutableListOf() }.add(hit)
        return order.map { (title, groupHits) -> InBookGroup(title, groupHits) }
    }

    // ---- TXT/MD snippet (raw-span-anchored, so the highlight matches the jump anchor) --------------

    /**
     * Build a whitespace-collapsed display window centered on the raw occurrence span, plus the highlight
     * range in snippet-local coordinates. The highlight IS the located span, so the snippet highlight and
     * the jump anchor are the same occurrence — no independent re-search that could disagree with the
     * matcher's offsets.
     */
    private fun collapsedWindow(rawText: String, occ: RawOccurrence): Pair<String, List<IntRange>> {
        val n = rawText.length
        val start = occ.startUtf16.coerceIn(0, n)
        val end = occ.endUtf16.coerceIn(start, n)
        val lo = (start - SNIPPET_WINDOW).coerceAtLeast(0)
        val hi = (end + SNIPPET_WINDOW).coerceAtMost(n)
        val raw = rawText.substring(lo, hi)
        // Collapse control/whitespace runs to single spaces, tracking where the match span lands.
        val sb = StringBuilder(raw.length)
        var matchStart = -1
        var matchEnd = -1
        var prevWs = false
        var i = 0
        while (i < raw.length) {
            val absolute = lo + i
            val c = raw[i]
            val isWs = c.isWhitespace() || c.isISOControl()
            if (absolute == start) matchStart = sb.length
            if (isWs) {
                if (!prevWs && sb.isNotEmpty()) sb.append(' ')
                prevWs = true
            } else {
                sb.append(c)
                prevWs = false
            }
            if (absolute + 1 == end) matchEnd = sb.length - 1
            i++
        }
        // Trim leading/trailing space and shift the match range.
        val leading = sb.indexOfFirst { !it.isWhitespace() }.let { if (it < 0) 0 else it }
        val display = sb.toString().trim()
        val ranges = if (matchStart >= 0 && matchEnd >= matchStart) {
            val s = matchStart - leading
            val e = matchEnd - leading
            if (s in 0..display.length && e in 0 until display.length && s <= e) listOf(IntRange(s, e)) else emptyList()
        } else {
            emptyList()
        }
        return display to ranges
    }

    private companion object {
        /** Snippet half-window (raw code units either side of the match span). */
        const val SNIPPET_WINDOW = 60
    }
}
