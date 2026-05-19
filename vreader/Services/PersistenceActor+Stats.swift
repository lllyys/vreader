// Purpose: Extension adding reading stats recomputation to PersistenceActor.
// Aggregates ReadingSession records into a ReadingStats record per book.
//
// Key decisions:
// - Upserts ReadingStats: creates if missing, updates if exists.
// - Recomputes all aggregate fields from sessions (idempotent).
// - Called after session end so library sorting by reading time/last read works.
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
