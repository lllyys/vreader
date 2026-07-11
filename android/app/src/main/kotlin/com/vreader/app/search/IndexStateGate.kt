// Purpose: The per-book index-state → in-book-search UI-state gate — feature #133 WI-7. Maps a book's FTS
// index-state row (SearchIndexStateEntity, evaluated at the CURRENT SearchIndexCoordinator.INDEXER_VERSION)
// + its BookFormat + whether it has any matching occurrence into an [InBookIndexState] the ViewModel (WI-8)
// collects. This exists so TXT/MD in-book search never shows a FALSE "no results" while the FTS index is
// still building: a not-yet-settled book is reported as Indexing, not the definitive NoResults.
//
// Key decisions:
// - EPUB BYPASSES the gate entirely. Readium searches the live publication (WI-5); an EPUB book is not in
//   the FTS index, so its state-row presence/absence is IRRELEVANT — EPUB is always Ready and can never
//   enter Indexing. This is the plan's core two-track invariant (EPUB→engine, TXT/MD→FTS).
// - The "still working" predicate MIRRORS SearchIndexCoordinator.isEligible/needsIndexing (do NOT re-derive
//   it differently): a MISSING row, a row at an OLD indexerVersion, or any status that is NOT one of the two
//   SETTLED terminals (`indexed`, `skipped_unsupported`) is still-working. A `failed` row is a special still-
//   working case that surfaces as the retryable Failed state (rather than the generic Indexing) so the caller
//   can offer retry. An unexpected/typo status (`indexing`, `faild`, …) is treated as still-working → Indexing
//   (mirrors the DAO's defensive `NOT IN ('indexed','skipped_unsupported')` completeness predicate).
// - A held query RE-RUNS on settle: observeIndexState is a Flow, so when the coordinator settles the book
//   (Indexing→indexed) the gate re-emits and the ViewModel re-executes the FTS query — a query typed during
//   Indexing yields results (or the definitive NoResults) once the index completes, with no manual re-type.
//
// @coordinates-with search/SearchIndexCoordinator.kt (the authoritative status vocabulary + version + the
//   isEligible/needsIndexing staleness logic mirrored here), search/InBookSearchRepository.kt (WI-6 — the FTS
//   results path this gate front-runs for TXT/MD), data/SearchDao.kt (observeIndexState, read-only).
package com.vreader.app.search

import com.vreader.app.data.SearchIndexStateEntity
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import vreader.contracts.BookFormat

/**
 * The in-book-search index-state UI gate for one book. Exactly one variant, mapped from the book's FTS
 * index-state row + format + occurrence-presence. The ViewModel (WI-8) drives its UI off this: Ready lets
 * the FTS/engine results flow, Indexing shows a "still building" hint (never a false empty), NoResults shows
 * the definitive empty copy, [Unsupported] hides the Search entry, Failed offers retry.
 */
sealed interface InBookIndexState {
    /** True iff the caller should HIDE the in-book Search entry for this book — only [Unsupported]. */
    val hidesSearchEntry: Boolean

    /** The book is searchable NOW: TXT/MD is settled-`indexed` with ≥1 occurrence, or any EPUB. Results flow. */
    data object Ready : InBookIndexState {
        override val hidesSearchEntry: Boolean get() = false
    }

    /** The FTS index for this TXT/MD book is not yet settled (missing / stale version / in-progress) — show a
     *  "still building" hint, NOT a false NoResults. Re-emits to Ready/NoResults when the index settles. */
    data object Indexing : InBookIndexState {
        override val hidesSearchEntry: Boolean get() = false
    }

    /** The FTS index is settled and this book has ZERO matching occurrences — the DEFINITIVE empty state. */
    data object NoResults : InBookIndexState {
        override val hidesSearchEntry: Boolean get() = false
    }

    /** The format has no in-book search (PDF/AZW3, or a TXT/MD skipped as unsupported) — the caller HIDES the
     *  Search entry for this book. */
    data object Unsupported : InBookIndexState {
        override val hidesSearchEntry: Boolean get() = true
    }

    /** Indexing FAILED for this TXT/MD book — retryable (the coordinator re-attempts a `failed` row). */
    data object Failed : InBookIndexState {
        override val hidesSearchEntry: Boolean get() = false
    }
}

/**
 * Maps a book's index state to an [InBookIndexState] and observes it as a [Flow] so a held query un-gates
 * when the current book settles.
 *
 * @param dispatcher the CoroutineDispatcher the mapping runs on (never hardcode Dispatchers.IO — rule 50 §1).
 *   The mapping is pure/cheap; the dispatcher is injected only for test determinism + consistency with the
 *   rest of the search subsystem.
 */
class IndexStateGate(private val dispatcher: CoroutineDispatcher) {

