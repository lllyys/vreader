// Purpose: Actor that aggregates ReadingSession rows into a dashboard snapshot
// for feature #58 (reading-time + activity dashboard).
//
// Key decisions:
// - Actor-isolated so a sweep over a large session history runs OFF the main
//   actor and never janks the UI.
// - The snapshot is derived ENTIRELY from ReadingSession + Book rows in ONE
//   ModelContext pass. It does NOT read ReadingStats — every displayed number
//   (per-window totals, per-book reading-seconds, lastReadAt, lifetimeTotal,
//   trackingSince) is computed from the session rows. ReadingStats is a derived
//   cache for the Library list's sort only; recomputing from the source rows
//   means a stale ReadingStats can never desync the dashboard, and there is no
//   torn-read window vs a concurrent ReadingSessionTracker write.
// - `calendarProvider` is a closure, not a stored Calendar, so a long-lived
//   aggregator picks up a timezone/DST change on the NEXT snapshot.
//
// @coordinates-with: ReadingStatsModels.swift, ReadingSession.swift, Book.swift

import Foundation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.vreader.app", category: "ReadingStats")

/// The boundary the dashboard ViewModel depends on, so tests can inject a mock.
protocol ReadingStatsAggregating: Sendable {
    /// Produces a dashboard snapshot for the given enum window + optional
    /// custom range. When `customRange` is non-nil and valid, the snapshot's
    /// `perBook` reflects the custom range and `customRangeBreakdown` carries
    /// the range's total; the seven enum `windowTotals` are still populated
    /// so the pill bar can render every window's total alongside the active
    /// Custom pill.
    ///
    /// Feature #58 WI-6b — the `customRange` argument is purely additive; a
    /// caller passing nil (the WI-1..WI-6a default path) gets the original
    /// behaviour.
    func snapshot(
        window: ReadingStatsWindow,
        sort: ReadingDashboardSort,
        now: Date,
        customRange: ReadingStatsCustomRange?
    ) async throws -> ReadingDashboardSnapshot
}

extension ReadingStatsAggregating {
    /// Backward-compatible no-customRange overload (the original WI-2 shape).
    func snapshot(
        window: ReadingStatsWindow,
        sort: ReadingDashboardSort,
        now: Date
    ) async throws -> ReadingDashboardSnapshot {
        try await snapshot(window: window, sort: sort, now: now, customRange: nil)
    }
}

