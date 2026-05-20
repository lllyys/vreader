// Purpose: Composition tests for ReadingDashboardView — the design's
// `FullStatsDashboard` (`vreader-profile-stats.jsx`). Feature #58 WI-6a.
//
// COMPOSITION assertions, not pixel snapshots: the dashboard wraps
// itself in the `ReaderSheetChrome` "Stats" sheet, composes the
// `StatsTimeWindowBar` + hero total + `StatsPerBookTable`, and the hero
// re-renders when the VM's `activeWindow` changes.
//
// Per the D4-A resolution (GH #665 2026-05-20): one hero serif total +
// the 7-pill bar (NOT 7 simultaneous cards). Per D1-A: presented as a
// sheet from the Settings profile-card Stats button — the
// SettingsView wiring itself ships in feature #67 WI-4 (which is
// hard-blocked on this WI-6a reaching `DONE`). The dashboard view
// renders standalone and exposes its content for testing without a
// SettingsView presenter.

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("ReadingDashboardView composition — feature #58 WI-6a")
@MainActor
struct ReadingDashboardViewTests {

    // MARK: - VM stub

    /// A canned aggregator that returns a deterministic snapshot — no
    /// SwiftData, no ModelContainer. Reuses the same shape as
    /// `ReadingDashboardViewModelTests.MockAggregator` but kept local so
    /// this suite is fully independent.
    final class CannedAggregator: ReadingStatsAggregating, @unchecked Sendable {
        var snapshotToReturn: ReadingDashboardSnapshot

        init(snapshot: ReadingDashboardSnapshot) {
            self.snapshotToReturn = snapshot
        }

        func snapshot(
            window: ReadingStatsWindow, sort: ReadingDashboardSort, now: Date
        ) async throws -> ReadingDashboardSnapshot {
            // Echo the requested window so the VM's selectWindow flow can
            // observe the active window change.
            let totals = snapshotToReturn.windowTotals.isEmpty
                ? [WindowTotal(window: window, totalSeconds: 3600, sessionCount: 1)]
                : snapshotToReturn.windowTotals
            return ReadingDashboardSnapshot(
                windowTotals: totals,
                activeWindow: window,
                perBook: snapshotToReturn.perBook,
                lifetimeTotalSeconds: snapshotToReturn.lifetimeTotalSeconds,
                trackingSince: snapshotToReturn.trackingSince
            )
        }
    }

    private func row(
        _ key: String, title: String, seconds: Int
    ) -> PerBookStatsRow {
        PerBookStatsRow(
            id: key, bookFingerprintKey: key, title: title, isDeleted: false,
            readingSecondsInWindow: seconds, notesCount: 0,
            highlightsCount: 0, lastReadAt: nil
        )
    }

    private func makeViewModel(
        snapshot: ReadingDashboardSnapshot? = nil
    ) -> (ReadingDashboardViewModel, CannedAggregator) {
        let initialSnapshot = snapshot ?? ReadingDashboardSnapshot(
            windowTotals: [
                WindowTotal(window: .today, totalSeconds: 3600, sessionCount: 1)
            ],
            activeWindow: .today,
            perBook: [
                row("pp", title: "Pride and Prejudice", seconds: 1800),
                row("bi", title: "Brief Interviews",    seconds:  900)
            ],
            lifetimeTotalSeconds: 42_000,
            trackingSince: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let agg = CannedAggregator(snapshot: initialSnapshot)
        let vm = ReadingDashboardViewModel(aggregator: agg)
        return (vm, agg)
    }

    private func makeView(viewModel: ReadingDashboardViewModel) -> ReadingDashboardView {
        ReadingDashboardView(viewModel: viewModel, theme: .paper) {}
    }

    // MARK: - Build

    @Test func buildsForEveryReaderTheme() {
        let (vm, _) = makeViewModel()
        for theme in ReaderThemeV2.allCases {
            let view = ReadingDashboardView(viewModel: vm, theme: theme) {}
            _ = view.body
        }
    }

    // MARK: - Sheet title (D1-A: design's "Stats" chrome)

    @Test func sheetTitleMatchesTheDesign() {
        // Pinned to `vreader-profile-stats.jsx` `FullStatsDashboard`:
        // `<Sheet … title="Reading" …>`. The Stats *button* (in
        // `ProfileCardLibrary`) is labelled "Stats"; the *sheet* it opens
        // is titled "Reading" per the design.
        #expect(ReadingDashboardView.sheetTitle == "Reading")
    }

    // MARK: - Hero content (D4-A)

    /// The hero exposes the duration text for the active window — the
    /// design's "ONE large serif total" pattern.
    @Test func heroTextMirrorsActiveWindowTotal() async {
        let snap = ReadingDashboardSnapshot(
            windowTotals: [
                WindowTotal(window: .today,    totalSeconds: 3_600, sessionCount: 1),
                WindowTotal(window: .last7Days, totalSeconds: 25_200, sessionCount: 7)
            ],
            activeWindow: .today,
            perBook: [],
            lifetimeTotalSeconds: 100_000,
            trackingSince: nil
        )
        let (vm, _) = makeViewModel(snapshot: snap)
        await vm.load()
        let view = makeView(viewModel: vm)
        // The hero's duration string matches the formatted active-window
        // total via `ReadingTimeFormatter.formatDuration`.
        #expect(view.heroDurationTextForTesting == ReadingTimeFormatter.formatDuration(totalSeconds: 3_600))
    }

    @Test func heroFallsBackToZeroWhenNoSnapshot() {
        let (vm, _) = makeViewModel()
        // Without calling `load()`, snapshot is nil — the hero shows the
        // zero state via formatDuration(0).
        let view = makeView(viewModel: vm)
        #expect(view.heroDurationTextForTesting == ReadingTimeFormatter.formatDuration(totalSeconds: 0))
    }

    // MARK: - Window-pill flow

    @Test func windowSelectionRoutesThroughViewModel() async {
        let (vm, _) = makeViewModel()
        await vm.load()
        let view = makeView(viewModel: vm)

        view.selectWindowForTesting(.last30Days)
        // VM.selectWindow is async; spin until the activeWindow updates.
        // Using a short polling loop on the @MainActor — no Task.sleep,
        // no background shells. Aggregator is in-memory so this completes
        // in microseconds.
        for _ in 0..<100 where vm.activeWindow != .last30Days {
            await Task.yield()
        }
        #expect(vm.activeWindow == .last30Days)
    }

    // MARK: - Per-book table flow

    @Test func sortSelectionRoutesThroughViewModel() async {
        let (vm, _) = makeViewModel()
        await vm.load()
        let view = makeView(viewModel: vm)

        let newSort = ReadingDashboardSort(field: .title, ascending: true)
        view.selectSortForTesting(newSort)
        for _ in 0..<100 where vm.sort != newSort {
            await Task.yield()
        }
        #expect(vm.sort == newSort)
    }

    // MARK: - Empty state

    @Test func emptyStateBuilds() {
        let emptySnap = ReadingDashboardSnapshot(
            windowTotals: [], activeWindow: .today,
            perBook: [], lifetimeTotalSeconds: 0, trackingSince: nil
        )
        let (vm, _) = makeViewModel(snapshot: emptySnap)
        let view = makeView(viewModel: vm)
        _ = view.body
    }
}
