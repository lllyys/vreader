package com.vreader.app.diagnostics

import androidx.lifecycle.ViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger

/**
 * Purpose: Feature #164 WI-5 — the diagnostics viewer's ViewModel (the iOS
 * `DiagnosticsLogViewModel` analog). Owns the loaded batch, the two active filter chips and the
 * expanded-row identity; publishes the derived [DiagnosticsUiState] the WI-6 Compose surfaces
 * render, and hands the share flow its filtered export payload + filename.
 *
 * iOS parity holds for the filtering, the counts, the positional identity and the export narrowing.
 * THREE Android divergences are deliberate and plan-authorised, not drift: the footer's third
 * (filtered-empty) grammar, which iOS lacks because #96 predates the F3 artboard; category matching
 * through `DiagnosticsCategoryBounding.chipFor`, which exists only on Android; and the state
 * publication shape below.
 *
 * Pipeline: [load] -> [DiagnosticsLogStore.load] -> `loadedEntries` -> filter by level chip AND
 * category chip -> tag each survivor with its POSITION -> [DiagnosticsDayGrouper] -> state.
 *
 * Key decisions:
 * - **State is recomputed synchronously into a `MutableStateFlow`**, not assembled with
 *   `map`/`stateIn`. The plan sketched the `StatsViewModel` shape, but that pattern exists to
 *   flatten a repository FLOW, and this store is a one-shot `suspend load()` — there is nothing to
 *   flatMap. `stateIn(WhileSubscribed)` would additionally leave `state.value` stale until the
 *   screen subscribes, and [load] runs before first composition. The shape used here is the house
 *   `InBookSearchViewModel` (#133) one: private fields + one `publish()`. Derivation is a filter and
 *   a group over a bounded batch, so doing it eagerly costs nothing.
 * - **Filtering lives HERE, not in the store** (iOS parity): the `Errors` chip is a level SET, which
 *   the store's single-batch API cannot express. The export therefore also runs through the filtered
 *   list, so a share emits exactly what is on screen.
 * - **Category filtering goes through `DiagnosticsCategoryBounding.chipFor`**, the same mapping that
 *   built the chip row. Matching the RAW tag instead would leave every collapsed framework entry
 *   reachable only under `All`, contradicting the bounding rule's own promise.
 * - **Counts are computed over `loadedEntries`, never the filtered list.** A chip badge that moved
 *   when another chip was tapped would report a different number of errors depending on what the
 *   user was looking at.
 * - **Row identity is the position in the FILTERED list, and any filter change resets it.** The ids
 *   are only meaningful for one selection, so a stale id would re-open an unrelated row.
 * - **`isLoading` is cleared in a `finally`.** [DiagnosticsLogStore] contains ordinary exceptions,
 *   but `CancellationException` and `Error` propagate by contract; neither may leave the viewer
 *   spinning forever. A throw does not advance `hasLoaded`, so a failed FIRST load leaves the viewer
 *   unloaded rather than claiming an empty capture stack (which would render the designed empty
 *   state's "entries appear here automatically" over a log that was never read); a failed RELOAD
 *   keeps `hasLoaded` true and the previously loaded batch on screen, which is the right outcome —
 *   stale breadcrumbs beat a blank screen.
 * - **The degraded-capture flag is NOT surfaced in the UI here.** `DiagnosticsLogStore`
 *   .`lastLoadDegraded` reaches the user through the export header's `capture source:` line, which
 *   the store already stamps; the viewer's own degraded copy is undesigned and filed as GH #2022
 *   (plan section 6.5b). Inventing it would be a rule-51 violation.
 * - **The export FILENAME formats in `Locale.ROOT`**, not the display locale: it is a machine-facing
 *   stamp, and a locale-sensitive formatter would emit non-ASCII digits or a Buddhist-era year.
 *
 * @coordinates-with DiagnosticsUiState.kt, DiagnosticsDayGrouper.kt, DiagnosticsLogStore.kt,
 *   DiagnosticsCategoryBounding.kt
 */