/// Aggregates `ReadingSession` rows into a `ReadingDashboardSnapshot`.
actor ReadingStatsAggregator: ReadingStatsAggregating {
    private let modelContainer: ModelContainer
    private let calendarProvider: @Sendable () -> Calendar

    /// - Parameters:
    ///   - modelContainer: the SwiftData container (same one `PersistenceActor` uses).
    ///   - calendarProvider: resolves the calendar/timezone per snapshot call.
    ///     Defaults to `.current` so window boundaries follow the device.
    init(
        modelContainer: ModelContainer,
        calendarProvider: @Sendable @escaping () -> Calendar = { .current }
    ) {
        self.modelContainer = modelContainer
        self.calendarProvider = calendarProvider
    }

    /// Produces one consistent dashboard render.
    ///
    /// - Parameters:
    ///   - window: which enum window the per-book table is computed for (when
    ///     `customRange` is nil or invalid).
    ///   - sort: the per-book table sort.
    ///   - now: the reference instant — injectable for deterministic tests.
    ///   - customRange: optional user-picked range; when non-nil and valid, the
    ///     `perBook` rows + `customRangeBreakdown` reflect this range and the
    ///     `window` argument only sets `activeWindow` (the pill-bar state).
    func snapshot(
        window: ReadingStatsWindow,
        sort: ReadingDashboardSort,
        now: Date,
        customRange: ReadingStatsCustomRange? = nil
    ) async throws -> ReadingDashboardSnapshot {
        let calendar = calendarProvider()
        let context = ModelContext(modelContainer)

        // ONE pass: fetch every session + every book.
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        let books = try context.fetch(FetchDescriptor<Book>())

        // Index books by fingerprint key for the per-book join.
        // First-wins on a duplicate key (mirrors PersistenceActor+Library's
        // data-integrity guard against duplicate rows).
        var bookByKey: [String: Book] = [:]
        for book in books where bookByKey[book.fingerprintKey] == nil {
            bookByKey[book.fingerprintKey] = book
        }

        let windowTotals = computeWindowTotals(sessions: sessions, now: now, calendar: calendar)
        let lifetimeTotalSeconds = sessions.reduce(0) { $0 + max(0, $1.durationSeconds) }
        let trackingSince = sessions.map(\.startedAt).min()

        // Decide whether the user-picked custom range supplants the enum window
        // for the per-book table. An invalid range (start > end) is silently
        // dropped — picker UI surfaces the error; the model returns a clean
        // window-only snapshot (customRangeBreakdown=nil) so the dashboard
        // doesn't render a stale Custom hero.
        let activeCustom: ReadingStatsCustomRange? = {
            guard let r = customRange, r.isValid(calendar: calendar) else { return nil }
            return r
        }()

        let perBook: [PerBookStatsRow]
        let customBreakdown: CustomRangeBreakdown?
        if let custom = activeCustom {
            perBook = computePerBookForCustom(
                sessions: sessions, bookByKey: bookByKey,
                range: custom, sort: sort, calendar: calendar
            )
            customBreakdown = computeCustomBreakdown(
                sessions: sessions, range: custom, calendar: calendar
            )
        } else {
            perBook = computePerBook(
                sessions: sessions, bookByKey: bookByKey,
                window: window, sort: sort, now: now, calendar: calendar
            )
            customBreakdown = nil
        }

        log.info("dashboard snapshot: \(sessions.count) sessions, \(perBook.count) books, window=\(window.rawValue, privacy: .public), custom=\(activeCustom != nil)")

        return ReadingDashboardSnapshot(
            windowTotals: windowTotals,
            activeWindow: window,
            perBook: perBook,
            lifetimeTotalSeconds: lifetimeTotalSeconds,
            trackingSince: trackingSince,
            customRangeBreakdown: customBreakdown
        )
    }

    // MARK: - Custom-range computations (WI-6b)

    /// Sums durations of sessions whose `startedAt` lies inside the custom
    /// range — matches the enum-window bucketing rule (sessions are
    /// bucketed by start, not by overlap).
    private func computeCustomBreakdown(
        sessions: [ReadingSession],
        range: ReadingStatsCustomRange,
        calendar: Calendar
    ) -> CustomRangeBreakdown {
        var totalSeconds = 0
        var sessionCount = 0
        for session in sessions
        where range.contains(session.startedAt, calendar: calendar) {
            totalSeconds += max(0, session.durationSeconds)
            sessionCount += 1
        }
        return CustomRangeBreakdown(
            range: range, totalSeconds: totalSeconds, sessionCount: sessionCount
        )
    }

    /// Per-book rows for a custom range. Mirrors `computePerBook` but uses the
    /// range's `contains(_:calendar:)` instead of the enum window's predicate.
    private func computePerBookForCustom(
        sessions: [ReadingSession], bookByKey: [String: Book],
        range: ReadingStatsCustomRange, sort: ReadingDashboardSort,
        calendar: Calendar
    ) -> [PerBookStatsRow] {
        var sessionsByKey: [String: [ReadingSession]] = [:]
        for session in sessions {
            sessionsByKey[session.bookFingerprintKey, default: []].append(session)
        }

        let allKeys = Set(bookByKey.keys).union(sessionsByKey.keys)
        let rows = allKeys.map { key -> PerBookStatsRow in
            let bookSessions = sessionsByKey[key] ?? []
            let inRangeSeconds = bookSessions
                .filter { range.contains($0.startedAt, calendar: calendar) }
                .reduce(0) { $0 + max(0, $1.durationSeconds) }
            let lastReadAt = bookSessions
                .map { $0.endedAt ?? $0.startedAt }
                .max()
            if let book = bookByKey[key] {
                return PerBookStatsRow(
                    id: key, bookFingerprintKey: key, title: book.title, isDeleted: false,
                    readingSecondsInWindow: inRangeSeconds,
                    notesCount: book.annotations.count,
                    highlightsCount: book.highlights.count,
                    lastReadAt: lastReadAt
                )
            } else {
                return PerBookStatsRow(
                    id: key, bookFingerprintKey: key, title: "(deleted)", isDeleted: true,
                    readingSecondsInWindow: inRangeSeconds,
                    notesCount: 0, highlightsCount: 0,
                    lastReadAt: lastReadAt
                )
            }
        }
        return PerBookStatsRow.sorted(rows, by: sort)
    }

    // MARK: - Window totals

    /// Sums `durationSeconds` (clamped to ≥0) per window, bucketing each session
    /// by whether its `startedAt` falls in the window's half-open `[start, now)`.
    private func computeWindowTotals(
        sessions: [ReadingSession], now: Date, calendar: Calendar
    ) -> [WindowTotal] {
        ReadingStatsWindow.allCases.map { window in
            var totalSeconds = 0
            var sessionCount = 0
            for session in sessions
            where window.contains(session.startedAt, now: now, calendar: calendar) {
                totalSeconds += max(0, session.durationSeconds)
                sessionCount += 1
            }
            return WindowTotal(window: window, totalSeconds: totalSeconds, sessionCount: sessionCount)
        }
    }

    // MARK: - Per-book rows

    /// Builds the per-book table for `window`: one row per book key in the
    /// UNION of (every live `Book` key) and (every key seen in the sessions).
    ///
    /// - A live `Book` with sessions → title + cascade-scoped highlight/note
    ///   counts + reading seconds derived from its sessions.
    /// - A live `Book` with NO sessions → still shown as a `0m` row (plan
    ///   edge case (a)) — `lastReadAt` nil, in-window seconds 0.
    /// - A session key with no `Book` row → a deleted book: `isDeleted`,
    ///   title "(deleted)", zero notes/highlights (cascade-deleted with the
    ///   `Book`), reading seconds still derived from the surviving sessions.
    ///
    /// Reading seconds / `lastReadAt` are derived from `ReadingSession` rows
    /// ONLY — `ReadingStats` is never read (the F10 consistency model).
    private func computePerBook(
        sessions: [ReadingSession], bookByKey: [String: Book],
        window: ReadingStatsWindow, sort: ReadingDashboardSort,
        now: Date, calendar: Calendar
    ) -> [PerBookStatsRow] {
        // Group sessions by book key.
        var sessionsByKey: [String: [ReadingSession]] = [:]
        for session in sessions {
            sessionsByKey[session.bookFingerprintKey, default: []].append(session)
        }

        // The row set is the union of live-book keys and session keys: a live
        // book with no sessions still gets a 0m row; an orphan session key
        // (deleted book) still surfaces its history.
        let allKeys = Set(bookByKey.keys).union(sessionsByKey.keys)

        let rows = allKeys.map { key -> PerBookStatsRow in
            let bookSessions = sessionsByKey[key] ?? []
            let inWindowSeconds = bookSessions
                .filter { window.contains($0.startedAt, now: now, calendar: calendar) }
                .reduce(0) { $0 + max(0, $1.durationSeconds) }
            let lastReadAt = bookSessions
                .map { $0.endedAt ?? $0.startedAt }
                .max()

            if let book = bookByKey[key] {
                return PerBookStatsRow(
                    id: key, bookFingerprintKey: key, title: book.title, isDeleted: false,
                    readingSecondsInWindow: inWindowSeconds,
                    notesCount: book.annotations.count,
                    highlightsCount: book.highlights.count,
                    lastReadAt: lastReadAt
                )
            } else {
                // Deleted book: highlights/notes cascade-deleted with the Book.
                return PerBookStatsRow(
                    id: key, bookFingerprintKey: key, title: "(deleted)", isDeleted: true,
                    readingSecondsInWindow: inWindowSeconds,
                    notesCount: 0, highlightsCount: 0,
                    lastReadAt: lastReadAt
                )
            }
        }
        return PerBookStatsRow.sorted(rows, by: sort)
    }
}
