// Purpose: Feature #101 WI-2a — the testable builder deriving the Book
// details "Reading time" group strings (design `RTBookDetailsRows`):
// total ("6h 40m total"), the sessions-since sub line ("23 sessions
// since Mar 2"), this session ("12m" / "—"), and average session
// ("17m" / "—"). Pure derivation — the sheet layer (WI-2b) only renders.
//
// Key decisions:
// - Absent stats record renders truthfully: "0m total", no sub, em-dash
//   session/average (the plan's "simplest truthful rendering").
// - The since-date shows "Mar 2" within the current calendar year and
//   "Mar 2, 2025" otherwise (the design depicts the same-year form;
//   bare month-day would be ambiguous across years).
// - "This session" reuses the live chrome display ("12m read") with the
//   " read" suffix dropped — one formatter owns both forms.
//
// @coordinates-with: ReadingTimeFormatter.swift, PersistenceActor+Stats.swift,
//   BookDetailsSheet.swift, dev-docs/plans/20260611-feature-101-reading-time.md

import Foundation

/// Feature #101 WI-2b: the host-fetched persisted half of the Reading
/// time group — the per-book stats record (nil = never read) and the
/// earliest session start. `ReaderContainerView` fetches it once when
/// Book details presents; the live session display arrives separately
/// off the `.readerSessionTimeDidChange` mirror.
struct BookReadingTimeStats: Equatable, Sendable {
    let record: ReadingStatsRecord?
    let firstSessionDate: Date?
}

/// The derived Reading time group for Book details (feature #101).
struct BookReadingTimeModel: Equatable, Sendable {
    /// "6h 40m total" / "41h total" / "0m total".
    let totalValue: String
    /// "23 sessions since Mar 2" / "4 sessions" / nil (no sessions).
    let totalSub: String?
    /// "12m" / "<1m" / "—" (no live reader).
    let thisSessionValue: String
    /// "17m" / "1h 30m" / "—" (no sessions).
    let averageSessionValue: String

    static let emDash = "\u{2014}"

    /// Builds the group from the per-book stats record (nil = never read),
    /// the earliest session start, and the live session display mirrored
    /// off `.readerSessionTimeDidChange` (nil/empty = no live reader).
    static func build(
        record: ReadingStatsRecord?,
        firstSessionDate: Date?,
        liveSessionDisplay: String?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> BookReadingTimeModel {
        let totalSeconds = record?.totalReadingSeconds ?? 0
        let sessionCount = record?.sessionCount ?? 0

        let average: String
        if sessionCount > 0 {
            // Round at the MINUTE level (the plan's "rounds to minutes") —
            // rounding seconds then flooring would render 90-119s as "1m"
            // (Gate-4 Medium).
            let avgMinutes = Int((Double(totalSeconds) / Double(sessionCount) / 60).rounded())
            average = ReadingTimeFormatter.formatDuration(totalSeconds: avgMinutes * 60)
        } else {
            average = emDash
        }

        return BookReadingTimeModel(
            totalValue: "\(ReadingTimeFormatter.totalDisplay(totalSeconds: totalSeconds)) total",
            totalSub: subLine(
                sessionCount: sessionCount, firstSessionDate: firstSessionDate,
                now: now, calendar: calendar
            ),
            thisSessionValue: sessionValue(from: liveSessionDisplay),
            averageSessionValue: average
        )
    }

    /// "23 sessions since Mar 2" — singular-aware; drops the since clause
    /// when no first date is known; nil when there are no sessions at all.
    private static func subLine(
        sessionCount: Int, firstSessionDate: Date?, now: Date, calendar: Calendar
    ) -> String? {
        guard sessionCount > 0 else { return nil }
        let noun = sessionCount == 1 ? "session" : "sessions"
        guard let firstSessionDate else { return "\(sessionCount) \(noun)" }
        let since = sinceDisplay(firstSessionDate, now: now, calendar: calendar)
        return "\(sessionCount) \(noun) since \(since)"
    }

    /// "Mar 2" within the current calendar year, "Mar 2, 2025" otherwise.
    private static func sinceDisplay(_ date: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: now)
        formatter.dateFormat = sameYear ? "MMM d" : "MMM d, yyyy"
        return formatter.string(from: date)
    }

    /// The live chrome display ("12m read") with the " read" suffix
    /// dropped; em-dash when there is no live reader for this book.
    private static func sessionValue(from liveSessionDisplay: String?) -> String {
        guard let display = liveSessionDisplay, !display.isEmpty else { return emDash }
        if display.hasSuffix(" read") { return String(display.dropLast(5)) }
        return display
    }
}
