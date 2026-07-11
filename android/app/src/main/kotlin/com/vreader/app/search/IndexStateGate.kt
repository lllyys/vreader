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
// - The staleness predicate MIRRORS SearchIndexCoordinator.isEligible EXACTLY (do NOT re-derive it
//   differently): a book is (re-)indexed — and therefore WILL settle → Indexing — iff its row is MISSING or
//   at an OLD indexerVersion. AT THE CURRENT VERSION the coordinator retries ONLY a `failed` row; a
//   current-version `indexed`/`skipped_unsupported` row is settled. Consequences:
//     · current-version `failed` → Failed (retryable — the coordinator re-attempts it).
//     · current-version `indexed` → Ready (≥1 occurrence) or NoResults (0 occurrences, definitive).
//     · current-version `skipped_unsupported` → Unsupported (hide the Search entry).
//     · current-version UNEXPECTED status (`indexing`, `faild`, a typo) → Failed, NOT Indexing. The
//       coordinator does NOT retry a current-version non-`failed` status, so such a row NEVER settles;
//       reporting Indexing would spin the UI forever. Failed is the recoverable terminal the user retries
//       from. (A STALE-version row of ANY status IS re-indexed → Indexing, since the version check dominates.)
// - A held query RE-RUNS on settle: observeIndexState is a Flow, so when the coordinator settles the book
//   (Indexing→indexed) the gate re-emits and the ViewModel re-executes the FTS query — a query typed during
//   Indexing yields results (or the definitive NoResults) once the index completes, with no manual re-type.
//
// @coordinates-with search/SearchIndexCoordinator.kt (the authoritative status vocabulary + INDEXER_VERSION
//   + the isEligible staleness logic mirrored here), search/InBookSearchRepository.kt (WI-6 — the FTS
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
        // Non-FTS formats bypass the gate entirely (EPUB searches Readium live; PDF/AZW3 have no in-book
        // search) — one mapped state, NO subscription to the FTS index-state flow, no occurrence check.
        if (!usesFtsIndex(format)) {
            return flowOf(evaluate(format, row = null, hasOccurrence = false))
        }
        return indexStateFlow
            .map { row -> evaluateSuspending(format, row, hasOccurrence) }
            .distinctUntilChanged()
            .flowOn(dispatcher)
    }

    /**
     * The observed mapping: consults [hasOccurrence] LAZILY and ONLY when the ladder needs it (a settled-
     * `indexed` TXT/MD row), so a missing/stale/failed/skipped/unexpected row never triggers an occurrence
     * query. Delegates the non-occurrence ladder to [classify]; the ONE occurrence-dependent case
     * (`indexed`) is resolved here, keeping a single source of truth for the decision order.
     */
    private suspend fun evaluateSuspending(
        format: BookFormat,
        row: SearchIndexStateEntity?,
        hasOccurrence: suspend () -> Boolean,
    ): InBookIndexState = when (classify(format, row)) {
        Classification.NeedsOccurrenceCheck ->
            if (hasOccurrence()) InBookIndexState.Ready else InBookIndexState.NoResults
        Classification.Ready -> InBookIndexState.Ready
        Classification.Indexing -> InBookIndexState.Indexing
        Classification.Unsupported -> InBookIndexState.Unsupported
        Classification.Failed -> InBookIndexState.Failed
    }

    companion object {
        // The status vocabulary MIRRORS SearchIndexCoordinator's (whose companion consts are private). Kept in
        // sync with data/SearchEntities.kt's `status` column doc: "indexed" | "skipped_unsupported" | "failed".
        private const val STATUS_INDEXED = "indexed"
        private const val STATUS_SKIPPED_UNSUPPORTED = "skipped_unsupported"
        private const val STATUS_FAILED = "failed"

        /** Only TXT/MD live in the FTS index; EPUB uses Readium; PDF/AZW3 have no in-book search. */
        private fun usesFtsIndex(format: BookFormat): Boolean =
            format == BookFormat.txt || format == BookFormat.md

        /** Intermediate classification decoupling the row→state ladder from the occurrence check, so the
         *  observed (lazy suspend) and pure (eager boolean) entry points share ONE decision order. */
        private enum class Classification { Ready, Indexing, Unsupported, Failed, NeedsOccurrenceCheck }

        /**
         * The decision LADDER (occurrence-independent), a faithful mirror of
         * [SearchIndexCoordinator.isEligible]:
         *  - non-FTS: EPUB → Ready (Readium searches live — bypass); PDF/AZW3 → Unsupported.
         *  - missing row → Indexing (the coordinator WILL index it → it will settle).
         *  - STALE indexerVersion (any status) → Indexing (the coordinator WILL re-index → it will settle).
         *  - current-version `failed` → Failed (the coordinator RETRIES it; also a recoverable terminal).
         *  - current-version `skipped_unsupported` → Unsupported (settled — hide the Search entry).
         *  - current-version `indexed` → [NeedsOccurrenceCheck] (Ready iff ≥1 occurrence, else NoResults).
         *  - current-version UNEXPECTED status (`indexing`, typo, …) → Failed, NOT Indexing. CRITICAL
         *    (Gate-4 High): the coordinator's `isEligible` does NOT retry a current-version non-`failed`
         *    status, so such a row NEVER settles — mapping it to Indexing would spin the UI forever waiting
         *    for an emission that can't come. Failed is the recoverable terminal the user can retry from.
         */
        private fun classify(format: BookFormat, row: SearchIndexStateEntity?): Classification = when {
            !usesFtsIndex(format) ->
                if (format == BookFormat.epub) Classification.Ready else Classification.Unsupported
            row == null -> Classification.Indexing
            row.indexerVersion != SearchIndexCoordinator.INDEXER_VERSION -> Classification.Indexing
            row.status == STATUS_FAILED -> Classification.Failed
            row.status == STATUS_SKIPPED_UNSUPPORTED -> Classification.Unsupported
            row.status == STATUS_INDEXED -> Classification.NeedsOccurrenceCheck
            else -> Classification.Failed   // current-version unexpected status → recoverable terminal, never Indexing
        }

        /**
         * Pure, synchronous mapping (no Flow, no suspension) for direct testing + non-observed call sites:
         * (format, row, hasOccurrence-boolean) → [InBookIndexState]. Same [classify] ladder as
         * [IndexStateGate.observe]. [hasOccurrence] is only consulted for a settled-`indexed` TXT/MD book.
         */
        fun evaluate(
            format: BookFormat,
            row: SearchIndexStateEntity?,
            hasOccurrence: Boolean,
        ): InBookIndexState = when (classify(format, row)) {
            Classification.NeedsOccurrenceCheck ->
                if (hasOccurrence) InBookIndexState.Ready else InBookIndexState.NoResults
            Classification.Ready -> InBookIndexState.Ready
            Classification.Indexing -> InBookIndexState.Indexing
            Classification.Unsupported -> InBookIndexState.Unsupported
            Classification.Failed -> InBookIndexState.Failed
        }
    }
}
