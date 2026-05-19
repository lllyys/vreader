// Purpose: Tests for MonthBoundary — the pure calendar-month interval
// helper that feeds the Settings profile-card "this month" subline
// (feature #67 WI-1).

import Testing
import Foundation
@testable import vreader

@Suite("MonthBoundary")
struct MonthBoundaryTests {

    /// A Gregorian calendar pinned to UTC so the interval math is
    /// deterministic regardless of the test host's time zone.
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// Builds a `Date` for a given Y/M/D H:M:S in the supplied calendar.
    private func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        calendar: Calendar
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    @Test func midMonthDateYieldsThatCalendarMonth() {
        let calendar = utcCalendar()
        let interval = MonthBoundary.currentMonth(
            containing: date(2026, 5, 19, 14, 30, 0, calendar: calendar),
            calendar: calendar
        )
        #expect(interval.start == date(2026, 5, 1, calendar: calendar))
        #expect(interval.end == date(2026, 6, 1, calendar: calendar))
    }

    @Test func firstInstantOfMonthStartsTheInterval() {
        let calendar = utcCalendar()
        let firstInstant = date(2026, 5, 1, 0, 0, 0, calendar: calendar)
        let interval = MonthBoundary.currentMonth(containing: firstInstant, calendar: calendar)
        #expect(interval.start == firstInstant)
        #expect(interval.contains(firstInstant))
    }

    @Test func lastInstantOfMonthStaysInTheMonthInterval() {
        let calendar = utcCalendar()
        let lastInstant = date(2026, 5, 31, 23, 59, 59, calendar: calendar)
        let interval = MonthBoundary.currentMonth(containing: lastInstant, calendar: calendar)
        #expect(interval.start == date(2026, 5, 1, calendar: calendar))
        #expect(interval.end == date(2026, 6, 1, calendar: calendar))
        #expect(interval.contains(lastInstant))
    }

    @Test func februaryInLeapYearSpansTwentyNineDays() {
        let calendar = utcCalendar()
        let interval = MonthBoundary.currentMonth(
            containing: date(2024, 2, 15, calendar: calendar),
            calendar: calendar
        )
        #expect(interval.start == date(2024, 2, 1, calendar: calendar))
        #expect(interval.end == date(2024, 3, 1, calendar: calendar))
        // 29 days * 86400s.
        #expect(interval.duration == 29 * 86_400)
    }

    @Test func februaryInNonLeapYearSpansTwentyEightDays() {
        let calendar = utcCalendar()
        let interval = MonthBoundary.currentMonth(
            containing: date(2026, 2, 15, calendar: calendar),
            calendar: calendar
        )
        #expect(interval.start == date(2026, 2, 1, calendar: calendar))
        #expect(interval.end == date(2026, 3, 1, calendar: calendar))
        #expect(interval.duration == 28 * 86_400)
    }

    @Test func decemberIntervalCrossesIntoNextYear() {
        let calendar = utcCalendar()
        let interval = MonthBoundary.currentMonth(
            containing: date(2026, 12, 20, calendar: calendar),
            calendar: calendar
        )
        #expect(interval.start == date(2026, 12, 1, calendar: calendar))
        #expect(interval.end == date(2027, 1, 1, calendar: calendar))
    }

    @Test func dstTransitionMonthStillSpansTheFullCalendarMonth() {
        // March 2026 in US Pacific contains the spring-forward DST jump.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let interval = MonthBoundary.currentMonth(
            containing: date(2026, 3, 15, 12, 0, 0, calendar: calendar),
            calendar: calendar
        )
        // start is the first instant of March in that zone.
        #expect(interval.start == date(2026, 3, 1, 0, 0, 0, calendar: calendar))
        // end is the first instant of April in that zone.
        #expect(interval.end == date(2026, 4, 1, 0, 0, 0, calendar: calendar))
        // March has 31 days but one is short an hour due to DST — the
        // interval still ends exactly at April-1, never an hour off.
        #expect(interval.contains(date(2026, 3, 31, 23, 0, 0, calendar: calendar)))
    }

    @Test func intervalIsNeverNegativeWidthForAnyContainingDate() {
        let calendar = utcCalendar()
        // A future and a past date both yield a positive-width interval
        // that *contains* the supplied date.
        for sample in [
            date(2099, 7, 4, calendar: calendar),
            date(1971, 1, 15, calendar: calendar)
        ] {
            let interval = MonthBoundary.currentMonth(containing: sample, calendar: calendar)
            #expect(interval.duration > 0)
            #expect(interval.contains(sample))
        }
    }
}
