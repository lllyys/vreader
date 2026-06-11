// Purpose: Extension adding reading stats recomputation to PersistenceActor.
// Aggregates ReadingSession records into a ReadingStats record per book.
//
// Key decisions:
// - Upserts ReadingStats: creates if missing, updates if exists.
// - Recomputes all aggregate fields from sessions (idempotent).
// - Called after session end so library sorting by reading time/last read works.
// - DEBUG-only seedSyntheticReadingSessions inserts a deterministic session
//   spread for the Bug #263 verification harness — see the #if DEBUG block.
//
// @coordinates-with: PersistenceActor.swift, ReadingStats.swift, ReadingSession.swift

import Foundation
import SwiftData

extension PersistenceActor {

    /// Recomputes the ReadingStats record for a book from all its ReadingSession records.
    /// Creates the stats record if it doesn't exist yet (upsert).
    func recomputeStats(bookFingerprintKey: String, bookFingerprint: DocumentFingerprint) async throws {
        let context = ModelContext(modelContainer)

        // Fetch all sessions for this book
        let key = bookFingerprintKey
        let sessionPredicate = #Predicate<ReadingSession> {
            $0.bookFingerprintKey == key
        }
        let sessions = try context.fetch(
            FetchDescriptor<ReadingSession>(predicate: sessionPredicate)
        )

        // Find or create stats record
        let statsPredicate = #Predicate<ReadingStats> {
            $0.bookFingerprintKey == key
        }
        var statsDescriptor = FetchDescriptor<ReadingStats>(predicate: statsPredicate)
        statsDescriptor.fetchLimit = 1

        let stats: ReadingStats
        if let existing = try context.fetch(statsDescriptor).first {
            stats = existing
        } else {
            stats = ReadingStats(bookFingerprint: bookFingerprint)
            context.insert(stats)
        }

        stats.recompute(from: sessions)
        // Bug #45 v5: Always set lastReadAt to now.
        // recompute() derives lastReadAt from session endedAt, but sessions
        // shorter than 5s are discarded — leaving lastReadAt nil for quick opens.
        // Since recomputeStats is only called from reader close(), "now" is correct.
        stats.lastReadAt = Date()
        try context.save()
    }

    // MARK: - Read side (feature #58 WI-2)

    /// Returns every `ReadingSession` row as a value-typed record.
    ///
    /// Used by the feature #58 WebDAV backup collector (WI-5). The reading-stats
    /// dashboard aggregator does NOT consume this — it owns its own
    /// `ModelContainer`/`ModelContext` pass so its snapshot stays internally
    /// consistent. This exists so `collectReadingHistory` has a value-typed read
    /// without the collector touching `@Model` rows directly.
    func fetchAllReadingSessions() async throws -> [ReadingSessionRecord] {
        let context = ModelContext(modelContainer)
        let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
        return sessions.map { session in
            ReadingSessionRecord(
                sessionId: session.sessionId,
                bookFingerprintKey: session.bookFingerprintKey,
                startedAt: session.startedAt,
                endedAt: session.endedAt,
                durationSeconds: session.durationSeconds,
                pagesRead: session.pagesRead,
                wordsRead: session.wordsRead,
                startLocator: session.startLocator,
                endLocator: session.endLocator,
                deviceId: session.deviceId,
                isRecovered: session.isRecovered
            )
        }
    }

    /// Returns every `ReadingStats` row as a value-typed record.
    ///
    /// Deduplicates by `bookFingerprintKey` (first-wins), mirroring
    /// `fetchAllLibraryBooks`'s duplicate-row data-integrity guard. Used by the
    /// feature #58 WebDAV backup collector (WI-5).
    /// Feature #101: the per-book stats fetch — one record, filtered in the
    /// store (avoids the O(library) all-books scan at reader open).
    func readingStats(forBookWithKey key: String) async throws -> ReadingStatsRecord? {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<ReadingStats>(
            predicate: #Predicate { $0.bookFingerprintKey == key }
        )
        descriptor.fetchLimit = 1
        guard let stats = try context.fetch(descriptor).first else { return nil }
        return ReadingStatsRecord(
            bookFingerprintKey: stats.bookFingerprintKey,
            totalReadingSeconds: stats.totalReadingSeconds,
            sessionCount: stats.sessionCount,
            lastReadAt: stats.lastReadAt,
            averagePagesPerHour: stats.averagePagesPerHour,
            averageWordsPerMinute: stats.averageWordsPerMinute,
            totalPagesRead: stats.totalPagesRead,
            totalWordsRead: stats.totalWordsRead,
            longestSessionSeconds: stats.longestSessionSeconds
        )
    }

    /// Feature #101 WI-2a: the earliest session start for one book — the
    /// "since <date>" half of Book details' "N sessions since Mar 2" sub
    /// line. Filtered + sorted in the store with fetchLimit 1 (avoids the
    /// O(history) all-sessions scan at sheet-open).
    func firstSessionDate(forBookWithKey key: String) async throws -> Date? {
        let context = ModelContext(modelContainer)
        var descriptor = FetchDescriptor<ReadingSession>(
            predicate: #Predicate { $0.bookFingerprintKey == key },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.startedAt
    }

    func fetchAllReadingStats() async throws -> [ReadingStatsRecord] {
        let context = ModelContext(modelContainer)
        let rows = try context.fetch(FetchDescriptor<ReadingStats>())
        var seen = Set<String>()
        var records: [ReadingStatsRecord] = []
        for stats in rows where seen.insert(stats.bookFingerprintKey).inserted {
            records.append(ReadingStatsRecord(
                bookFingerprintKey: stats.bookFingerprintKey,
                totalReadingSeconds: stats.totalReadingSeconds,
                sessionCount: stats.sessionCount,
                lastReadAt: stats.lastReadAt,
                averagePagesPerHour: stats.averagePagesPerHour,
                averageWordsPerMinute: stats.averageWordsPerMinute,
                totalPagesRead: stats.totalPagesRead,
                totalWordsRead: stats.totalWordsRead,
                longestSessionSeconds: stats.longestSessionSeconds
            ))
        }
        return records
    }
}

