// Purpose: Unit tests for ReadingStatsModels — window date-interval math,
// the per-book sort comparator, and ReadingDashboardSort string round-trip.
// Feature #58 WI-1.

import Foundation
import Testing
@testable import vreader

@Suite("ReadingStatsWindow date intervals")
struct ReadingStatsWindowIntervalTests {

    /// Fixed reference instant: 2026-05-19 14:30:00 UTC.
    private var now: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 19
        c.hour = 14; c.minute = 30; c.second = 0
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    @Test func todayStartsAtLocalMidnight() {
        let cal = utcCalendar()
        let interval = ReadingStatsWindow.today.dateInterval(now: now, calendar: cal)
        let unwrapped = try! #require(interval)
        // today = local-midnight(now) ..< now
        let expectedStart = cal.startOfDay(for: now)
        #expect(unwrapped.start == expectedStart)
        #expect(unwrapped.end == now)
    }

    @Test(arguments: [
        (ReadingStatsWindow.last7Days, 7),
        (ReadingStatsWindow.last30Days, 30),
        (ReadingStatsWindow.last90Days, 90),
        (ReadingStatsWindow.last180Days, 180),
        (ReadingStatsWindow.last365Days, 365),
    ])
    func rollingWindowsSpanNDays(_ window: ReadingStatsWindow, _ days: Int) {
        let cal = utcCalendar()
        let interval = window.dateInterval(now: now, calendar: cal)
        let unwrapped = try! #require(interval)
        #expect(unwrapped.end == now)
        let expectedStart = now.addingTimeInterval(-Double(days) * 86_400)
        #expect(abs(unwrapped.start.timeIntervalSince(expectedStart)) < 1.0)
    }

    @Test func allTimeHasNoLowerBound() {
        let interval = ReadingStatsWindow.allTime.dateInterval(now: now, calendar: utcCalendar())
        #expect(interval == nil)
    }

    @Test func timezoneChangesTodayLowerBound() {
        // Same `now`, two calendars in different time zones → different
        // local-midnight, hence a different `today` start (edge case g).
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")! // UTC+9

        let utcStart = ReadingStatsWindow.today.dateInterval(now: now, calendar: utc)!.start
        let tokyoStart = ReadingStatsWindow.today.dateInterval(now: now, calendar: tokyo)!.start
        #expect(utcStart != tokyoStart)
    }

    @Test func todayIntervalAcrossDSTSpringForwardAnchorsAtLocalMidnight() {
        // 2026-03-08 in America/New_York is a spring-forward day (02:00→03:00).
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        var c = DateComponents()
        c.year = 2026; c.month = 3; c.day = 8; c.hour = 15; c.minute = 0
        c.timeZone = TimeZone(identifier: "America/New_York")
        let dstNow = ny.date(from: c)!
        let interval = ReadingStatsWindow.today.dateInterval(now: dstNow, calendar: ny)!
        // Start is still local midnight of that day, even though the day is 23h long.
        #expect(interval.start == ny.startOfDay(for: dstNow))
        #expect(interval.end == dstNow)
    }

    @Test func allCasesAreSevenInCanonicalOrder() {
        #expect(ReadingStatsWindow.allCases == [
            .today, .last7Days, .last30Days, .last90Days,
            .last180Days, .last365Days, .allTime,
        ])
    }

    @Test func labelsAreStable() {
        #expect(ReadingStatsWindow.today.label == "Today")
        #expect(ReadingStatsWindow.last7Days.label == "7d")
        #expect(ReadingStatsWindow.last30Days.label == "30d")
        #expect(ReadingStatsWindow.last90Days.label == "90d")
        #expect(ReadingStatsWindow.last180Days.label == "180d")
        #expect(ReadingStatsWindow.last365Days.label == "365d")
        #expect(ReadingStatsWindow.allTime.label == "All")
    }
}

@Suite("ReadingDashboardSort string round-trip")
struct ReadingDashboardSortStorageTests {

    @Test func defaultIsReadingTimeDescending() {
        #expect(ReadingDashboardSort.default.field == .readingTime)
        #expect(ReadingDashboardSort.default.ascending == false)
    }

    @Test(arguments: [
        ReadingDashboardSort(field: .title, ascending: true),
        ReadingDashboardSort(field: .title, ascending: false),
        ReadingDashboardSort(field: .readingTime, ascending: true),
        ReadingDashboardSort(field: .readingTime, ascending: false),
        ReadingDashboardSort(field: .highlights, ascending: true),
        ReadingDashboardSort(field: .notes, ascending: false),
    ])
    func roundTripsThroughStorageString(_ sort: ReadingDashboardSort) {
        let restored = ReadingDashboardSort(storageString: sort.storageString)
        #expect(restored == sort)
    }

    @Test func storageStringFormat() {
        #expect(ReadingDashboardSort(field: .readingTime, ascending: false).storageString == "readingTime:desc")
        #expect(ReadingDashboardSort(field: .title, ascending: true).storageString == "title:asc")
    }

    @Test(arguments: ["", "garbage", "readingTime", "readingTime:sideways", "bogusField:asc", ":asc", "readingTime:"])
    func malformedStringYieldsNil(_ raw: String) {
        #expect(ReadingDashboardSort(storageString: raw) == nil)
    }
}

