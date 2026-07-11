// Purpose: The observable in-text search boundary — feature #128 WI-6. Turns a raw user query into a
// Flow of first-hit-per-book text hits over the WI-4 FTS index. The Flow is OBSERVABLE (not a one-shot
// List) so in-text results appear/GROW automatically as the WI-5 coordinator publishes more books
// mid-indexing — the repository re-runs its query whenever the index-generation signal changes.
//
// Key decisions:
// - The index-generation signal is SearchDao.observeSearchSectionsCount() (every publishBook adds
//   rows → the count changes → flatMapLatest re-queries with the SAME query string). Fix #1 (live
//   result growth): a held query enlarges as indexing completes.
// - A null/blank BuiltQuery (SearchQueryBuilder.ftsQuery returned null) short-circuits to an EMPTY
//   Flow BEFORE any FTS MATCH — passing an empty/null query to `search_sections_fts MATCH` SQL-errors
//   (fix #2 — null-query crash).
// - Snippet + match-range assembly happens HERE via SnippetBuilder (token-aware, so a case/width/
//   diacritic-folded match still highlights). One hit per book (SearchDao.firstHitsPerBook), so a
//   heavily-matching book contributes exactly one row (Gate-2 HIGH).
package com.vreader.app.search

import com.vreader.app.data.SearchDao
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf

/**
 * One in-text search hit for a book: the book key, the chapter/section title (for the "— Ch. N"
 * attribution; null for TXT/MD), the snippet display text, and the wash-highlight ranges within it.
 */
data class TextHit(
    val bookKey: String,
    val sectionTitle: String?,
    val snippet: String,
    val matchRanges: List<IntRange>,
)

/**
 * The observable text-search boundary. `textHits` re-runs as the index grows; the ViewModel (WI-6)
 * combines it with the live metadata filter + the completeness Flow.
 */
class SearchRepository(private val searchDao: SearchDao) {

    /**
     * A Flow of first-hit-per-book text hits for [rawQuery]. Re-emits (enlarged) whenever the published
     * section count changes, so a held query grows as indexing completes (fix #1). A blank/operator-only
     * query yields an EMPTY Flow (no FTS MATCH is ever issued for a null BuiltQuery — fix #2).
     */
    @OptIn(ExperimentalCoroutinesApi::class)
    fun textHits(rawQuery: String, limit: Int = DEFAULT_LIMIT): Flow<List<TextHit>> {
        // Fix #2: short-circuit BEFORE the index-generation subscription and BEFORE any MATCH SQL. A
        // blank/operator-only query yields ONE empty emission (never a MATCH), so a downstream combine
        // still fires — metadata search stays live even for a null in-text query.
        val built = SearchQueryBuilder.ftsQuery(rawQuery) ?: return flowOf(emptyList())
        // Fix #1: flatMapLatest over the index-generation signal so a HELD query re-queries + grows as
        // more sections publish. distinctUntilChanged so an unchanged count doesn't re-run needlessly.
        return searchDao.observeSearchSectionsCount()
            .distinctUntilChanged()
            .flatMapLatest {
                flow { emit(queryOnce(built, limit)) }
            }
    }

    /** One-shot query — the current first-hit-per-book results for an already-built query. */
    private suspend fun queryOnce(built: BuiltQuery, limit: Int): List<TextHit> =
        searchDao.firstHitsPerBook(built.fts, limit).map { section ->
            val snippet = SnippetBuilder.build(section.text, built)
            TextHit(
                bookKey = section.bookKey,
                sectionTitle = section.sectionTitle,
                snippet = snippet?.text ?: section.text,
                matchRanges = snippet?.matchRanges ?: emptyList(),
            )
        }

    companion object {
        /** First-hit-per-book DISTINCT-book limit (mirrors SearchDao.firstHitsPerBook's default). */
        const val DEFAULT_LIMIT: Int = 200
    }
}
