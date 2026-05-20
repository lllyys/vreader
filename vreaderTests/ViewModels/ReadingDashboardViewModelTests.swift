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
        private(set) var lastCustomRange: ReadingStatsCustomRange?

        func snapshot(
            window: ReadingStatsWindow, sort: ReadingDashboardSort, now: Date,
            customRange: ReadingStatsCustomRange?
        ) async throws -> ReadingDashboardSnapshot {
            callCount += 1
            lastWindow = window
            lastSort = sort
            lastCustomRange = customRange
            if let errorToThrow { throw errorToThrow }
            return snapshotToReturn ?? Self.emptySnapshot(activeWindow: window, customRange: customRange)
        }

        static func emptySnapshot(
            activeWindow: ReadingStatsWindow,
            customRange: ReadingStatsCustomRange? = nil
        ) -> ReadingDashboardSnapshot {
            let breakdown: CustomRangeBreakdown? = customRange.map {
                CustomRangeBreakdown(range: $0, totalSeconds: 0, sessionCount: 0)
            }
            return ReadingDashboardSnapshot(
                windowTotals: [], activeWindow: activeWindow, perBook: [],
                lifetimeTotalSeconds: 0, trackingSince: nil,
                customRangeBreakdown: breakdown
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

    // MARK: - Out-of-order refresh (Codex WI-4 audit finding)

    /// An aggregator where each call blocks on a per-call gate the test opens
    /// explicitly — so the test controls completion ordering deterministically.
    actor GatedAggregator: ReadingStatsAggregating {
        private var gates: [ReadingStatsWindow: CheckedContinuation<Void, Never>] = [:]
        private var pending: [ReadingStatsWindow: () -> Void] = [:]

        /// Snapshots are keyed by window so the test can tell which one "won".
        func snapshot(
            window: ReadingStatsWindow, sort: ReadingDashboardSort, now: Date,
            customRange: ReadingStatsCustomRange?
        ) async throws -> ReadingDashboardSnapshot {
            // Block until the test releases this window's gate.
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if let release = pending.removeValue(forKey: window) {
                    // The test already asked to release this window — go now.
                    cont.resume()
                    release()
                } else {
                    gates[window] = cont
                }
            }
            return ReadingDashboardSnapshot(
                windowTotals: [WindowTotal(window: window, totalSeconds: 0, sessionCount: 0)],
                activeWindow: window, perBook: [],
                lifetimeTotalSeconds: window == .today ? 1 : 2, trackingSince: nil
            )
        }

        /// Releases the blocked `snapshot` call for `window` (or arms a release
        /// if the call hasn't reached the gate yet).
        func release(_ window: ReadingStatsWindow) {
            if let cont = gates.removeValue(forKey: window) {
                cont.resume()
            } else {
                pending[window] = {}
            }
        }
    }

    // MARK: - Custom range (feature #58 WI-6b)

    private func sampleRange() -> ReadingStatsCustomRange {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let end   = cal.date(from: DateComponents(year: 2026, month: 5, day: 15))!
        return ReadingStatsCustomRange(start: start, end: end)
    }

    @Test func applyCustomRangeActivatesCustomMode() async {
        let agg = MockAggregator()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: MockPreferenceStore())
        await vm.load()

        #expect(vm.customRange == nil)
        #expect(vm.isCustomActive == false)

        let range = sampleRange()
        await vm.applyCustomRange(range)

        #expect(vm.customRange == range)
        #expect(vm.isCustomActive == true)
        // The aggregator was called WITH the customRange.
        #expect(agg.lastCustomRange == range)
    }

    @Test func selectingAnEnumWindowExitsCustomMode() async {
        let agg = MockAggregator()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: MockPreferenceStore())
        await vm.applyCustomRange(sampleRange())
        #expect(vm.isCustomActive)

        await vm.selectWindow(.last7Days)
        #expect(vm.customRange == nil)
        #expect(vm.activeWindow == .last7Days)
        // The subsequent aggregator call had no custom range.
        #expect(agg.lastCustomRange == nil)
    }

    @Test func clearCustomRangeExitsCustomMode() async {
        let agg = MockAggregator()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: MockPreferenceStore())
        await vm.applyCustomRange(sampleRange())
        #expect(vm.isCustomActive)

        await vm.clearCustomRange()
        #expect(vm.customRange == nil)
        #expect(vm.isCustomActive == false)
    }

    @Test func clearCustomRangeWhenInactiveIsANoOp() async {
        let agg = MockAggregator()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: MockPreferenceStore())
        await vm.load()
        let calls = agg.callCount

        await vm.clearCustomRange()
        // The early-exit guard means no extra aggregator call when there
        // was no Custom range to clear.
        #expect(agg.callCount == calls)
    }

    @Test func customRangePersistsAcrossReinitialization() async {
        let store = MockPreferenceStore()
        let agg = MockAggregator()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: store)
        let range = sampleRange()
        await vm.applyCustomRange(range)

        // A fresh VM with the same store sees the range restored.
        let vm2 = ReadingDashboardViewModel(aggregator: MockAggregator(), preferenceStore: store)
        #expect(vm2.customRange == range)
        #expect(vm2.isCustomActive == true)
    }

    @Test func selectingAnEnumWindowRemovesPersistedCustomRange() async {
        let store = MockPreferenceStore()
        let agg = MockAggregator()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: store)
        await vm.applyCustomRange(sampleRange())
        #expect(store.string(forKey: ReadingDashboardViewModel.customRangeKey) != nil)

        await vm.selectWindow(.last30Days)
        #expect(store.string(forKey: ReadingDashboardViewModel.customRangeKey) == nil)
    }

    @Test func corruptStoredCustomRangeFallsBackToNil() {
        let store = MockPreferenceStore()
        store.setRaw("not-a-json-blob", forKey: ReadingDashboardViewModel.customRangeKey)
        let vm = ReadingDashboardViewModel(aggregator: MockAggregator(), preferenceStore: store)
        #expect(vm.customRange == nil)
    }

    @Test func isCustomPickerPresentedDefaultsToFalse() {
        let vm = ReadingDashboardViewModel(aggregator: MockAggregator(), preferenceStore: MockPreferenceStore())
        #expect(vm.isCustomPickerPresented == false)
    }

    @Test func staleRefreshDoesNotOverwriteANewerSnapshot() async {
        let agg = GatedAggregator()
        let vm = ReadingDashboardViewModel(aggregator: agg, preferenceStore: MockPreferenceStore())

        // Request A (today) starts and blocks on its gate.
        async let requestA: Void = vm.load()
        // Give A a turn to reach the aggregator gate.
        await Task.yield()

        // Request B (last30Days) starts and blocks on its gate.
        async let requestB: Void = vm.selectWindow(.last30Days)
        await Task.yield()

        // Release the NEWER request (B) first, then the older one (A).
        await agg.release(.last30Days)
        _ = await requestB
        await agg.release(.today)
        _ = await requestA

        // The VM must keep B's snapshot — the stale A result is dropped.
        #expect(vm.activeWindow == .last30Days)
        #expect(vm.snapshot?.activeWindow == .last30Days)
    }
}