@Suite("PerBookStatsRow sort comparator")
struct PerBookStatsRowSortTests {

    private func row(
        key: String, title: String, deleted: Bool = false,
        seconds: Int, notes: Int, highlights: Int, lastRead: Date?
    ) -> PerBookStatsRow {
        PerBookStatsRow(
            id: key, bookFingerprintKey: key, title: title, isDeleted: deleted,
            readingSecondsInWindow: seconds, notesCount: notes,
            highlightsCount: highlights, lastReadAt: lastRead
        )
    }

    private var sample: [PerBookStatsRow] {
        [
            row(key: "a", title: "Beta", seconds: 100, notes: 2, highlights: 5, lastRead: Date(timeIntervalSince1970: 200)),
            row(key: "b", title: "alpha", seconds: 300, notes: 1, highlights: 1, lastRead: Date(timeIntervalSince1970: 100)),
            row(key: "c", title: "Gamma", seconds: 200, notes: 3, highlights: 3, lastRead: nil),
        ]
    }

    @Test func sortsByReadingTimeDescending() {
        let sorted = PerBookStatsRow.sorted(sample, by: ReadingDashboardSort(field: .readingTime, ascending: false))
        #expect(sorted.map(\.bookFingerprintKey) == ["b", "c", "a"])
    }

    @Test func sortsByReadingTimeAscending() {
        let sorted = PerBookStatsRow.sorted(sample, by: ReadingDashboardSort(field: .readingTime, ascending: true))
        #expect(sorted.map(\.bookFingerprintKey) == ["a", "c", "b"])
    }

    @Test func sortsByTitleCaseInsensitiveAscending() {
        let sorted = PerBookStatsRow.sorted(sample, by: ReadingDashboardSort(field: .title, ascending: true))
        // "alpha" < "Beta" < "Gamma" case-insensitively.
        #expect(sorted.map(\.title) == ["alpha", "Beta", "Gamma"])
    }

    @Test func sortsByNotesDescending() {
        let sorted = PerBookStatsRow.sorted(sample, by: ReadingDashboardSort(field: .notes, ascending: false))
        #expect(sorted.map(\.bookFingerprintKey) == ["c", "a", "b"])
    }

    @Test func sortsByHighlightsDescending() {
        let sorted = PerBookStatsRow.sorted(sample, by: ReadingDashboardSort(field: .highlights, ascending: false))
        #expect(sorted.map(\.bookFingerprintKey) == ["a", "c", "b"])
    }

    @Test func tiesBreakByTitleStably() {
        let tied = [
            row(key: "x", title: "Zebra", seconds: 100, notes: 0, highlights: 0, lastRead: nil),
            row(key: "y", title: "apple", seconds: 100, notes: 0, highlights: 0, lastRead: nil),
            row(key: "z", title: "mango", seconds: 100, notes: 0, highlights: 0, lastRead: nil),
        ]
        let sorted = PerBookStatsRow.sorted(tied, by: ReadingDashboardSort(field: .readingTime, ascending: false))
        // All reading-times equal → tie-break by title ascending, case-insensitive.
        #expect(sorted.map(\.title) == ["apple", "mango", "Zebra"])
    }

    @Test func deletedRowsSortStablyAmongLiveRows() {
        let rows = [
            row(key: "live1", title: "Real Book", seconds: 50, notes: 1, highlights: 1, lastRead: nil),
            row(key: "del1", title: "(deleted)", deleted: true, seconds: 500, notes: 0, highlights: 0, lastRead: nil),
        ]
        let sorted = PerBookStatsRow.sorted(rows, by: ReadingDashboardSort(field: .readingTime, ascending: false))
        // Deleted row has more reading-time → sorts first; it is not specially demoted.
        #expect(sorted.map(\.bookFingerprintKey) == ["del1", "live1"])
    }

    @Test func emptyInputYieldsEmptyOutput() {
        let sorted = PerBookStatsRow.sorted([], by: ReadingDashboardSort.default)
        #expect(sorted.isEmpty)
    }
}

@Suite("ReadingDashboardSnapshot lookup")
struct ReadingDashboardSnapshotTests {

    @Test func totalForPresentWindowReturnsStoredValue() {
        let totals = ReadingStatsWindow.allCases.map {
            WindowTotal(window: $0, totalSeconds: $0 == .today ? 600 : 0, sessionCount: $0 == .today ? 2 : 0)
        }
        let snapshot = ReadingDashboardSnapshot(
            windowTotals: totals, activeWindow: .today, perBook: [],
            lifetimeTotalSeconds: 600, trackingSince: nil
        )
        #expect(snapshot.total(for: .today).totalSeconds == 600)
        #expect(snapshot.total(for: .today).sessionCount == 2)
    }

    @Test func totalForMissingWindowReturnsZeroed() {
        // A snapshot whose windowTotals omits last90Days → total(for:) zeroes it.
        let totals = [WindowTotal(window: .today, totalSeconds: 100, sessionCount: 1)]
        let snapshot = ReadingDashboardSnapshot(
            windowTotals: totals, activeWindow: .today, perBook: [],
            lifetimeTotalSeconds: 100, trackingSince: nil
        )
        let missing = snapshot.total(for: .last90Days)
        #expect(missing.window == .last90Days)
        #expect(missing.totalSeconds == 0)
        #expect(missing.sessionCount == 0)
    }
}
