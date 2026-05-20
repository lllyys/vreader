// Purpose: Unit tests for ReadingStatsCustomRange — the value type that
// represents a user-picked [startDay, endDay] calendar-day range for the
// stats dashboard's Custom pill (feature #58 WI-6b).
//
// Pinned to the design's range semantics in
// `dev-docs/designs/vreader-fidelity-v1/project/stats-followups-artboards.jsx`:
//   - Range is half-open in absolute time but inclusive in calendar days
//     ([startOfDay(start), endOfDay(end)+1s)).
//   - `start <= end` is the only valid order — start-after-end → `.error`.
//   - `start` and `end` may equal (single-day range).
//   - Future days are not selectable in the picker, so the range never
//     extends past `now`. The model itself does not enforce that — the
//     picker UI is responsible — but the model exposes `dateInterval(...)`
//     that callers can compose with the aggregator.

import Foundation
import Testing
@testable import vreader

@Suite("ReadingStatsCustomRange — feature #58 WI-6b")
struct ReadingStatsCustomRangeTests {

    /// Fixed reference instant: 2026-05-19 14:30:00 UTC.
    private var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 19
        c.hour = 14; c.minute = 30; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    /// Builds a fixed `Date` for a given `(y, m, d)` triplet in UTC.
    private func date(_ y: Int, _ m: Int, _ d: Int,
                      hour: Int = 12, minute: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        c.hour = hour; c.minute = minute
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Builds a range directly from day components — bypasses Date arithmetic
    /// so tests assert against the day triples, not against absolute instants.
    private func range(_ y1: Int, _ m1: Int, _ d1: Int,
                       _ y2: Int, _ m2: Int, _ d2: Int) -> ReadingStatsCustomRange {
        ReadingStatsCustomRange(
            startDay: CalendarDay(year: y1, month: m1, day: d1),
            endDay: CalendarDay(year: y2, month: m2, day: d2)
        )
    }

    // MARK: - Construction

    @Test func equalsBuildsSameRange() {
        let r1 = range(2026, 5, 1, 2026, 5, 15)
        let r2 = range(2026, 5, 1, 2026, 5, 15)
        #expect(r1 == r2)
    }

    @Test func singleDayRangeIsValid() {
        let cal = utcCalendar()
        let r = range(2026, 5, 1, 2026, 5, 1)
        #expect(r.isValid(calendar: cal))
    }

    @Test func startAfterEndIsInvalid() {
        let cal = utcCalendar()
        let r = range(2026, 5, 15, 2026, 5, 1)
        #expect(!r.isValid(calendar: cal))
    }

    // MARK: - dateInterval — calendar-day inclusive

    @Test func dateIntervalCoversTheFullDayRange() {
        // start = 2026-05-01, end = 2026-05-15. The interval must cover from
        // start-of-day(May 1) through start-of-day(May 16) (exclusive end of
        // May 15) so every reading session anywhere in May 1..15 (inclusive)
        // is counted.
        let cal = utcCalendar()
        let r = range(2026, 5, 1, 2026, 5, 15)
        let interval = try! #require(r.dateInterval(calendar: cal))
        #expect(interval.start == cal.startOfDay(for: date(2026, 5, 1)))
        // end is exclusive; equals startOfDay(May 16).
        let nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date(2026, 5, 15)))!
        #expect(interval.end == nextDay)
    }

    @Test func dateIntervalCoversSingleDay() {
        let cal = utcCalendar()
        let r = range(2026, 5, 5, 2026, 5, 5)
        let interval = try! #require(r.dateInterval(calendar: cal))
        #expect(interval.start == cal.startOfDay(for: date(2026, 5, 5)))
        #expect(interval.duration == 86_400)
    }

    @Test func dateIntervalForInvalidRangeIsNil() {
        let cal = utcCalendar()
        let r = range(2026, 5, 15, 2026, 5, 1)
        #expect(r.dateInterval(calendar: cal) == nil)
    }

    // MARK: - contains — half-open per-second semantics

    @Test func containsIncludesStartOfStartDay() {
        let cal = utcCalendar()
        let r = range(2026, 5, 1, 2026, 5, 15)
        let startOfDay = cal.startOfDay(for: date(2026, 5, 1))
        #expect(r.contains(startOfDay, calendar: cal))
    }

    @Test func containsIncludesLateOnEndDay() {
        let cal = utcCalendar()
        let r = range(2026, 5, 1, 2026, 5, 15)
        let lateEndDay = date(2026, 5, 15, hour: 23, minute: 59)
        #expect(r.contains(lateEndDay, calendar: cal))
    }

    @Test func containsExcludesStartOfNextDayAfterEnd() {
        let cal = utcCalendar()
        let r = range(2026, 5, 1, 2026, 5, 15)
        let nextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: date(2026, 5, 15)))!
        #expect(!r.contains(nextDay, calendar: cal))
    }

    @Test func containsExcludesBeforeStart() {
        let cal = utcCalendar()
        let r = range(2026, 5, 1, 2026, 5, 15)
        #expect(!r.contains(date(2026, 4, 30), calendar: cal))
    }

    @Test func invalidRangeContainsNothing() {
        let cal = utcCalendar()
        let r = range(2026, 5, 15, 2026, 5, 1)
        #expect(!r.contains(date(2026, 5, 5), calendar: cal))
    }

    // MARK: - Day count

    @Test func dayCountIs1ForSameDay() {
        let cal = utcCalendar()
        let r = range(2026, 5, 5, 2026, 5, 5)
        #expect(r.dayCount(calendar: cal) == 1)
    }

    @Test func dayCountIsInclusiveOnBothEnds() {
        let cal = utcCalendar()
        // May 1..May 15 inclusive = 15 days.
        let r = range(2026, 5, 1, 2026, 5, 15)
        #expect(r.dayCount(calendar: cal) == 15)
    }

    @Test func dayCountForInvalidRangeIsZero() {
        let cal = utcCalendar()
        let r = range(2026, 5, 15, 2026, 5, 1)
        #expect(r.dayCount(calendar: cal) == 0)
    }

    // MARK: - Summary label

    @Test func summaryLabelMatchesDesignWithinOneMonth() {
        let cal = utcCalendar()
        let r = range(2026, 5, 1, 2026, 5, 15)
        #expect(r.summaryLabel(calendar: cal) == "May 1 – May 15")
    }

    @Test func summaryLabelCollapsesSameDay() {
        let cal = utcCalendar()
        let r = range(2026, 5, 5, 2026, 5, 5)
        #expect(r.summaryLabel(calendar: cal) == "May 5")
    }

    @Test func summaryLabelCrossesMonths() {
        let cal = utcCalendar()
        let r = range(2026, 4, 20, 2026, 5, 5)
        #expect(r.summaryLabel(calendar: cal) == "Apr 20 – May 5")
    }

    @Test func summaryLabelCrossesYears() {
        let cal = utcCalendar()
        let r = range(2025, 12, 28, 2026, 1, 5)
        #expect(r.summaryLabel(calendar: cal) == "Dec 28 – Jan 5")
    }

    // MARK: - Codable round-trip (PreferenceStoring persistence in WI-6b)

    @Test func codableRoundTripsAcrossEncoderBoundary() throws {
        let r = range(2026, 5, 1, 2026, 5, 15)
        let encoded = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(ReadingStatsCustomRange.self, from: encoded)
        #expect(decoded == r)
    }

    // MARK: - Timezone stability (Codex Gate-4 fix)

    /// Codex Gate-4 medium finding: a saved range must mean the same calendar
    /// days when reloaded in a different timezone. The day triples are stored
    /// directly, so this is structural — but tested explicitly here.
    @Test func rangePickedInUTCMeansSameDaysInTokyo() throws {
        // Pick May 1 → May 15 in UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let utcMay1 = utc.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 12))!
        let utcMay15 = utc.date(from: DateComponents(year: 2026, month: 5, day: 15, hour: 12))!
        let picked = ReadingStatsCustomRange(start: utcMay1, end: utcMay15, calendar: utc)

        // Persist + restore.
        let encoded = try JSONEncoder().encode(picked)
        let restored = try JSONDecoder().decode(ReadingStatsCustomRange.self, from: encoded)

        // Now in Tokyo: the calendar-day-inclusive interval should still cover
        // May 1 → May 15 (Tokyo days), not May 1 22:00 → May 14 22:00 (the
        // would-be drift if instants had been persisted instead).
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let tokyoMay1 = tokyo.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let tokyoMay16 = tokyo.date(from: DateComponents(year: 2026, month: 5, day: 16))!
        let interval = try #require(restored.dateInterval(calendar: tokyo))
        #expect(interval.start == tokyoMay1)
        #expect(interval.end == tokyoMay16)
    }
}
