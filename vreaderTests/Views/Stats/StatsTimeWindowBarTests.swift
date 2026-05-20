// Purpose: Composition tests for StatsTimeWindowBar — the design's
// scrollable time-window pill bar (`StatsTimeWindowBar` in
// `vreader-profile-stats.jsx`). Feature #58 WI-6a.
//
// COMPOSITION assertions, not pixel snapshots: the bar renders one pill
// per `ReadingStatsWindow.allCases` case (the WI-1 enum), the active
// pill matches the `value` binding, and tapping a pill invokes the
// `onChange` closure with the tapped window.
//
// Per the D2-B resolution (GH #665 2026-05-20), the design's `Custom`
// pill is DEFERRED to WI-6b (blocked on GH #1058 needs-design). The
// bar therefore renders only the enum-backed windows.

import Testing
import SwiftUI
import Foundation
@testable import vreader

@Suite("StatsTimeWindowBar composition — feature #58 WI-6a")
@MainActor
struct StatsTimeWindowBarTests {

    private func makeBar(
        value: ReadingStatsWindow = .today,
        theme: ReaderThemeV2 = .paper,
        onChange: @escaping (ReadingStatsWindow) -> Void = { _ in }
    ) -> StatsTimeWindowBar {
        StatsTimeWindowBar(theme: theme, value: value, onChange: onChange)
    }

    // MARK: - Builds

    @Test func buildsForEveryReaderTheme() {
        for theme in ReaderThemeV2.allCases {
            let bar = makeBar(theme: theme)
            _ = bar.body
        }
    }

    // MARK: - Window set

    /// The bar renders one pill per enum case. Custom is intentionally
    /// absent — it lives in the design but is deferred to WI-6b
    /// (GH #1058 needs-design).
    @Test func rendersOnePillPerEnumCase() {
        let bar = makeBar()
        let pills = bar.windowsForTesting
        #expect(pills == ReadingStatsWindow.allCases)
    }

    /// The pill labels match `ReadingStatsWindow.label`.
    @Test func pillLabelsMatchEnumLabel() {
        let bar = makeBar()
        let labels = bar.windowsForTesting.map { $0.label }
        #expect(labels == ReadingStatsWindow.allCases.map { $0.label })
    }

    // MARK: - Active pill

    @Test(arguments: ReadingStatsWindow.allCases)
    func activePillTracksValue(_ window: ReadingStatsWindow) {
        let bar = makeBar(value: window)
        #expect(bar.isPillActiveForTesting(window))
        for other in ReadingStatsWindow.allCases where other != window {
            #expect(!bar.isPillActiveForTesting(other))
        }
    }

    // MARK: - Selection callback

    @Test func pillTapInvokesOnChange() {
        var picked: ReadingStatsWindow?
        let bar = makeBar(onChange: { picked = $0 })
        bar.selectWindowForTesting(.last30Days)
        #expect(picked == .last30Days)
    }

    @Test func selectingTheActiveWindowStillFiresOnChange() {
        var fireCount = 0
        let bar = makeBar(value: .today, onChange: { _ in fireCount += 1 })
        // Tapping the already-active pill should still fire; deduplication
        // is the caller's responsibility (mirrors the design's behaviour).
        bar.selectWindowForTesting(.today)
        #expect(fireCount == 1)
    }

    @Test func eachPillFiresWithItsOwnWindow() {
        var lastPicked: ReadingStatsWindow?
        let bar = makeBar(onChange: { lastPicked = $0 })
        for window in ReadingStatsWindow.allCases {
            bar.selectWindowForTesting(window)
            #expect(lastPicked == window)
        }
    }
}
