package com.vreader.app.diagnostics

import java.util.Locale

/**
 * Purpose: Feature #164 WI-5 — the immutable state the diagnostics viewer renders, plus the two
 * vocabularies it is expressed in: the designed level-filter chips ([DiagnosticsLevelFilter]) and
 * the content states the design draws ([DiagnosticsContent]).
 *
 * Key decisions:
 * - **Everything derivable is a computed property, not a constructor field.** [content],
 *   [isFiltering], [filterDescriptor] and [footerScope] are pure functions of the stored counts and
 *   filters, so a ViewModel cannot publish a state whose footer disagrees with its own numbers.
 *   The ViewModel supplies facts; this type supplies the grammar.
 * - **The footer has THREE grammars, not two** (`vreader-diagnostics.jsx:484`). Unfiltered reads
 *   `"<N> entries · <scope>"`; filtered-with-results reads `"Showing X of N · <descriptor>"`;
 *   FILTERED-EMPTY reads `"0 of N entries"` — a distinct sentence, not the second one with a zero
 *   in it. iOS ships only the first two because #96's design predates the F3 artboard.
 * - **The capture-scope word is never re-typed here.** It is
 *   [DiagnosticsLogStore.CAPTURE_SCOPE_LABEL], the same constant the export header stamps, so the
 *   footer and the exported file can never claim different capture windows.
 * - **`Errors` is a level SET, not a level** (iOS `DiagnosticsLevelFilter.matches` parity): `ASSERT`
 *   rides with `ERROR` so the loudest thing in a bug report is never hidden behind the chip a user
 *   taps to find it.
 * - **`WARN` deliberately matches NO chip but `All`.** Android has six priorities and the design
 *   has three row treatments; folding warnings into `Errors` would paint every one of this app's
 *   production log sites red (they are all `Log.w`). Interim per plan section 6.3, pending the
 *   designed Warn treatment filed as GH #2021 — changing this is a deliberate, test-breaking act.
 * - **Row identity is caller-assigned and POSITIONAL** ([IdentifiedDiagnosticsEntry]). Content-derived
 *   identity collapses byte-identical log lines — which retry loops emit routinely — into one row
 *   that expands and collapses in lockstep.
 *
 * @coordinates-with DiagnosticsViewModel.kt, DiagnosticsDayGrouper.kt, DiagnosticsLogStore.kt,
 *   DiagnosticsCategoryBounding.kt,
 *   `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
 */
