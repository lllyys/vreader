// Purpose: Feature #58 WI-6b — picker state machine + quick-preset math
// for the design's `CustomRangePickerSheet` (stats-followups-artboards.jsx).
//
// Kept separate from the SwiftUI view so the state transitions are pure
// (no SwiftUI, no @MainActor) and unit-testable without driving the UI.
//
// State machine (matches the design's `state` prop):
//   empty            → no dates picked
//   pickingEnd       → start set, end not yet
//   ready            → both endpoints set, apply enabled
//   allTime          → the "All time" preset was tapped (host routes to
//                      the enum `.allTime` pill rather than applying)
//
// `.error` and `.noResults` from the design are post-apply states the host
// surfaces against the snapshot; they're not part of the picker's own
// state machine.
//
// @coordinates-with: StatsCustomRangePicker.swift,
//   ReadingStatsCustomRange.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/stats-followups-artboards.jsx`

import Foundation

/// The picker's lifecycle phase. Matches the design's `state` prop on
/// `CustomRangePickerSheet`, narrowed to the in-picker states.
enum StatsCustomRangePickerPhase: Sendable, Equatable {
    /// No dates picked yet.
    case empty
    /// Start date picked, awaiting end date.
    case pickingEnd
    /// Both endpoints set — Apply is enabled.
    case ready
    /// User picked the "All time" preset — host should route to the
    /// enum `.allTime` pill rather than applying a custom range.
    case allTime
}

/// The six quick presets from the design's `QUICK_PRESETS` array. Mapped to
/// concrete (start, end) day pairs against the picker's `today` baseline.
enum StatsCustomRangePreset: String, CaseIterable, Sendable, Equatable {
    case last7Days
    case last14Days
    case thisMonth
    case lastMonth
    case thisYear
    case allTime

    /// User-facing label exactly as it appears on the design's preset rail.
    var label: String {
        switch self {
        case .last7Days:  return "Last 7 days"
        case .last14Days: return "Last 14 days"
        case .thisMonth:  return "This month"
        case .lastMonth:  return "Last month"
        case .thisYear:   return "This year"
        case .allTime:    return "All time"
        }
    }

    /// Returns the inclusive (start, end) day pair for this preset, anchored at
    /// `today`. `allTime` returns nil — the host routes to the enum pill.
    func dayRange(today: Date, calendar: Calendar) -> (start: Date, end: Date)? {
        let endDay = calendar.startOfDay(for: today)
        switch self {
        case .last7Days:
            return (calendar.date(byAdding: .day, value: -6, to: endDay)!, endDay)
        case .last14Days:
            return (calendar.date(byAdding: .day, value: -13, to: endDay)!, endDay)
        case .thisMonth:
            var comps = calendar.dateComponents([.year, .month], from: endDay)
            comps.day = 1
            let firstOfMonth = calendar.date(from: comps)!
            return (firstOfMonth, endDay)
        case .lastMonth:
            // First day of last month.
            var comps = calendar.dateComponents([.year, .month], from: endDay)
            comps.day = 1
            let firstOfThisMonth = calendar.date(from: comps)!
            let firstOfLastMonth = calendar.date(
                byAdding: .month, value: -1, to: firstOfThisMonth
            )!
            // Last day of last month = day before first of this month.
            let lastOfLastMonth = calendar.date(
                byAdding: .day, value: -1, to: firstOfThisMonth
            )!
            return (firstOfLastMonth, lastOfLastMonth)
        case .thisYear:
            var comps = calendar.dateComponents([.year], from: endDay)
            comps.month = 1; comps.day = 1
            let firstOfYear = calendar.date(from: comps)!
            return (firstOfYear, endDay)
        case .allTime:
            return nil
        }
    }
}

/// The picker's mutable in-flight state. Pure value type; the SwiftUI view
/// owns it via `@State`.
struct StatsCustomRangePickerState: Sendable, Equatable {
    /// The "today" reference instant — future days are not selectable.
    let today: Date
    let calendar: Calendar