class DiagnosticsViewModel(
    private val store: DiagnosticsLogStore,
    /** Injected so "Today" and the export stamp are deterministic in tests. */
    private val clock: () -> Long = System::currentTimeMillis,
    /** Injected, and read per recompute so a zone change is picked up on the next publish. */
    private val zone: () -> ZoneId = ZoneId::systemDefault,
    /** Names the month in a day header; never used for the export filename. */
    private val locale: () -> Locale = Locale::getDefault,
) : ViewModel() {

    private var loadedEntries: List<DiagnosticsLogEntry> = emptyList()
    private var levelFilter: DiagnosticsLevelFilter = DiagnosticsLevelFilter.ALL
    private var categoryFilter: String = DiagnosticsCategoryBounding.ALL
    private var expandedEntryId: Int? = null
    private var isLoading: Boolean = false
    private var hasLoaded: Boolean = false

    /** Serialises [load] so the store never sees two concurrent reads (see [load]). */
    private val loadMutex = Mutex()

    /** Outstanding [load] calls — atomic because a caller may suspend on any dispatcher. */
    private val pendingLoads = AtomicInteger(0)

    private val _state = MutableStateFlow(DiagnosticsUiState())

    /** The viewer's whole render input. */
    val state: StateFlow<DiagnosticsUiState> = _state.asStateFlow()

    /**
     * Reads a batch through the store, REPLACING whatever was held. Collapses the expanded row —
     * identities are positional, so a reload invalidates them.
     *
     * Overlapping calls are SERIALISED, never concurrent: [DiagnosticsLogStore] documents that its
     * `lastLoadDegraded` latch is store-wide and that loads are expected to be single-flight, so two
     * reads in flight at once would let one batch inherit the other's capture-source verdict — a
     * diagnostics export that names the wrong provenance. The queued caller waits on [loadMutex] and
     * the spinner stays up until the LAST outstanding load finishes ([pendingLoads]); the
     * last-completing load's batch is the one on screen.
     */
    suspend fun load(sinceMillis: Long? = null, limit: Int? = null) {
        // The increment is the ONLY statement outside the `try`, and `AtomicInteger` cannot throw:
        // everything that can fail — including the first `publish()`, which calls the injected
        // clock/zone/locale — is inside it, so the count can never leak and strand the spinner.
        pendingLoads.incrementAndGet()
        try {
            isLoading = true
            publish()
            loadMutex.withLock {
                loadedEntries = store.load(sinceMillis, limit)
                hasLoaded = true
                expandedEntryId = null
            }
        } finally {
            // Only the last one out lowers the spinner — an earlier load completing while a later
            // one is still queued must not publish "done".
            isLoading = pendingLoads.decrementAndGet() > 0
            publish()
        }
    }

    /** Taps a level chip. A real change collapses the expanded row; re-tapping the active chip is a no-op. */
    fun selectLevel(filter: DiagnosticsLevelFilter) {
        if (filter == levelFilter) return
        levelFilter = filter
        expandedEntryId = null
        publish()
    }

    /** Taps a category chip ([DiagnosticsCategoryBounding.ALL] clears it). Same reset semantics as [selectLevel]. */
    fun selectCategory(chip: String) {
        if (chip == categoryFilter) return
        categoryFilter = chip
        expandedEntryId = null
        publish()
    }

    /**
     * The filtered-empty state's "Clear filters" action. Unconditional — unlike [selectLevel] it
     * always collapses, because it is a single gesture that resets the whole selection.
     */
    fun clearFilters() {
        levelFilter = DiagnosticsLevelFilter.ALL
        categoryFilter = DiagnosticsCategoryBounding.ALL
        expandedEntryId = null
        publish()
    }

    /** Expands the row with this positional [id], or collapses it if it is already the expanded one. */
    fun toggleExpanded(id: Int) {
        expandedEntryId = if (expandedEntryId == id) null else id
        publish()
    }

    /** The redacted share payload, narrowed to EXACTLY what the active filters show. */
    fun exportText(): String = store.exportText(visibleEntries(), clock())

    /** `vreader-log-YYYY-MM-DD.txt` — the injected clock's date in the injected zone. */
    fun exportFileName(nowMillis: Long = clock()): String =
        "vreader-log-${FILE_DATE.format(Instant.ofEpochMilli(nowMillis).atZone(zone()))}.txt"

    private fun visibleEntries(): List<DiagnosticsLogEntry> =
        loadedEntries.filter { levelFilter.matches(it.level) && matchesCategory(it.category) }

    private fun matchesCategory(rawCategory: String): Boolean =
        categoryFilter == DiagnosticsCategoryBounding.ALL ||
            DiagnosticsCategoryBounding.chipFor(rawCategory) == categoryFilter

    private fun publish() {
        val visible = visibleEntries()
        val identified = visible.mapIndexed { position, entry ->
            IdentifiedDiagnosticsEntry(id = position, entry = entry)
        }
        _state.value = DiagnosticsUiState(
            isLoading = isLoading,
            hasLoaded = hasLoaded,
            levelFilter = levelFilter,
            categoryFilter = categoryFilter,
            // Over loadedEntries, NOT `visible` — the counts are global by design.
            levelCounts = DiagnosticsLevelFilter.entries.associateWith { filter ->
                loadedEntries.count { filter.matches(it.level) }
            },
            categoryChips = DiagnosticsCategoryBounding.chips(loadedEntries),
            totalCount = loadedEntries.size,
            visibleCount = visible.size,
            sections = DiagnosticsDayGrouper.sections(identified, clock(), zone(), locale()),
            expandedEntryId = expandedEntryId,
        )
    }

    private companion object {
        /** `Locale.ROOT`: the filename stamp is machine-facing and must stay ASCII. */
        private val FILE_DATE: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.ROOT)
    }
}
