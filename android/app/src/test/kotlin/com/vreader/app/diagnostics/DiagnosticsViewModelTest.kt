package com.vreader.app.diagnostics

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneId
import java.util.Locale

/**
 * Feature #164 WI-5 — [DiagnosticsViewModel]: the filter / compose / group / label layer between
 * WI-4's [DiagnosticsLogStore] and WI-6's Compose surfaces.
 *
 * This suite is the CONTRACT the viewer renders against, so it pins the exact user-visible strings
 * (footer grammars, day headers) as well as the behaviour. Three defects it exists to catch, each of
 * which a naive implementation passes every other test with:
 *
 *  * the "Errors" chip narrowed to `{ERROR}` — `ASSERT` would silently vanish from a bug report;
 *  * chip counts recomputed from the FILTERED list — correct while unfiltered, wrong the instant a
 *    category chip is tapped;
 *  * expanded-row identity derived from entry CONTENT — two byte-identical log lines (common) would
 *    expand and collapse as one row.
 *
 * The store is REAL throughout (only the [DiagnosticsLogSource] behind it is faked), so the level
 * set, the category bounding and the export text are exercised through the shipping code path.
 */
class DiagnosticsViewModelTest {

    // ── fixtures ────────────────────────────────────────────────────────────────────────────────

    private val zone: ZoneId = ZoneId.of("America/New_York")
    private val today = "2026-06-10"

    private fun at(local: String): Long =
        LocalDateTime.parse(local).atZone(zone).toInstant().toEpochMilli()

    private val now = at("2026-06-10T20:00:00")

    private fun entry(
        time: String,
        level: DiagnosticsLevel,
        category: String,
        message: String = "entry $time",
    ) = DiagnosticsLogEntry(at(time), level, category, message)

    /** One entry per level, spread over three categories — the workhorse fixture. */
    private val sixLevels = listOf(
        entry("2026-06-10T09:00:00", DiagnosticsLevel.VERBOSE, "Library", "verbose library line"),
        entry("2026-06-10T10:00:00", DiagnosticsLevel.DEBUG, "Persistence", "debug persistence line"),
        entry("2026-06-10T11:00:00", DiagnosticsLevel.INFO, "Sync", "info sync line"),
        entry("2026-06-10T12:00:00", DiagnosticsLevel.WARN, "Library", "warn library line"),
        entry("2026-06-10T13:00:00", DiagnosticsLevel.ERROR, "Persistence", "error persistence line"),
        entry("2026-06-10T14:00:00", DiagnosticsLevel.ASSERT, "AI", "assert ai line"),
    )

    private class FakeSource(
        private val entries: List<DiagnosticsLogEntry>,
        private val failWith: Throwable? = null,
        private val gate: CompletableDeferred<Unit>? = null,
        private val entered: CompletableDeferred<Unit>? = null,
    ) : DiagnosticsLogSource {
        override suspend fun recentEntries(sinceMillis: Long?, limit: Int): SourceResult {
            entered?.complete(Unit)
            gate?.await()
            failWith?.let { throw it }
            return SourceResult.Available(entries)
        }
    }

    /** An `Error`, so [DiagnosticsLogStore]'s `catch (Exception)` containment does NOT swallow it. */
    private class CaptureStackFailure : Error("simulated non-containable capture failure")

    private fun viewModel(
        entries: List<DiagnosticsLogEntry> = sixLevels,
        source: DiagnosticsLogSource = FakeSource(entries),
        nowMillis: Long = now,
        locale: Locale = Locale.ENGLISH,
    ) = DiagnosticsViewModel(
        store = DiagnosticsLogStore(source),
        clock = { nowMillis },
        zone = { zone },
        locale = { locale },
    )

    private suspend fun loaded(
        entries: List<DiagnosticsLogEntry> = sixLevels,
        locale: Locale = Locale.ENGLISH,
    ): DiagnosticsViewModel = viewModel(entries = entries, locale = locale).also { it.load() }

    private fun DiagnosticsViewModel.visibleEntries(): List<DiagnosticsLogEntry> =
        state.value.sections.flatMap { section -> section.entries.map { it.entry } }

    private fun DiagnosticsViewModel.visibleLevels(): Set<DiagnosticsLevel> =
        visibleEntries().map { it.level }.toSet()