data class DiagnosticsUiState(
    /** True while a [DiagnosticsViewModel.load] is in flight. */
    val isLoading: Boolean = false,
    /** True once a load has COMPLETED — distinguishes "empty log" from "not read yet". */
    val hasLoaded: Boolean = false,
    val levelFilter: DiagnosticsLevelFilter = DiagnosticsLevelFilter.ALL,
    /** The active category chip; [DiagnosticsCategoryBounding.ALL] means "no category filter". */
    val categoryFilter: String = DiagnosticsCategoryBounding.ALL,
    /**
     * The level-chip badges. Computed over ALL loaded entries and therefore
     * CATEGORY-INDEPENDENT (iOS parity): a count that moved when a category chip was tapped would
     * tell the user that tapping a filter changed how many errors their device had.
     */
    val levelCounts: Map<DiagnosticsLevelFilter, Int> =
        DiagnosticsLevelFilter.entries.associateWith { 0 },
    /** The bounded chip row from [DiagnosticsCategoryBounding.chips], `All` first. */
    val categoryChips: List<String> = listOf(DiagnosticsCategoryBounding.ALL),
    /** Every loaded entry, before filtering. */
    val totalCount: Int = 0,
    /** Entries passing both filters — the number of rows in [sections]. */
    val visibleCount: Int = 0,
    /** The day-grouped rows, newest day first. */
    val sections: List<DiagnosticsDaySection> = emptyList(),
    /** The expanded row's positional id, or `null` when every row is collapsed. */
    val expandedEntryId: Int? = null,
) {

    /** Whether either chip is narrowing the list — drives filtered-empty vs plain empty. */
    val isFiltering: Boolean
        get() = levelFilter != DiagnosticsLevelFilter.ALL ||
            categoryFilter != DiagnosticsCategoryBounding.ALL

    /**
     * Which of the design's states the body renders.
     *
     * `!hasLoaded` reads as [DiagnosticsContent.Loading] rather than [DiagnosticsContent.Empty]:
     * before the first load completes the viewer knows nothing, and the designed empty state makes
     * the positive claim *"entries appear here automatically"*. Showing it over an unread log would
     * be a falsehood on the most common path (the screen starts its load on first composition).
     */
    val content: DiagnosticsContent
        get() = when {
            isLoading || !hasLoaded -> DiagnosticsContent.Loading
            totalCount == 0 -> DiagnosticsContent.Empty
            visibleCount == 0 -> DiagnosticsContent.FilteredEmpty
            else -> DiagnosticsContent.Entries
        }

    /**
     * The short human label for the active filter in the footer — `"errors"`, `"Persistence"`, or
     * `"Persistence errors"` (design F1/F2, `diagnostics-artboards.jsx:186`/`:190`). `null` when
     * nothing is filtered.
     */
    val filterDescriptor: String?
        get() {
            // `Locale.ROOT`, never the display locale: a Turkish device would otherwise render
            // "Info" as "ınfo" (dotless i) in an English sentence.
            val level = levelFilter.takeIf { it != DiagnosticsLevelFilter.ALL }
                ?.label?.lowercase(Locale.ROOT)
            val category = categoryFilter.takeIf { it != DiagnosticsCategoryBounding.ALL }
            return when {
                level != null && category != null -> "$category $level"
                level != null -> level
                else -> category
            }
        }

    /** The footer's left-hand scope line — one of the three designed grammars. */
    val footerScope: String
        get() = when {
            !isFiltering ->
                "$totalCount ${entriesNoun(totalCount)} · ${DiagnosticsLogStore.CAPTURE_SCOPE_LABEL}"
            visibleCount == 0 -> "0 of $totalCount ${entriesNoun(totalCount)}"
            else -> "Showing $visibleCount of $totalCount" +
                (filterDescriptor?.let { " · $it" } ?: "")
        }

    private fun entriesNoun(count: Int): String = if (count == 1) "entry" else "entries"
}

/**
 * The four level chips the design draws (`DiagFilterBar`, `vreader-diagnostics.jsx:216-221`), in
 * their designed order.
 */
enum class DiagnosticsLevelFilter(val label: String) {
    ALL("All"),
    ERRORS("Errors"),
    DEBUG("Debug"),
    INFO("Info");

    /**
     * Whether an entry of [level] passes this chip.
     *
     * `ERRORS` is a SET — `ASSERT` (logcat `F`) rides with `ERROR`. `WARN` matches [ALL] only; see
     * this file's header and plan section 6.3 (GH #2021).
     */
    fun matches(level: DiagnosticsLevel): Boolean = when (this) {
        ALL -> true
        ERRORS -> level == DiagnosticsLevel.ERROR || level == DiagnosticsLevel.ASSERT
        DEBUG -> level == DiagnosticsLevel.VERBOSE || level == DiagnosticsLevel.DEBUG
        INFO -> level == DiagnosticsLevel.INFO
    }
}

/** The viewer's body state (`DiagLogViewer`'s `default | loading | empty | filtered-empty`). */
sealed interface DiagnosticsContent {
    /** Reading the log store, or not read yet. */
    data object Loading : DiagnosticsContent

    /** The capture window held nothing at all. */
    data object Empty : DiagnosticsContent

    /** Entries exist, but the active filters select none — the "Clear filters" state. */
    data object FilteredEmpty : DiagnosticsContent

    /** Rows to render. */
    data object Entries : DiagnosticsContent
}

/**
 * One entry paired with a STABLE, caller-assigned identity for the list.
 *
 * [id] is the entry's POSITION in the filtered list, never anything derived from its content: two
 * byte-identical entries must expand independently, and `DiagnosticsLogEntry` is a data class whose
 * equality/hash would make them indistinguishable.
 */
data class IdentifiedDiagnosticsEntry(val id: Int, val entry: DiagnosticsLogEntry)