#if DEBUG

extension PersistenceActor {

    /// Bug #263 — verification harness reading-session seeder.
    ///
    /// Inserts a deterministic spread of synthetic `ReadingSession` rows for
    /// `bookFingerprint` so the reading dashboard (Feature #58) renders
    /// non-zero per-window totals CU-free. Rows are inserted through the same
    /// `ModelContext`/`ReadingSession` path the production
    /// `SwiftDataSessionStore.saveSession` uses, so the dashboard aggregator
    /// reads them through its normal SwiftData query — there is no parallel
    /// persistence path. After inserting, refreshes the book's `ReadingStats`
    /// aggregate so the Library list's reading-time sort also reflects the
    /// seeded sessions (parity with the reader-close path).
    ///
    /// Six sessions are inserted, one per bounded time band:
    /// - **today** — anchored at the midpoint of the elapsed local day
    ///   (`[startOfDay(now), now)`), so it ALWAYS lands inside the "today"
    ///   window regardless of when the command runs (including the first hour
    ///   after midnight, where a fixed `now − 1h` offset would slip into
    ///   yesterday). This is the round-1 audit fix for the midnight edge.
    /// - **7d / 30d / 90d / 180d** — anchored mid-window at `now − {3d, 15d,
    ///   60d, 120d}` (fixed rolling offsets that land comfortably inside each
    ///   rolling window, not on its edge).
    /// - **year/all** — anchored at `now − 300d`.
    ///
    /// Because the dashboard's windows nest (today ⊂ 7d ⊂ 30d ⊂ 90d ⊂ 180d ⊂
    /// allTime), the cumulative per-window totals are strictly increasing
    /// (today < 7d < 30d < 90d < 180d < allTime) — exactly what makes Feature
    /// #58 criterion (b) "all windows render correct (differing) totals"
    /// verifiable. Each session is a closed `[startedAt, endedAt]` interval
    /// lasting `secondsPerSession`, so the per-book table's last-read column
    /// also has data.
    ///
    /// Caveat: the "Year" window is calendar-YTD (Jan 1 → now), so the
    /// now−300d session lands in "Year" only when `now − 300d` is still in the
    /// current calendar year. Within ~300 days of Jan 1 the "Year" total
    /// equals the 180d total (5 sessions) rather than 6 — `Year ≥ 180d` and
    /// `Year ≤ allTime` always hold (the invariants a verify run asserts), but
    /// the exact "Year" multiple is date-dependent. The other six windows are
    /// run-time-independent.
    ///
    /// - Parameters:
    ///   - bookFingerprint: the book the synthetic sessions attach to. Need
    ///     not have a `Book` row (an orphan key surfaces as the dashboard's
    ///     "(deleted)" row).
    ///   - secondsPerSession: each session's `durationSeconds` (caller has
    ///     validated ≥ 1).
    ///   - now: the reference instant the bands anchor against — injectable so
    ///     tests assert exact per-window totals deterministically. Defaults to
    ///     `Date()` for the production URL path.
    ///   - calendar: resolves the local-start-of-day for the "today" band.
    ///     Defaults to `.current` (matching the aggregator's default) so the
    ///     today anchor uses the same day boundary the dashboard does; tests
    ///     pin a fixed-timezone calendar.
    /// - Returns: the number of sessions inserted (always 6).
    @discardableResult
    func seedSyntheticReadingSessions(
        bookFingerprint: DocumentFingerprint,
        secondsPerSession: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> Int {
        // The "today" anchor is the midpoint of the elapsed local day, so it is
        // always strictly inside [startOfDay(now), now) — midnight-edge safe.
        let startOfToday = calendar.startOfDay(for: now)
        let todayAnchor = startOfToday.addingTimeInterval(
            max(1, now.timeIntervalSince(startOfToday) / 2)
        )

        // Mid-window anchors for the rolling / YTD bands.
        let bandStarts: [Date] = [
            todayAnchor,                            // today (+ every wider window)
            now.addingTimeInterval(-3 * 86_400),    // 7d   (+ wider)
            now.addingTimeInterval(-15 * 86_400),   // 30d  (+ wider)
            now.addingTimeInterval(-60 * 86_400),   // 90d  (+ wider)
            now.addingTimeInterval(-120 * 86_400),  // 180d (+ wider)
            now.addingTimeInterval(-300 * 86_400),  // year/all
        ]

        let context = ModelContext(modelContainer)
        let duration = max(1, secondsPerSession)
        for startedAt in bandStarts {
            // Clamp endedAt to `now` so a seeded session never extends into the
            // future. This matters for the today band near midnight: its
            // startedAt is `startOfDay + elapsed/2`, so `startedAt + duration`
            // can exceed `now` for runs within ~`2 * duration` of midnight,
            // producing a future per-book lastReadAt. durationSeconds stays the
            // requested value (so per-window totals are exact); only the
            // displayed [startedAt, endedAt] interval is clamped. (Round-2
            // audit fix.)
            let endedAt = min(startedAt.addingTimeInterval(Double(duration)), now)
            let session = ReadingSession(
                bookFingerprint: bookFingerprint,
                startedAt: startedAt,
                endedAt: endedAt,
                durationSeconds: duration,
                deviceId: "debug-seed"
            )
            context.insert(session)
        }
        try context.save()

        // Refresh the per-book ReadingStats aggregate (Library sort parity).
        try await recomputeStats(
            bookFingerprintKey: bookFingerprint.canonicalKey,
            bookFingerprint: bookFingerprint
        )

        return bandStarts.count
    }
}

#endif

// Feature #101: the reader lifecycle's once-at-open stats seam.
extension PersistenceActor: BookReadingStatsProviding {}
