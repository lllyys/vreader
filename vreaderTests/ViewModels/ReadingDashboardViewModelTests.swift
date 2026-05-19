// Purpose: Tests for ReadingDashboardViewModel — window/sort state, snapshot
// loading, sort persistence, error handling. Feature #58 WI-4.

import Foundation
import Testing
@testable import vreader

@MainActor
@Suite("ReadingDashboardViewModel")
struct ReadingDashboardViewModelTests {

    // MARK: - Test doubles

    /// A mock aggregator that returns a canned snapshot (or throws).
    final class MockAggregator: ReadingStatsAggregating, @unchecked Sendable {
        var snapshotToReturn: ReadingDashboardSnapshot?
        var errorToThrow: Error?
        private(set) var callCount = 0
        private(set) var lastWindow: ReadingStatsWindow?
        private(set) var lastSort: ReadingDashboardSort?

        func snapshot(
            window: ReadingStatsWindow, sort: ReadingDashboardSort, now: Date
        ) async throws -> ReadingDashboardSnapshot {
            callCount += 1
            lastWindow = window
            lastSort = sort
            if let errorToThrow { throw errorToThrow }
            return snapshotToReturn ?? Self.emptySnapshot(activeWindow: window)
        }

        static func emptySnapshot(activeWindow: ReadingStatsWindow) -> ReadingDashboardSnapshot {
            ReadingDashboardSnapshot(
                windowTotals: [], activeWindow: activeWindow, perBook: [],
                lifetimeTotalSeconds: 0, trackingSince: nil
            )
        }
    }

    struct SampleError: Error {}

    private func row(_ key: String, title: String, seconds: Int) -> PerBookStatsRow {
        PerBookStatsRow(
            id: key, bookFingerprintKey: key, title: title, isDeleted: false,
            readingSecondsInWindow: seconds, notesCount: 0, highlightsCount: 0, lastReadAt: nil
        )
    }

    private func snapshot(
        window: ReadingStatsWindow, rows: [PerBookStatsRow], lifetime: Int = 0
    ) -> ReadingDashboardSnapshot {
        ReadingDashboardSnapshot(
            windowTotals: [WindowTotal(window: window, totalSeconds: lifetime, sessionCount: rows.count)],
            activeWindow: window, perBook: rows,
            lifetimeTotalSeconds: lifetime, trackingSince: nil
        )
    }

    // MARK: - Initial load

    @Test func initialLoadPopulatesSnapshot() async {
        let agg = MockAggregator()
        agg.snapshotToReturn = snapshot(
            window: .today, rows: [row("a", title: "Book A", seconds: 100)], lifetime: 100
        )
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: MockPreferenceStore())
        await vm.load()

        #expect(vm.snapshot != nil)
        #expect(vm.snapshot?.perBook.count == 1)
        #expect(vm.errorMessage == nil)
        #expect(agg.callCount == 1)
    }

    @Test func defaultWindowIsTodayAndDefaultSortIsReadingTimeDesc() {
        let vm = ReadingDashboardViewModel(
            aggregator: MockAggregator(), preferenceStore: MockPreferenceStore()
        )
        #expect(vm.activeWindow == .today)
        #expect(vm.sort == ReadingDashboardSort.default)
    }

    // MARK: - Window switching

    @Test func selectingWindowReQueriesAndUpdatesActiveWindow() async {
        let agg = MockAggregator()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: MockPreferenceStore())
        await vm.load()
        #expect(agg.callCount == 1)

        await vm.selectWindow(.last30Days)
        #expect(vm.activeWindow == .last30Days)
        #expect(agg.callCount == 2)
        #expect(agg.lastWindow == .last30Days)
    }

    @Test func selectingTheSameWindowStillReQueries() async {
        // Re-tapping the active window is harmless — it just refreshes.
        let agg = MockAggregator()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: MockPreferenceStore())
        await vm.load()
        await vm.selectWindow(.today)  // same as default
        #expect(vm.activeWindow == .today)
        #expect(agg.callCount == 2)
    }

    // MARK: - Sort

    @Test func changingSortReQueriesWithTheNewSort() async {
        let agg = MockAggregator()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: MockPreferenceStore())
        await vm.load()

        let newSort = ReadingDashboardSort(field: .title, ascending: true)
        await vm.selectSort(newSort)
        #expect(vm.sort == newSort)
        #expect(agg.lastSort == newSort)
        #expect(agg.callCount == 2)
    }

    @Test func changingSortPersistsToPreferenceStore() async {
        let store = MockPreferenceStore()
        let agg = MockAggregator()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: store)
        await vm.load()

        let newSort = ReadingDashboardSort(field: .highlights, ascending: false)
        await vm.selectSort(newSort)
        // Persisted under the documented key, as the storage string.
        #expect(store.string(forKey: ReadingDashboardViewModel.sortKey) == newSort.storageString)
    }

    @Test func sortIsRestoredFromPreferenceStoreAtConstruction() {
        let store = MockPreferenceStore()
        let saved = ReadingDashboardSort(field: .notes, ascending: true)
        store.set(saved.storageString, forKey: ReadingDashboardViewModel.sortKey)

        let vm = ReadingDashboardViewModel(aggregator: MockAggregator(), preferenceStore: store)
        #expect(vm.sort == saved)
    }

    @Test func corruptStoredSortFallsBackToDefault() {
        let store = MockPreferenceStore()
        store.setRaw("garbage:not-a-direction", forKey: ReadingDashboardViewModel.sortKey)

        let vm = ReadingDashboardViewModel(aggregator: MockAggregator(), preferenceStore: store)
        #expect(vm.sort == ReadingDashboardSort.default)
    }

    // MARK: - Error handling

    @Test func aggregatorErrorSurfacesAsErrorMessageWithoutCrashing() async {
        let agg = MockAggregator()
        agg.errorToThrow = SampleError()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: MockPreferenceStore())
        await vm.load()

        #expect(vm.errorMessage != nil)
        #expect(vm.snapshot == nil)
    }

    @Test func errorMessageClearsAfterASuccessfulReload() async {
        let agg = MockAggregator()
        agg.errorToThrow = SampleError()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: MockPreferenceStore())
        await vm.load()
        #expect(vm.errorMessage != nil)

        // Recover: clear the error, return a snapshot.
        agg.errorToThrow = nil
        agg.snapshotToReturn = snapshot(window: .today, rows: [])
        await vm.load()
        #expect(vm.errorMessage == nil)
        #expect(vm.snapshot != nil)
    }
}
