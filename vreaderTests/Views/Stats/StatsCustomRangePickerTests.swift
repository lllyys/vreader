// Purpose: Composition + state tests for StatsCustomRangePicker — the
// design's `CustomRangePickerSheet` (feature #58 WI-6b).
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/stats-followups-artboards.jsx`
// (`CustomRangePickerSheet` + `MonthGrid` + `QuickPresetRail`).
//
// COMPOSITION assertions, not pixel snapshots: the picker's state machine
// (empty → picking-end → ready → applied/error/no-results), the preset
// rail's range computation, and the apply/cancel callback wiring.

import Foundation
import SwiftUI
import Testing
@testable import vreader

@Suite("StatsCustomRangePicker composition — feature #58 WI-6b")
@MainActor
struct StatsCustomRangePickerTests {

    // MARK: - Fixtures

    private static func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Fixed "today" baseline: 2026-05-20 12:00 UTC (Wednesday). Same as the
    /// design canvas's `TODAY` constant.
    private static var sampleToday: Date {
        utcCalendar().date(from: DateComponents(year: 2026, month: 5, day: 20, hour: 12))!
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utcCalendar().date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: - PickerState lifecycle

    @Test func initialStateIsEmpty() {
        let state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        #expect(state.start == nil)
        #expect(state.end == nil)
        #expect(state.phase == .empty)
        #expect(state.canApply == false)
    }

    @Test func tappingStartDateTransitionsToPickingEnd() {
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.pickDate(Self.date(2026, 5, 1))
        #expect(state.start == Self.date(2026, 5, 1))
        #expect(state.end == nil)
        #expect(state.phase == .pickingEnd)
        // Apply is still disabled — we need both endpoints.
        #expect(state.canApply == false)
    }

    @Test func tappingEndDateAfterStartProducesAReadyRange() {
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.pickDate(Self.date(2026, 5, 1))
        state.pickDate(Self.date(2026, 5, 15))
        #expect(state.start == Self.date(2026, 5, 1))
        #expect(state.end == Self.date(2026, 5, 15))
        #expect(state.phase == .ready)
        #expect(state.canApply == true)
    }

    @Test func tappingAnEarlierDateAfterStartResetsStart() {
        // If the user picks May 10, then taps May 5 (earlier), the picker
        // resets the range with May 5 as the new start — the design's
        // "rubber-band back" behavior. This way you don't have to cancel and
        // start over.
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.pickDate(Self.date(2026, 5, 10))
        state.pickDate(Self.date(2026, 5, 5))
        #expect(state.start == Self.date(2026, 5, 5))
        #expect(state.end == nil)
        #expect(state.phase == .pickingEnd)
    }

    @Test func tappingAfterReadyStartsANewRange() {
        // After a range is set, tapping a single date resets to a single
        // start — the user is starting over.
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.pickDate(Self.date(2026, 5, 1))
        state.pickDate(Self.date(2026, 5, 15))
        state.pickDate(Self.date(2026, 5, 7))
        #expect(state.start == Self.date(2026, 5, 7))
        #expect(state.end == nil)
        #expect(state.phase == .pickingEnd)
    }

    @Test func tappingTheSameDateProducesSingleDayRange() {
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.pickDate(Self.date(2026, 5, 10))
        state.pickDate(Self.date(2026, 5, 10))
        #expect(state.start == Self.date(2026, 5, 10))
        #expect(state.end == Self.date(2026, 5, 10))
        #expect(state.phase == .ready)
        #expect(state.canApply == true)
    }

    // MARK: - Quick presets

    @Test func quickPresetLast7DaysProducesReadyRange() {
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.selectPreset(.last7Days)
        #expect(state.phase == .ready)
        // today = May 20 → last 7 days = May 14..May 20.
        #expect(state.start == Self.date(2026, 5, 14))
        #expect(state.end == Self.date(2026, 5, 20))
    }

    @Test func quickPresetLast14DaysProducesReadyRange() {
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.selectPreset(.last14Days)
        #expect(state.phase == .ready)
        #expect(state.start == Self.date(2026, 5, 7))
        #expect(state.end == Self.date(2026, 5, 20))
    }

    @Test func quickPresetThisMonthProducesReadyRange() {
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.selectPreset(.thisMonth)
        #expect(state.phase == .ready)
        #expect(state.start == Self.date(2026, 5, 1))
        #expect(state.end == Self.date(2026, 5, 20))
    }

    @Test func quickPresetLastMonthProducesReadyRange() {
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.selectPreset(.lastMonth)
        // today = May 20 → last month = April 2026 (Apr 1..Apr 30).
        #expect(state.phase == .ready)
        #expect(state.start == Self.date(2026, 4, 1))
        #expect(state.end == Self.date(2026, 4, 30))
    }

    @Test func quickPresetThisYearProducesReadyRange() {
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.selectPreset(.thisYear)
        // today = May 20, 2026 → this year = Jan 1..May 20.
        #expect(state.phase == .ready)
        #expect(state.start == Self.date(2026, 1, 1))
        #expect(state.end == Self.date(2026, 5, 20))
    }

    @Test func quickPresetAllTimeIsNotApplyable() {
        // "All time" is a special case — the existing `last365Days` covers
        // most history. The preset rail still offers "All time" for
        // visibility, but it routes to the enum `allTime` pill rather than
        // producing a Custom range. Internally that means tapping it on
        // the picker dismisses to enum mode (the host handles routing —
        // the state itself returns a no-op marker).
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.selectPreset(.allTime)
        #expect(state.phase == .allTime)
        #expect(state.canApply == false)
    }

    // MARK: - Picker → range conversion

    @Test func appliedRangeIsCorrect() {
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.pickDate(Self.date(2026, 5, 1))
        state.pickDate(Self.date(2026, 5, 15))
        let range = state.applyRange()
        let unwrapped = try! #require(range)
        // WI-6b: ranges store day triples — assert against those, not against
        // an absolute Date (which depends on the current timezone).
        #expect(unwrapped.startDay == CalendarDay(year: 2026, month: 5, day: 1))
        #expect(unwrapped.endDay == CalendarDay(year: 2026, month: 5, day: 15))
    }

    @Test func applyReturnsNilWhenNotReady() {
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        // Empty.
        #expect(state.applyRange() == nil)
        // Only start picked.
        state.pickDate(Self.date(2026, 5, 1))
        #expect(state.applyRange() == nil)
    }

    // MARK: - Future-date guard (design: future days are not selectable)

    @Test func pickingFutureDateIsIgnored() {
        // today = May 20, 2026; May 25 is in the future → ignored.
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.pickDate(Self.date(2026, 5, 25))
        #expect(state.start == nil)
        #expect(state.phase == .empty)
    }

    @Test func todayIsSelectable() {
        // The reference instant Self.sampleToday has hour=12; passing
        // start-of-day(today) must be accepted.
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        let cal = Self.utcCalendar()
        let todayStart = cal.startOfDay(for: Self.sampleToday)
        state.pickDate(todayStart)
        #expect(state.start == todayStart)
    }

    // MARK: - Restore from an applied range

    @Test func initFromExistingRangeStartsReady() {
        let range = ReadingStatsCustomRange(
            startDay: CalendarDay(year: 2026, month: 5, day: 1),
            endDay: CalendarDay(year: 2026, month: 5, day: 15)
        )
        let cal = Self.utcCalendar()
        let state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: cal,
            existingRange: range
        )
        // State materializes the range's day triples against its own
        // calendar — assert the resulting Date is the start-of-day for
        // those days in that calendar.
        #expect(state.start == cal.date(from: DateComponents(year: 2026, month: 5, day: 1)))
        #expect(state.end == cal.date(from: DateComponents(year: 2026, month: 5, day: 15)))
        #expect(state.phase == .ready)
        #expect(state.canApply == true)
    }

    // MARK: - Reset

    @Test func resetClearsToEmpty() {
        var state = StatsCustomRangePickerState(
            today: Self.sampleToday, calendar: Self.utcCalendar()
        )
        state.pickDate(Self.date(2026, 5, 1))
        state.pickDate(Self.date(2026, 5, 15))
        state.reset()
        #expect(state.start == nil)
        #expect(state.end == nil)
        #expect(state.phase == .empty)
    }
}

// MARK: - Month-grid helpers

@Suite("StatsCustomRangePicker month-grid math")
struct StatsCustomRangeMonthGridTests {

    private static func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2  // Monday — per design's `DOW` constant
        return cal
    }

    @Test func monthGridForMay2026PadsToMultipleOfSeven() {
        // May 2026 has 31 days; May 1 = Friday → 4 leading blanks (Mon-Thu),
        // 31 day cells, 0 trailing blanks needed when total reaches 35.
        // Per the design's `while (cells.length % 7) cells.push(null)`, the
        // grid pads to the next multiple of 7.
        let grid = StatsCustomRangeMonthGrid.cells(
            forYear: 2026, month: 5, calendar: Self.utcCalendar()
        )
        #expect(grid.count % 7 == 0)
        #expect(grid.count >= 31 + 4)
        // The non-nil span starts at index 4 (Friday under Monday-first) and
        // runs 31 cells.
        let nonNil = grid.compactMap { $0 }
        #expect(nonNil.count == 31)
        #expect(nonNil.first == 1)
        #expect(nonNil.last == 31)
        // Leading blanks indicate Mon..Thu before May 1.
        #expect(grid[0] == nil)
        #expect(grid[3] == nil)
        #expect(grid[4] == 1)
    }

    @Test func monthGridForFebruary2025() {
        // Feb 2025: 28 days. Feb 1 2025 = Saturday → 5 leading blanks (Mon-Fri).
        // 5 + 28 = 33 → pad to 35.
        let grid = StatsCustomRangeMonthGrid.cells(
            forYear: 2025, month: 2, calendar: Self.utcCalendar()
        )
        #expect(grid.count == 35)
        let nonNil = grid.compactMap { $0 }
        #expect(nonNil.count == 28)
        #expect(grid[5] == 1)  // Feb 1 = Saturday slot under Mon-first
    }
}