    /**
     * The observed index-state gate for one book: maps the per-book [indexStateFlow] (the DAO's
     * `observeIndexState` Flow) to [InBookIndexState], re-emitting when the coordinator settles the book so a
     * HELD query re-runs. [hasOccurrence] is queried per emission (it must reflect the CURRENT index — e.g.
     * `matchingChunkCount(bookKey, ftsQuery) > 0`); it is only consulted when the row is settled-`indexed`.
     *
     * EPUB short-circuits to a single [InBookIndexState.Ready] and never subscribes to the FTS flow.
     * `distinctUntilChanged` suppresses duplicate emissions when the row changes but the mapped state does not.
     */
    fun observe(
        format: BookFormat,
        bookKey: String,
        hasOccurrence: suspend () -> Boolean,
        indexStateFlow: Flow<SearchIndexStateEntity?>,
    ): Flow<InBookIndexState> {
        // EPUB bypasses the FTS gate entirely (Readium searches live) — one Ready, no FTS subscription.
        if (!usesFtsIndex(format)) {
            return flowOf(mapNonFts(format))
        }
        return indexStateFlow
            .map { row -> evaluateSuspending(format, row, hasOccurrence) }
            .distinctUntilChanged()
            .flowOn(dispatcher)
    }

    private suspend fun evaluateSuspending(
        format: BookFormat,
        row: SearchIndexStateEntity?,
        hasOccurrence: suspend () -> Boolean,
    ): InBookIndexState = when {
        !usesFtsIndex(format) -> mapNonFts(format)
        row == null -> InBookIndexState.Indexing                     // missing → still working
        row.status == STATUS_FAILED -> InBookIndexState.Failed       // failed (any version) → retryable
        needsReindex(row) -> InBookIndexState.Indexing               // stale version / unexpected status
        row.status == STATUS_SKIPPED_UNSUPPORTED -> InBookIndexState.Unsupported
        row.status == STATUS_INDEXED ->
            if (hasOccurrence()) InBookIndexState.Ready else InBookIndexState.NoResults
        else -> InBookIndexState.Indexing                            // defensive (unreachable after needsReindex)
    }

    companion object {
        // The status vocabulary MIRRORS SearchIndexCoordinator's (whose companion consts are private). Kept in
        // sync with data/SearchEntities.kt's `status` column doc: "indexed" | "skipped_unsupported" | "failed".
        private const val STATUS_INDEXED = "indexed"
        private const val STATUS_SKIPPED_UNSUPPORTED = "skipped_unsupported"
        private const val STATUS_FAILED = "failed"

        /** The two SETTLED terminals at the current version — the completeness set (Gate-2 round-3 HIGH). */
        private val SETTLED_STATUSES = setOf(STATUS_INDEXED, STATUS_SKIPPED_UNSUPPORTED)

        /** Only TXT/MD live in the FTS index; EPUB uses Readium; PDF/AZW3 have no in-book search. */
        private fun usesFtsIndex(format: BookFormat): Boolean =
            format == BookFormat.txt || format == BookFormat.md

        /**
         * A settled `indexed`/`skipped_unsupported` row at an OLD indexerVersion, or ANY non-settled status
         * (an in-progress/typo/unknown row), still needs (re-)indexing — mirrors
         * [SearchIndexCoordinator.isEligible]. NOTE: a `failed` row is caught by the caller BEFORE this (it
         * surfaces as Failed, not Indexing), so this predicate treats it as still-working too, consistently.
         */
        private fun needsReindex(row: SearchIndexStateEntity): Boolean =
            row.indexerVersion != SearchIndexCoordinator.INDEXER_VERSION ||
                row.status !in SETTLED_STATUSES

        /** The non-FTS mapping: EPUB always Ready (Readium live); PDF/AZW3 Unsupported (no in-book search). */
        private fun mapNonFts(format: BookFormat): InBookIndexState =
            if (format == BookFormat.epub) InBookIndexState.Ready else InBookIndexState.Unsupported

        /**
         * Pure, synchronous mapping (no Flow, no suspension) for direct testing + non-observed call sites:
         * (format, row, hasOccurrence-boolean) → [InBookIndexState]. Same decision ladder as
         * [IndexStateGate.observe]. [hasOccurrence] is only consulted for a settled-`indexed` TXT/MD book.
         */
        fun evaluate(
            format: BookFormat,
            row: SearchIndexStateEntity?,
            hasOccurrence: Boolean,
        ): InBookIndexState = when {
            !usesFtsIndex(format) -> mapNonFts(format)
            row == null -> InBookIndexState.Indexing
            row.status == STATUS_FAILED -> InBookIndexState.Failed
            needsReindex(row) -> InBookIndexState.Indexing
            row.status == STATUS_SKIPPED_UNSUPPORTED -> InBookIndexState.Unsupported
            row.status == STATUS_INDEXED ->
                if (hasOccurrence) InBookIndexState.Ready else InBookIndexState.NoResults
            else -> InBookIndexState.Indexing
        }
    }
}