    // ── level filtering (design chips All / Errors / Debug / Info) ───────────────────────────────

    @Test
    fun errorsChipMatchesTheErrorAndAssertSet_neverJustError() = runTest {
        val vm = loaded()
        vm.selectLevel(DiagnosticsLevelFilter.ERRORS)

        // iOS parity: the Errors chip is a level SET (`DiagnosticsLevelFilter.matches` includes
        // `.fault`). Dropping ASSERT hides the loudest thing a bug report can contain.
        assertEquals(setOf(DiagnosticsLevel.ERROR, DiagnosticsLevel.ASSERT), vm.visibleLevels())
        assertEquals(2, vm.state.value.visibleCount)
    }

    @Test
    fun debugChipMatchesVerboseAndDebug() = runTest {
        val vm = loaded()
        vm.selectLevel(DiagnosticsLevelFilter.DEBUG)
        assertEquals(setOf(DiagnosticsLevel.VERBOSE, DiagnosticsLevel.DEBUG), vm.visibleLevels())
    }

    @Test
    fun infoChipMatchesInfoAlone() = runTest {
        val vm = loaded()
        vm.selectLevel(DiagnosticsLevelFilter.INFO)
        assertEquals(setOf(DiagnosticsLevel.INFO), vm.visibleLevels())
    }

    @Test
    fun allChipMatchesEverySeverity() = runTest {
        val vm = loaded()
        assertEquals(DiagnosticsLevelFilter.ALL, vm.state.value.levelFilter)
        assertEquals(DiagnosticsLevel.entries.toSet(), vm.visibleLevels())
    }

    @Test
    fun warnIsReachableOnlyUnderAll() = runTest {
        // Plan section 6.3's INTERIM, pending the filed WARN design (GH #2021): warn-level entries
        // are not folded into any designed chip, so they surface under `All` only. Asserted
        // explicitly so moving to `{WARN, ERROR, ASSERT}` is a deliberate, test-breaking decision
        // rather than a silent drift. (The debug ROW TREATMENT for those entries is WI-6a's
        // `DiagnosticsLevelStyle`; this layer decides reachability, not colour.)
        val vm = loaded()
        assertTrue(DiagnosticsLevel.WARN in vm.visibleLevels())

        for (filter in DiagnosticsLevelFilter.entries - DiagnosticsLevelFilter.ALL) {
            vm.selectLevel(filter)
            assertFalse("WARN must not be reachable under $filter", DiagnosticsLevel.WARN in vm.visibleLevels())
        }
    }

    @Test
    fun theErrorsCountDoesNotInflateWithWarnings() = runTest {
        // Every one of this app's six production log sites is `Log.w`; counting warnings as errors
        // would paint the whole screen red for routine handled conditions (plan section 6.3).
        val vm = loaded()
        assertEquals(2, vm.state.value.levelCounts[DiagnosticsLevelFilter.ERRORS])
    }

    // ── counts + composition ────────────────────────────────────────────────────────────────────

    @Test
    fun chipCountsCoverEveryLoadedEntry() = runTest {
        val counts = loaded().state.value.levelCounts
        assertEquals(6, counts[DiagnosticsLevelFilter.ALL])
        assertEquals(2, counts[DiagnosticsLevelFilter.ERRORS])
        assertEquals(2, counts[DiagnosticsLevelFilter.DEBUG])
        assertEquals(1, counts[DiagnosticsLevelFilter.INFO])
    }

    @Test
    fun chipCountsAreCategoryIndependent() = runTest {
        val vm = loaded()
        val unfiltered = vm.state.value.levelCounts

        vm.selectCategory("Persistence")

        // The naive implementation recomputes counts from the FILTERED list — right while
        // unfiltered, wrong the moment a category chip is active (iOS parity: counts are global).
        assertEquals(unfiltered, vm.state.value.levelCounts)
        assertEquals(6, vm.state.value.totalCount)
        assertEquals(2, vm.state.value.visibleCount)
    }

    @Test
    fun chipCountsAreAlsoIndependentOfTheActiveLevelChip() = runTest {
        val vm = loaded()
        val unfiltered = vm.state.value.levelCounts
        vm.selectLevel(DiagnosticsLevelFilter.INFO)
        assertEquals(unfiltered, vm.state.value.levelCounts)
    }

