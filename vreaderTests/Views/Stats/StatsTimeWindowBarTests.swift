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
        customRange: ReadingStatsCustomRange? = nil,
        onChange: @escaping (ReadingStatsWindow) -> Void = { _ in },
        onCustomTap: @escaping () -> Void = {}
    ) -> StatsTimeWindowBar {
        StatsTimeWindowBar(
            theme: theme, value: value, customRange: customRange,
            onChange: onChange, onCustomTap: onCustomTap
        )
    }

    /// Builds a deterministic Custom range for label tests.
    private static func sampleRange() -> ReadingStatsCustomRange {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let start = cal.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let end   = cal.date(from: DateComponents(year: 2026, month: 5, day: 15))!
        return ReadingStatsCustomRange(start: start, end: end)
    }

    private static func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
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

    // MARK: - Custom pill (WI-6b)

    @Test func customPillRendersInactiveByDefault() {
        let bar = makeBar(customRange: nil)
        #expect(bar.isCustomPillActiveForTesting == false)
        #expect(bar.customPillLabelForTesting(calendar: Self.utcCalendar()) == "Custom")
    }

    @Test func customPillTapInvokesOnCustomTap() {
        var fireCount = 0
        let bar = makeBar(onCustomTap: { fireCount += 1 })
        bar.selectCustomForTesting()
        #expect(fireCount == 1)
    }

    @Test func customPillActiveWhenRangeApplied() {
        let bar = makeBar(customRange: Self.sampleRange())
        #expect(bar.isCustomPillActiveForTesting == true)
    }

    @Test func customPillCarriesAppliedRangeSummary() {
        let bar = makeBar(customRange: Self.sampleRange())
        let label = bar.customPillLabelForTesting(calendar: Self.utcCalendar())
        #expect(label == "Custom · May 1 – May 15")
    }

    @Test func customRangeActiveDeactivatesEnumPills() {
        // When a Custom range is applied, no enum pill renders as active —
        // the Custom pill owns the active state.
        let bar = makeBar(value: .today, customRange: Self.sampleRange())
        for window in ReadingStatsWindow.allCases {
            #expect(!bar.isPillActiveForTesting(window))
        }
        #expect(bar.isCustomPillActiveForTesting == true)
    }

    @Test func customPillTapFiresEvenWhenAlreadyActive() {
        // Tapping the Custom pill is the re-entry point to the picker — it
        // must fire `onCustomTap` even when a range is already applied.
        var fireCount = 0
        let bar = makeBar(
            customRange: Self.sampleRange(),
            onCustomTap: { fireCount += 1 }
        )
        bar.selectCustomForTesting()
        #expect(fireCount == 1)
    }
}
