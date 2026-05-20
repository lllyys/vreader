// Purpose: Value type for the Custom time-window picker (feature #58 WI-6b).
//
// `ReadingStatsCustomRange` represents a user-picked calendar-day range
// `[start, end]` (both inclusive at the calendar-day granularity). It is a
// peer to `ReadingStatsWindow` — together they form the time-axis selection
// for the dashboard.
//
// Pinned to the design's range semantics in
// `dev-docs/designs/vreader-fidelity-v1/project/stats-followups-artboards.jsx`:
// - **Calendar-day inclusive**: a session anywhere on `start..end` is in the
//   range. Internally that's `[startOfDay(start), startOfDay(end+1))`.
// - **Single-day range allowed** (`start == end` → 24h window).
// - **Start-after-end invalid** — flagged so the picker can show its error
//   state; never produces a positive interval/contains result.
// - **Timezone-stable** (Codex Gate-4 medium finding 2026-05-20): the range
//   is stored as `(year, month, day)` triples — NOT raw absolute `Date`
//   instants — so a range picked in Tokyo and reloaded in New York still
//   means "May 1 – May 15", not "April 30 14:00 UTC – May 14 14:00 UTC".
//   The aggregator materializes the precise interval against whatever
//   calendar is current at use time.
// - **Codable** — round-trips through `PreferenceStoring` so the applied
//   range survives across launches.
//
// @coordinates-with: ReadingStatsModels.swift (peer to ReadingStatsWindow),
//   ReadingStatsAggregator.swift (consumes via `dateInterval(calendar:)`),
//   StatsCustomRangePicker.swift (the picker UI),
//   `dev-docs/designs/vreader-fidelity-v1/project/stats-followups-artboards.jsx`

import Foundation

/// A user-picked `[start, end]` calendar-day range for the stats dashboard's
/// Custom pill.
///
/// **Stored** as two `(year, month, day)` triples — timezone-stable across
/// reloads. **Materialized** through the calling calendar at use time.
struct ReadingStatsCustomRange: Sendable, Equatable, Codable {
    /// The start calendar day, broken into `(year, month, day)`.
    let startDay: CalendarDay
    /// The end calendar day, broken into `(year, month, day)`.
    let endDay: CalendarDay

    /// Convenience: a `Date` materialized from `startDay` at start-of-day in
    /// the supplied calendar. Returned as a `Date` so callers (the picker,
    /// summary labels) can use the existing date-formatting helpers; this is
    /// NOT a stored field, it is reconstructed from the day triple.
    func startDate(calendar: Calendar) -> Date? {
        startDay.startOfDay(in: calendar)
    }

    /// Symmetric `endDate` materialization.
    func endDate(calendar: Calendar) -> Date? {
        endDay.startOfDay(in: calendar)
    }

    /// **Legacy compatibility**: `start` reconstructs the absolute `Date`
    /// against the system calendar so existing call sites that read `.start`
    /// keep compiling. Prefer `startDate(calendar:)` for new code.
    var start: Date { startDay.startOfDay(in: .current) ?? Date() }
    var end: Date { endDay.startOfDay(in: .current) ?? Date() }

    /// Build a range from two `Date` instants — the picker hands the model
    /// concrete `Date`s from its month grid; the model captures their day
    /// components in the supplied calendar.
    init(start: Date, end: Date, calendar: Calendar = .current) {
        self.startDay = CalendarDay(date: start, calendar: calendar)
        self.endDay = CalendarDay(date: end, calendar: calendar)
    }

    /// Build directly from day triples — used by the Codable decoder and by
    /// callers that already have day-precise inputs.
    init(startDay: CalendarDay, endDay: CalendarDay) {
        self.startDay = startDay
        self.endDay = endDay
    }

    /// True when `startDay` falls on or before `endDay` (lexicographic compare).
    /// An invalid range corresponds to the picker's `.error` state.
    func isValid(calendar: Calendar) -> Bool {
        startDay <= endDay
    }

    /// Half-open `[startOfDay(startDay), startOfDay(endDay + 1day))` interval —
    /// the shape the aggregator's `contains` test uses. `nil` for an invalid
    /// range or a calendar that cannot materialize the day.
    func dateInterval(calendar: Calendar) -> DateInterval? {
        guard isValid(calendar: calendar),
              let start = startDay.startOfDay(in: calendar),
              let endStartOfDay = endDay.startOfDay(in: calendar),
              let endExclusive = calendar.date(byAdding: .day, value: 1, to: endStartOfDay)
        else { return nil }
        return DateInterval(start: start, end: endExclusive)
    }

    /// True when `date` lies inside the range under `calendar`.
    func contains(_ date: Date, calendar: Calendar) -> Bool {
        guard let interval = dateInterval(calendar: calendar) else { return false }
        return date >= interval.start && date < interval.end
    }

    /// Inclusive day count (calendar days from `startDay` through `endDay`).
    /// Returns 0 for an invalid range so callers can short-circuit "no-results" copy.
    func dayCount(calendar: Calendar) -> Int {
        guard isValid(calendar: calendar),
              let startDate = startDay.startOfDay(in: calendar),
              let endDate = endDay.startOfDay(in: calendar)
        else { return 0 }
        let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return days + 1
    }

    /// The human-readable summary for the active-Custom pill (per
    /// `ExtendedTimeWindowBar`'s `customLabel` in the design canvas):
    /// `"May 1 – May 15"` for a multi-day range; `"May 5"` for a single day.
    /// Year is omitted to fit the pill chrome.
    func summaryLabel(calendar: Calendar) -> String {
        guard isValid(calendar: calendar) else { return "" }
        let startLabel = startDay.shortMonthDayLabel()
        let endLabel = endDay.shortMonthDayLabel()
        if startDay == endDay { return startLabel }
        return "\(startLabel) – \(endLabel)"
    }
}

// MARK: - CalendarDay

/// A timezone-stable `(year, month, day)` triple. Equatable + Comparable +
/// Codable so it round-trips through `PreferenceStoring` JSON intact and the
/// range type can do lexicographic ordering without materializing dates.
struct CalendarDay: Sendable, Equatable, Hashable, Codable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    /// Captures the day this `date` falls on in the supplied calendar.
    init(date: Date, calendar: Calendar) {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        self.year = comps.year ?? 1970
        self.month = comps.month ?? 1
        self.day = comps.day ?? 1
    }

    /// Reconstructs the absolute `Date` at 00:00 in the supplied calendar.
    /// `nil` when the day triple is non-representable in that calendar
    /// (e.g. month 13). Real calendars validate the input.
    func startOfDay(in calendar: Calendar) -> Date? {
        var comps = DateComponents()
        comps.year = year; comps.month = month; comps.day = day
        comps.hour = 0; comps.minute = 0; comps.second = 0
        return calendar.date(from: comps)
    }

    /// Lexicographic `(year, month, day)` ordering.
    static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    /// `"May 1"` / `"Dec 28"` — fixed-English to match the design's
    /// hand-set typography. Year omitted by design (pill chrome).
    func shortMonthDayLabel() -> String {
        let names = [
            "Jan", "Feb", "Mar", "Apr", "May", "Jun",
            "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
        ]
        let monthName = (month >= 1 && month <= 12) ? names[month - 1] : ""
        return "\(monthName) \(day)"
    }
}