    @Test
    fun levelAndCategoryFiltersCompose() = runTest {
        val vm = loaded()
        vm.selectCategory("Persistence")
        vm.selectLevel(DiagnosticsLevelFilter.ERRORS)

        assertEquals(listOf("error persistence line"), vm.visibleEntries().map { it.message })
    }

    @Test
    fun categoryFilteringGoesThroughTheChipBounding_soCollapsedTagsStayReachable() = runTest {
        // WI-3's bounding maps a raw framework tag onto a designed chip; filtering must follow the
        // SAME mapping or an entry becomes reachable only under `All`.
        val vm = loaded(
            listOf(
                entry("2026-06-10T09:00:00", DiagnosticsLevel.INFO, "SQLiteLog", "mapped to Persistence"),
                entry("2026-06-10T10:00:00", DiagnosticsLevel.INFO, "SomeVendorTag", "collapsed to the bucket"),
                entry("2026-06-10T11:00:00", DiagnosticsLevel.INFO, "Reader", "designed tag"),
            ),
        )

        vm.selectCategory("Persistence")
        assertEquals(listOf("mapped to Persistence"), vm.visibleEntries().map { it.message })

        vm.selectCategory(DiagnosticsCategoryBounding.COLLAPSED_BUCKET)
        assertEquals(listOf("collapsed to the bucket"), vm.visibleEntries().map { it.message })
    }

    @Test
    fun theCategoryChipRowIsAllFirstAndBounded() = runTest {
        val state = loaded().state.value
        assertEquals(DiagnosticsCategoryBounding.ALL, state.categoryChips.first())
        assertTrue(state.categoryChips.size <= DiagnosticsCategoryBounding.MAX_CATEGORY_CHIPS + 1)
        assertEquals(setOf("Library", "Persistence", "Sync", "AI"), state.categoryChips.drop(1).toSet())
    }

    // ── content states ──────────────────────────────────────────────────────────────────────────

    @Test
    fun beforeTheFirstLoadTheContentIsLoading() {
        assertEquals(DiagnosticsContent.Loading, viewModel().state.value.content)
        assertFalse(viewModel().state.value.hasLoaded)
    }

    @Test
    fun anEmptyIntersectionIsFilteredEmpty_notPlainEmpty() = runTest {
        val vm = loaded()
        vm.selectCategory("Persistence")
        vm.selectLevel(DiagnosticsLevelFilter.INFO)

        assertEquals(DiagnosticsContent.FilteredEmpty, vm.state.value.content)
        assertEquals(0, vm.state.value.visibleCount)
        assertEquals(6, vm.state.value.totalCount)
    }

    @Test
    fun noEntriesAtAllIsPlainEmpty_evenWithAFilterActive() = runTest {
        val vm = loaded(emptyList())
        assertEquals(DiagnosticsContent.Empty, vm.state.value.content)

        vm.selectLevel(DiagnosticsLevelFilter.ERRORS)
        // Nothing was captured, so there is no filter to clear — the plain empty state is the truth.
        assertEquals(DiagnosticsContent.Empty, vm.state.value.content)
    }

    @Test
    fun aNonEmptyResultIsTheEntriesState() = runTest {
        assertEquals(DiagnosticsContent.Entries, loaded().state.value.content)
        assertTrue(loaded().state.value.hasLoaded)
    }

    @Test
    fun clearFiltersRestoresBothChipsAndCollapsesTheExpandedRow() = runTest {
        val vm = loaded()
        vm.selectCategory("Persistence")
        vm.selectLevel(DiagnosticsLevelFilter.ERRORS)
        vm.toggleExpanded(0)

        vm.clearFilters()

        assertEquals(DiagnosticsLevelFilter.ALL, vm.state.value.levelFilter)
        assertEquals(DiagnosticsCategoryBounding.ALL, vm.state.value.categoryFilter)
        assertFalse(vm.state.value.isFiltering)
        assertNull(vm.state.value.expandedEntryId)
    }

    // ── expanded-row identity ───────────────────────────────────────────────────────────────────

