// Purpose: Tests for BookReadingTimeModel — feature #101 WI-2a's testable
// builder deriving the Book details Reading time group strings (total /
// sessions-since sub / this session / average session) from a per-book
// stats record + the earliest session date + the live session display.

import Foundation
import Testing
@testable import vreader

@Suite("BookReadingTimeModel (feature #101 WI-2a)")
struct BookReadingTimeModelTests {

    private func record(
        total: Int, sessions: Int, longest: Int = 0
    ) -> ReadingStatsRecord {
        ReadingStatsRecord(
            bookFingerprintKey: "epub:test:1", totalReadingSeconds: total,
            sessionCount: sessions, lastReadAt: nil,
            averagePagesPerHour: nil, averageWordsPerMinute: nil,
            totalPagesRead: nil, totalWordsRead: nil,
            longestSessionSeconds: longest
        )
    }

    /// 2026-03-02 12:00:00 UTC.
    private let march2 = Date(timeIntervalSince1970: 1_772_452_800)
    /// 2026-06-11 12:00:00 UTC — "now" in the same year as march2.
    private let june11 = Date(timeIntervalSince1970: 1_781_179_200)

    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // MARK: - Design-canonical row

    @Test func designCanonicalRows() {
        // "Reading time — 6h 40m total" sub "23 sessions since Mar 2";
        // "This session — 12m"; "Average session — 17m" (24000/23 ≈ 1043s).
        let model = BookReadingTimeModel.build(
            record: record(total: 24_000, sessions: 23),
            firstSessionDate: march2,
            liveSessionDisplay: "12m read",
            now: june11, calendar: utcCalendar
        )
        #expect(model.totalValue == "6h 40m total")
        #expect(model.totalSub == "23 sessions since Mar 2")
        #expect(model.thisSessionValue == "12m")
        #expect(model.averageSessionValue == "17m")
    }

    // MARK: - Absent / zero record

    @Test func absentRecordRendersZeroAndDashes() {
        // Plan edge case: absent record → "0m total / — / —", sub omitted.
        let model = BookReadingTimeModel.build(
            record: nil, firstSessionDate: nil, liveSessionDisplay: nil,
            now: june11, calendar: utcCalendar
        )
        #expect(model.totalValue == "0m total")
        #expect(model.totalSub == nil)
        #expect(model.thisSessionValue == "\u{2014}")
        #expect(model.averageSessionValue == "\u{2014}")
    }

    @Test func zeroSessionsOmitsSubAndGuardsDivision() {
        let model = BookReadingTimeModel.build(
            record: record(total: 0, sessions: 0),
            firstSessionDate: nil, liveSessionDisplay: nil,
            now: june11, calendar: utcCalendar
        )
        #expect(model.totalSub == nil)
        #expect(model.averageSessionValue == "\u{2014}")
    }

    // MARK: - Sub line variants

    @Test func singularSession() {
        let model = BookReadingTimeModel.build(
            record: record(total: 600, sessions: 1),
            firstSessionDate: march2, liveSessionDisplay: nil,
            now: june11, calendar: utcCalendar
        )
        #expect(model.totalSub == "1 session since Mar 2")
    }

    @Test func missingFirstDateDropsSinceClause() {
        let model = BookReadingTimeModel.build(
            record: record(total: 600, sessions: 4),
            firstSessionDate: nil, liveSessionDisplay: nil,
            now: june11, calendar: utcCalendar
        )
        #expect(model.totalSub == "4 sessions")
    }

    @Test func priorYearDateCarriesTheYear() {
        // 2025-03-02 12:00:00 UTC — a different calendar year than now.
        let march2_2025 = Date(timeIntervalSince1970: 1_740_916_800)
        let model = BookReadingTimeModel.build(
            record: record(total: 600, sessions: 4),
            firstSessionDate: march2_2025, liveSessionDisplay: nil,
            now: june11, calendar: utcCalendar
        )
        #expect(model.totalSub == "4 sessions since Mar 2, 2025")
    }

    // MARK: - This session

    @Test func liveSessionDisplayDropsReadSuffix() {
        let model = BookReadingTimeModel.build(
            record: record(total: 24_000, sessions: 23),
            firstSessionDate: march2, liveSessionDisplay: "1h 5m read",
            now: june11, calendar: utcCalendar
        )
        #expect(model.thisSessionValue == "1h 5m")
    }

    @Test func subMinuteLiveSessionKeepsLessThanForm() {
        let model = BookReadingTimeModel.build(
            record: record(total: 24_000, sessions: 23),
            firstSessionDate: march2, liveSessionDisplay: "<1m read",
            now: june11, calendar: utcCalendar
        )
        #expect(model.thisSessionValue == "<1m")
    }

    @Test func noLiveReaderShowsDash() {
        let model = BookReadingTimeModel.build(
            record: record(total: 24_000, sessions: 23),
            firstSessionDate: march2, liveSessionDisplay: nil,
            now: june11, calendar: utcCalendar
        )
        #expect(model.thisSessionValue == "\u{2014}")
    }

    @Test func emptyLiveDisplayShowsDash() {
        // The bus mirror posts "" while the session formatter returns nil.
        let model = BookReadingTimeModel.build(
            record: record(total: 24_000, sessions: 23),
            firstSessionDate: march2, liveSessionDisplay: "",
            now: june11, calendar: utcCalendar
        )
        #expect(model.thisSessionValue == "\u{2014}")
    }

    // MARK: - Totals + average

    @Test func longTotalDropsMinutes() {
        let model = BookReadingTimeModel.build(
            record: record(total: 149_400, sessions: 100),
            firstSessionDate: march2, liveSessionDisplay: nil,
            now: june11, calendar: utcCalendar
        )
        #expect(model.totalValue == "41h total")
    }

    @Test(arguments: [
        (89, "1m"),    // 1.48 min rounds down
        (90, "2m"),    // 1.5 min rounds up (Gate-4 Medium boundary)
        (95, "2m"),
        (119, "2m"),
        (120, "2m"),
        (149, "2m"),
        (150, "3m"),   // 2.5 min rounds up
    ])
    func averageRoundsAtTheMinuteLevel(_ avgSeconds: Int, _ expected: String) {
        // One session so total == the average being formatted.
        let model = BookReadingTimeModel.build(
            record: record(total: avgSeconds, sessions: 1),
            firstSessionDate: march2, liveSessionDisplay: nil,
            now: june11, calendar: utcCalendar
        )
        #expect(model.averageSessionValue == expected)
    }

    @Test func averageOverAnHourUsesHourForm() {
        let model = BookReadingTimeModel.build(
            record: record(total: 21_600, sessions: 4),  // 5400s avg
            firstSessionDate: march2, liveSessionDisplay: nil,
            now: june11, calendar: utcCalendar
        )
        #expect(model.averageSessionValue == "1h 30m")
    }
}
