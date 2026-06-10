// Purpose: Feature #96 WI-2 — DiagnosticsLogViewModel filter state, derived
// lists, chip counts, export, and expand-reset behavior, over a mock source.

import Testing
import Foundation
@testable import vreader

private struct MockDiagnosticsSource: DiagnosticsLogSource {
    var entries: [DiagnosticsLogEntry] = []
    func recentEntries(since: Date?, limit: Int) async throws -> [DiagnosticsLogEntry] {
        Array(entries.suffix(limit))
    }
}

private func entry(_ level: DiagnosticsLevel, _ category: String, _ message: String,
                   at offset: TimeInterval = 0) -> DiagnosticsLogEntry {
    DiagnosticsLogEntry(date: Date(timeIntervalSince1970: 1_700_000_000 + offset),
                        level: level, category: category, message: message)
}

@MainActor
private func loadedViewModel(_ entries: [DiagnosticsLogEntry]) async -> DiagnosticsLogViewModel {
    let store = DiagnosticsLogStore(source: MockDiagnosticsSource(entries: entries))
    let vm = DiagnosticsLogViewModel(store: store)
    await vm.load()
    return vm
}

@MainActor
@Suite("DiagnosticsLogViewModel")
struct DiagnosticsLogViewModelTests {

    private var sample: [DiagnosticsLogEntry] {
        [
            entry(.info, "Library", "opened", at: 0),
            entry(.error, "Persistence", "save failed", at: 1),
            entry(.debug, "Reader", "paginate", at: 2),
            entry(.fault, "Persistence", "corrupt", at: 3),
        ]
    }

    @Test func loadTogglesLoadingAndPopulates() async {
        let vm = await loadedViewModel(sample)
        #expect(vm.hasLoaded)
        #expect(!vm.isLoading)
        #expect(vm.allEntries.count == 4)
    }

    @Test func defaultFilterShowsAll() async {
        let vm = await loadedViewModel(sample)
        #expect(vm.levelFilter == .all)
        #expect(vm.filteredEntries.count == 4)
        #expect(!vm.isFiltering)
    }

    @Test func errorsFilterIncludesFault() async {
        let vm = await loadedViewModel(sample)
        vm.levelFilter = .errors
        #expect(vm.filteredEntries.count == 2)   // error + fault
        #expect(vm.isFiltering)
    }

    @Test func categoryFilterNarrows() async {
        let vm = await loadedViewModel(sample)
        vm.categoryFilter = "Persistence"
        #expect(vm.filteredEntries.count == 2)
        #expect(vm.isFiltering)
    }

    @Test func filtersCompose() async {
        let vm = await loadedViewModel(sample)
        vm.levelFilter = .errors
        vm.categoryFilter = "Persistence"
        #expect(vm.filteredEntries.count == 2)   // both error + fault are Persistence
    }

    @Test func chipCountsAreGlobal() async {
        let vm = await loadedViewModel(sample)
        #expect(vm.count(for: .all) == 4)
        #expect(vm.count(for: .errors) == 2)
        #expect(vm.count(for: .debug) == 1)
        #expect(vm.count(for: .info) == 1)
        // counts ignore the active category filter
        vm.categoryFilter = "Library"
        #expect(vm.count(for: .all) == 4)
    }

    @Test func changingFilterCollapsesExpandedRow() async {
        let vm = await loadedViewModel(sample)
        vm.expandedEntryID = 2
        vm.levelFilter = .errors
        #expect(vm.expandedEntryID == nil)
    }

    @Test func changingCategoryCollapsesExpandedRow() async {
        let vm = await loadedViewModel(sample)
        vm.expandedEntryID = 1
        vm.categoryFilter = "Reader"
        #expect(vm.expandedEntryID == nil)
    }

    @Test func categoriesAreSortedDistinct() async {
        let vm = await loadedViewModel(sample)
        #expect(vm.categories == ["Library", "Persistence", "Reader"])
    }

    @Test func exportFileNameUsesInjectedDate() async {
        let vm = await loadedViewModel(sample)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        #expect(vm.exportFileName(now: date, calendar: cal) == "vreader-log-2026-06-10.txt")
    }

    @Test func exportTextReflectsActiveFilterAndIsRedacted() async {
        let vm = await loadedViewModel([
            entry(.error, "AI", "api_key=sk-abcdef0123456789ABCDEF rejected", at: 0),
            entry(.debug, "Reader", "paginate", at: 1),
        ])
        vm.levelFilter = .errors
        let text = vm.exportText()
        #expect(text.contains("AI"))
        #expect(!text.contains("paginate"))                  // filtered out
        #expect(!text.contains("sk-abcdef0123456789ABCDEF"))  // redacted
    }

    @Test func exportUnderErrorsChipIncludesFault() async {
        // Codex Gate-4 High: the Errors chip = {.error,.fault}; export must
        // include the .fault row, not collapse to .error only.
        let vm = await loadedViewModel(sample)
        vm.levelFilter = .errors
        let text = vm.exportText()
        #expect(text.contains("save failed"))   // the .error row
        #expect(text.contains("corrupt"))        // the .fault row
        #expect(!text.contains("paginate"))      // the .debug row excluded
    }

    @Test func identifiedEntriesAreDistinctForValueEqualRows() async {
        // Codex Gate-4 High: two value-equal entries must get distinct ids so
        // they expand independently in the viewer.
        let dup = entry(.error, "C", "same", at: 5)
        let vm = await loadedViewModel([dup, dup])
        let ids = vm.identifiedEntries.map(\.id)
        #expect(ids == [0, 1])
        #expect(Set(ids).count == 2)
    }

    @Test func footerScopeReflectsFiltering() async {
        let vm = await loadedViewModel(sample)
        #expect(vm.footerScope.contains("4"))
        #expect(vm.footerScope.contains("this session"))
        vm.levelFilter = .errors
        #expect(vm.footerScope == "Showing 2 of 4 · errors")
        vm.categoryFilter = "Persistence"
        #expect(vm.footerScope == "Showing 2 of 4 · Persistence errors")
    }
}