    @Test
    fun byteIdenticalEntriesExpandIndependently() = runTest {
        // Duplicate log lines are ordinary (a retry loop logs the same string). Content-derived
        // identity would make tapping one expand BOTH — a visible defect this pins.
        val duplicate = entry("2026-06-10T09:00:00", DiagnosticsLevel.INFO, "Library", "same line")
        val vm = loaded(listOf(duplicate, duplicate.copy()))
        assertEquals(duplicate, duplicate.copy())

        val ids = vm.state.value.sections.flatMap { section -> section.entries.map { it.id } }
        assertEquals(2, ids.toSet().size)

        vm.toggleExpanded(ids.first())
        assertEquals(ids.first(), vm.state.value.expandedEntryId)
        assertNotEquals(ids.last(), vm.state.value.expandedEntryId)
    }

    @Test
    fun rowIdentityIsThePositionInTheFilteredList() = runTest {
        val vm = loaded()
        val ids = vm.state.value.sections.flatMap { section -> section.entries.map { it.id } }
        assertEquals(sixLevels.indices.toList(), ids.sorted())
    }

    @Test
    fun toggingAnExpandedRowCollapsesIt() = runTest {
        val vm = loaded()
        vm.toggleExpanded(2)
        assertEquals(2, vm.state.value.expandedEntryId)
        vm.toggleExpanded(2)
        assertNull(vm.state.value.expandedEntryId)
    }

    @Test
    fun changingTheLevelFilterResetsTheExpandedRow() = runTest {
        val vm = loaded()
        vm.toggleExpanded(1)
        vm.selectLevel(DiagnosticsLevelFilter.ERRORS)
        // Ids are positional, so a stale id would point at an unrelated row after re-filtering.
        assertNull(vm.state.value.expandedEntryId)
    }

    @Test
    fun changingTheCategoryFilterResetsTheExpandedRow() = runTest {
        val vm = loaded()
        vm.toggleExpanded(1)
        vm.selectCategory("Persistence")
        assertNull(vm.state.value.expandedEntryId)
    }

    @Test
    fun reselectingTheSameFilterLeavesTheExpandedRowAlone() = runTest {
        val vm = loaded()
        vm.selectLevel(DiagnosticsLevelFilter.ERRORS)
        vm.toggleExpanded(0)

        vm.selectLevel(DiagnosticsLevelFilter.ERRORS)
        vm.selectCategory(DiagnosticsCategoryBounding.ALL)

        assertEquals(0, vm.state.value.expandedEntryId)
    }

    // ── footer: THREE designed grammars (`vreader-diagnostics.jsx:484`) ─────────────────────────

    @Test
    fun theUnfilteredFooterSingleSourcesTheCaptureScopeLabel() = runTest {
        val footer = loaded().state.value.footerScope

        // The scope word is NOT re-typed here: it comes from the same constant the export header
        // uses, so the two can never drift (the design's illustrative "last 24 h" is a window we do
        // not control — see the plan's capture-scope divergence).
        assertEquals("6 entries · ${DiagnosticsLogStore.CAPTURE_SCOPE_LABEL}", footer)
        assertFalse(footer.contains("last 24 h"))
    }

    @Test
    fun theUnfilteredFooterAgreesWithTheEntryCountInNumber() = runTest {
        val one = loaded(listOf(sixLevels.first())).state.value.footerScope
        assertEquals("1 entry · ${DiagnosticsLogStore.CAPTURE_SCOPE_LABEL}", one)

        val none = loaded(emptyList()).state.value.footerScope
        assertEquals("0 entries · ${DiagnosticsLogStore.CAPTURE_SCOPE_LABEL}", none)
    }

    @Test
    fun theFilteredFooterShowsTheLevelDescriptor() = runTest {
        val vm = loaded()
        vm.selectLevel(DiagnosticsLevelFilter.ERRORS)
        assertEquals("Showing 2 of 6 · errors", vm.state.value.footerScope)
    }

    @Test
    fun theFilteredFooterShowsTheCategoryDescriptor() = runTest {
        val vm = loaded()
        vm.selectCategory("Persistence")
        assertEquals("Showing 2 of 6 · Persistence", vm.state.value.footerScope)
    }

    @Test
    fun theFilteredFooterCombinesCategoryThenLevel() = runTest {
        val vm = loaded()
        vm.selectCategory("Persistence")
        vm.selectLevel(DiagnosticsLevelFilter.ERRORS)
        assertEquals("Showing 1 of 6 · Persistence errors", vm.state.value.footerScope)
    }

