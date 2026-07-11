// Purpose: The in-book-search UI-state + backend-seam types the WI-8 ViewModel exposes — feature #133.
// Split out of InBookSearchViewModel.kt to keep the state machine focused: this file owns the observable
// [InBookSearchScreenState] (query + recents + the [InBookSearchContent] region — a pure function of the
// pipeline the WI-9 sheet renders) and the [InBookSearcher] boundary the ViewModel drives (the WI-6
// InBookSearchRepository surface, consumed as an interface so tests fake it; production wires the concrete
// repository behind [asSearcher]).
//
// @coordinates-with search/InBookSearchViewModel.kt (the state machine that produces these),
//   search/InBookSearchRepository.kt (WI-6 — the concrete backend behind [InBookSearcher]),
//   search/InBookSearchModels.kt (InBookGroup / InBookSearchOutcome / SearchCursor).
package com.vreader.app.search

import vreader.contracts.BookFormat

/**
 * The search backend seam the ViewModel drives — exactly the WI-6 [InBookSearchRepository] surface it needs.
 * Consumed as an interface so tests fake it; production wires the concrete repository behind it (one instance
 * per reader session).
 */
interface InBookSearcher {
    /** One page of in-book results (null [cursor] = first page). See [InBookSearchRepository.page]. */
    suspend fun page(
        bookKey: String,
        format: BookFormat,
        rawQuery: String,
        cursor: SearchCursor?,
        pageSize: Int,
    ): InBookSearchOutcome

    /** Dispose every live EPUB Readium iterator held for this session. See [InBookSearchRepository.closeAllEpubCursors]. */
    fun closeAllEpubCursors()
}

/** Adapts the concrete WI-6 [InBookSearchRepository] to the [InBookSearcher] seam (production wiring). */
fun InBookSearchRepository.asSearcher(): InBookSearcher = object : InBookSearcher {
    override suspend fun page(bookKey: String, format: BookFormat, rawQuery: String, cursor: SearchCursor?, pageSize: Int): InBookSearchOutcome =
        this@asSearcher.page(bookKey, format, rawQuery, cursor, pageSize)

    override fun closeAllEpubCursors() = this@asSearcher.closeAllEpubCursors()
}

/**
 * The content region of the in-book-search sheet — a pure function of the pipeline. Exactly one variant at a
 * time; [InBookSearchScreenState] wraps it with the always-live query + recents.
 */
sealed interface InBookSearchContent {
    /** No (non-blank) query — the empty state (recents live in the wrapper). */
    data object Idle : InBookSearchContent

    /** A query settled and a search is running (or the TXT/MD index is being consulted). */
    data object Loading : InBookSearchContent

    /** TXT/MD only: the FTS index is still building — a "still building" hint, NOT a false NoResults. The
     *  held query re-runs automatically when the index settles. */
    data object Indexing : InBookSearchContent

    /** Grouped results; [moreAvailable] gates append-on-scroll (`loadMore`). */
    data class Results(val groups: List<InBookGroup>, val moreAvailable: Boolean) : InBookSearchContent

    /** The search ran and produced zero hits (definitive). */
    data object NoResults : InBookSearchContent

    /** The format has no in-book search (the host hides the Search entry). */
    data object Unsupported : InBookSearchContent

    /** The backend surfaced a failure. */
    data class Error(val message: String) : InBookSearchContent
}

/**
 * The full in-book-search sheet state: the always-live [query] + [recents] plus the [content] region.
 * [hidesSearchEntry] is true only for [InBookSearchContent.Unsupported] (the host omits the Search control).
 */
data class InBookSearchScreenState(
    val query: String = "",
    val recents: List<String> = emptyList(),
    val content: InBookSearchContent = InBookSearchContent.Idle,
) {
    val hidesSearchEntry: Boolean get() = content is InBookSearchContent.Unsupported
}

/**
 * Merge an appended page's [next] groups into the [existing] displayed groups (append-on-scroll): a group whose
 * title matches the LAST existing group coalesces (its hits append), any other new group is appended as-is.
 * Because a page always continues in reading order, only the boundary group can straddle a page split, so
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