    private(set) var start: Date?
    private(set) var end: Date?
    private(set) var phase: StatsCustomRangePickerPhase = .empty

    /// Construct an empty picker, or seed it from an already-applied range.
    init(
        today: Date,
        calendar: Calendar,
        existingRange: ReadingStatsCustomRange? = nil
    ) {
        self.today = today
        self.calendar = calendar
        if let r = existingRange, r.isValid(calendar: calendar) {
            // Re-materialize against the state's calendar so a saved range
            // picked in another timezone still picks the SAME calendar days
            // — not the shifted instants (Codex Gate-4 timezone-stability fix).
            self.start = r.startDate(calendar: calendar)
            self.end = r.endDate(calendar: calendar)
            self.phase = .ready
        }
    }

    /// True when both endpoints are picked → Apply is enabled.
    var canApply: Bool { phase == .ready }

    /// Tap a date in the month grid. Drives the empty → pickingEnd → ready
    /// transitions. Future dates are silently ignored.
    mutating func pickDate(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        let todayStart = calendar.startOfDay(for: today)
        guard day <= todayStart else { return }

        switch phase {
        case .empty:
            start = day; end = nil; phase = .pickingEnd
        case .pickingEnd:
            // Picking before the start rubber-bands to a new start; picking
            // on-or-after completes the range.
            if let s = start {
                if day < s {
                    start = day; end = nil; phase = .pickingEnd
                } else {
                    end = day; phase = .ready
                }
            } else {
                start = day; phase = .pickingEnd
            }
        case .ready, .allTime:
            // After a range is set, a single tap restarts.
            start = day; end = nil; phase = .pickingEnd
        }
    }

    /// Apply a quick preset. The `.allTime` preset moves to its own phase so
    /// the host can route to the enum pill.
    mutating func selectPreset(_ preset: StatsCustomRangePreset) {
        guard let range = preset.dayRange(today: today, calendar: calendar) else {
            start = nil; end = nil; phase = .allTime; return
        }
        start = range.start; end = range.end; phase = .ready
    }

    /// Resets the picker to its empty state.
    mutating func reset() {
        start = nil; end = nil; phase = .empty
    }

    /// Returns the applied range when the picker is in the `.ready` phase,
    /// nil otherwise.
    func applyRange() -> ReadingStatsCustomRange? {
        guard phase == .ready, let s = start, let e = end else { return nil }
        // Capture day triples in the picker's calendar so the persisted form
        // is timezone-stable (Codex Gate-4 fix).
        let range = ReadingStatsCustomRange(start: s, end: e, calendar: calendar)
        return range.isValid(calendar: calendar) ? range : nil
    }
}

// MARK: - Month grid

/// Pure month-grid math for the design's `MonthGrid`. Returns a flat array of
/// day numbers (1-N) interleaved with `nil` blanks so the calling SwiftUI
/// `LazyVGrid` of 7 columns lines up under the Mon..Sun header. The length
/// is always a multiple of 7 (per the design's `cells.length % 7` pad loop).
enum StatsCustomRangeMonthGrid {
    /// Returns the array of 7×N cells for `(year, month)` under `calendar`.
    /// `calendar.firstWeekday` controls the leading-blank count — pass a
    /// Monday-first calendar to match the design.
    static func cells(forYear year: Int, month: Int, calendar: Calendar) -> [Int?] {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = 1
        guard let firstOfMonth = calendar.date(from: comps),
              let dim = calendar.range(of: .day, in: .month, for: firstOfMonth)
        else { return [] }
        let daysInMonth = dim.count

        // Day-of-week of the first day, in Monday=0..Sunday=6 (matching the
        // design's `dowOf` formula — independent of `calendar.firstWeekday`).
        let weekday = calendar.component(.weekday, from: firstOfMonth)
        // Calendar.weekday is 1=Sunday..7=Saturday; convert to Mon=0..Sun=6.
        let mondayBasedOffset = (weekday + 5) % 7

        var cells: [Int?] = Array(repeating: nil, count: mondayBasedOffset)
        for d in 1...daysInMonth { cells.append(d) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }
}