    @Test
    fun theFilteredEmptyFooterUsesItsOwnGrammar() = runTest {
        val vm = loaded()
        vm.selectCategory("Persistence")
        vm.selectLevel(DiagnosticsLevelFilter.INFO)

        // A DISTINCT third format, not "Showing 0 of 6 · Persistence info".
        assertEquals("0 of 6 entries", vm.state.value.footerScope)
        assertEquals(DiagnosticsContent.FilteredEmpty, vm.state.value.content)
    }

    @Test
    fun theFilteredEmptyFooterAgreesWithTheTotalInNumber() = runTest {
        val vm = loaded(listOf(sixLevels[2]))   // one INFO entry
        vm.selectLevel(DiagnosticsLevelFilter.ERRORS)
        assertEquals("0 of 1 entry", vm.state.value.footerScope)
    }

    // ── export ──────────────────────────────────────────────────────────────────────────────────

    @Test
    fun theExportFileNameCarriesTheInjectedClocksLocalDate() = runTest {
        assertEquals("vreader-log-$today.txt", loaded().exportFileName())
    }

    @Test
    fun theExportFileNameStaysAsciiUnderANonGregorianLocale() = runTest {
        // A locale-sensitive formatter would emit Buddhist-era years or non-ASCII digits into a
        // FILENAME. The date stamp is machine-facing and must not follow the display locale.
        val vm = loaded(locale = Locale.forLanguageTag("th-TH-u-ca-buddhist-nu-thai"))
        assertEquals("vreader-log-$today.txt", vm.exportFileName())
    }

    @Test
    fun theExportFileNameFollowsTheInjectedZone() = runTest {
        // 2026-06-10T23:30 New York is already 11 June in UTC; the stamp is the user's local day.
        val vm = viewModel(nowMillis = at("2026-06-10T23:30:00")).also { it.load() }
        assertEquals("vreader-log-2026-06-10.txt", vm.exportFileName())
    }

    @Test
    fun theExportTextIsNarrowedToTheActiveFilter() = runTest {
        val vm = loaded()
        vm.selectLevel(DiagnosticsLevelFilter.ERRORS)

        val text = vm.exportText()
        assertTrue(text.contains("error persistence line"))
        assertTrue(text.contains("assert ai line"))     // the Errors chip is a SET
        assertFalse(text.contains("info sync line"))
        assertTrue(text.startsWith("vreader diagnostics — 2 entries (${DiagnosticsLogStore.CAPTURE_SCOPE_LABEL})"))
    }

    // ── loading ─────────────────────────────────────────────────────────────────────────────────

    @Test
    fun isLoadingIsTrueAcrossTheAwaitAndFalseAfterwards() = runTest {
        val entered = CompletableDeferred<Unit>()
        val gate = CompletableDeferred<Unit>()
        val vm = viewModel(source = FakeSource(sixLevels, gate = gate, entered = entered))

        assertFalse(vm.state.value.isLoading)
        val job = launch { vm.load() }
        entered.await()

        assertTrue(vm.state.value.isLoading)
        assertEquals(DiagnosticsContent.Loading, vm.state.value.content)

        gate.complete(Unit)
        job.join()

        assertFalse(vm.state.value.isLoading)
        assertEquals(DiagnosticsContent.Entries, vm.state.value.content)
    }

    @Test
    fun isLoadingIsClearedWhenTheLoadThrows() {
        // NOT `runTest`: `assertThrows` takes a non-suspending block, and the fake fails eagerly so
        // `runBlocking` cannot stall. An `Error` is used deliberately — `DiagnosticsLogStore`
        // contains `Exception`, so only a non-containable throwable actually reaches the caller.
        val vm = viewModel(source = FakeSource(emptyList(), failWith = CaptureStackFailure()))

        assertThrows(CaptureStackFailure::class.java) { runBlocking { vm.load() } }

        assertFalse(vm.state.value.isLoading)
        // The load did NOT complete, so the viewer has not "loaded an empty log" — claiming it had
        // would render the designed empty state over a capture stack that never answered.
        assertFalse(vm.state.value.hasLoaded)
    }

    @Test
    fun aSecondLoadReplacesTheEntriesRatherThanAppending() = runTest {
        val vm = loaded()
        assertEquals(6, vm.state.value.totalCount)
        vm.load()
        assertEquals(6, vm.state.value.totalCount)
    }

    @Test
    fun aReloadOntoASmallerBatchDropsTheStaleExpandedRow() = runTest {
        // Identities are POSITIONAL, so an id held across a reload can point at an unrelated row —
        // or at no row at all when the new batch is shorter.
        val batches = ArrayDeque(listOf(sixLevels, listOf(sixLevels.first())))
        val vm = viewModel(source = object : DiagnosticsLogSource {
            override suspend fun recentEntries(sinceMillis: Long?, limit: Int) =
                SourceResult.Available(batches.removeFirst())
        })

        vm.load()
        vm.toggleExpanded(5)
        assertEquals(5, vm.state.value.expandedEntryId)

        vm.load()

        assertEquals(1, vm.state.value.totalCount)
        assertNull(vm.state.value.expandedEntryId)
    }

    @Test
    fun overlappingLoadsAreSerialisedAndTheSpinnerOutlastsTheFirstOne() = runTest {
        // `DiagnosticsLogStore` documents that loads are expected to be SINGLE-FLIGHT: its
        // `lastLoadDegraded` is a store-WIDE latch, so two concurrent reads let one batch inherit
        // the other's capture-source verdict — an export that names the wrong provenance.
        val probe = SerialisingProbe(listOf(sixLevels, listOf(sixLevels.first())))
        val vm = viewModel(source = probe)

        val first = launch { vm.load() }
        probe.entered[0].await()

        val second = launch { vm.load() }
        runCurrent()
        // The second read has NOT begun — it is queued behind the first.
        assertEquals(1, probe.startedCount)
        assertTrue(vm.state.value.isLoading)

        probe.gates[0].complete(Unit)
        probe.entered[1].await()
        // The FIRST load's `finally` has already run here; it must not have lowered the spinner
        // while a second load is still in flight.
        assertTrue(vm.state.value.isLoading)

        probe.gates[1].complete(Unit)
        first.join()
        second.join()

        assertEquals(1, probe.maxConcurrent)
        assertFalse(vm.state.value.isLoading)
        assertEquals(1, vm.state.value.totalCount)   // the last-completing load's batch wins
    }

    /** Serves [batches] in order, one gate per call, recording how many reads ever overlapped. */
    private class SerialisingProbe(private val batches: List<List<DiagnosticsLogEntry>>) :
        DiagnosticsLogSource {
        val entered = List(batches.size) { CompletableDeferred<Unit>() }
        val gates = List(batches.size) { CompletableDeferred<Unit>() }
        var startedCount = 0
            private set
        var maxConcurrent = 0
            private set
        private var active = 0

        override suspend fun recentEntries(sinceMillis: Long?, limit: Int): SourceResult {
            val index = startedCount++
            active++
            maxConcurrent = maxOf(maxConcurrent, active)
            entered[index].complete(Unit)
            gates[index].await()
            active--
            return SourceResult.Available(batches[index])
        }
    }

    // ── day sections are the grouper's, wired to the injected clock ─────────────────────────────

    @Test
    fun sectionsUseTheInjectedClockAndZone() = runTest {
        val vm = loaded(
            listOf(
                entry("2026-06-10T09:00:00", DiagnosticsLevel.INFO, "Library"),
                entry("2026-06-09T09:00:00", DiagnosticsLevel.INFO, "Library"),
                entry("2026-06-08T09:00:00", DiagnosticsLevel.INFO, "Library"),
            ),
        )
        assertEquals(
            listOf("Today · 10 June", "Yesterday · 9 June", "8 June"),
            vm.state.value.sections.map { it.header },
        )
    }

    @Test
    fun sectionHeadersFollowTheInjectedLocale() = runTest {
        val vm = loaded(
            listOf(entry("2026-06-08T09:00:00", DiagnosticsLevel.INFO, "Library")),
            locale = Locale.forLanguageTag("th-TH-u-ca-buddhist"),
        )
        assertEquals(listOf("8 มิถุนายน"), vm.state.value.sections.map { it.header })
    }
}
