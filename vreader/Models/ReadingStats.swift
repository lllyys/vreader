// Purpose: Aggregated reading statistics per book.
// Recomputed from ReadingSession records.
//
// Key decisions:
// - bookFingerprintKey is @Attribute(.unique) — one stats record per book.
// - All computed fields (averages, totals) can be recomputed from sessions.

import Foundation
import SwiftData

@Model
final class ReadingStats {
    /// Primitive unique key matching Book.fingerprintKey.
    @Attribute(.unique) var bookFingerprintKey: String

    var bookFingerprint: DocumentFingerprint
    var totalReadingSeconds: Int
    var sessionCount: Int
    var lastReadAt: Date?
    var averagePagesPerHour: Double?
    var averageWordsPerMinute: Double?
    var totalPagesRead: Int?
    var totalWordsRead: Int?
    var longestSessionSeconds: Int

    // MARK: - Init

    init(
        bookFingerprint: DocumentFingerprint,
        totalReadingSeconds: Int = 0,
        sessionCount: Int = 0,
        lastReadAt: Date? = nil,
        averagePagesPerHour: Double? = nil,
        averageWordsPerMinute: Double? = nil,
        totalPagesRead: Int? = nil,
        totalWordsRead: Int? = nil,
        longestSessionSeconds: Int = 0
    ) {
        self.bookFingerprintKey = bookFingerprint.canonicalKey
        self.bookFingerprint = bookFingerprint
        self.totalReadingSeconds = max(0, totalReadingSeconds)
        self.sessionCount = max(0, sessionCount)
        self.lastReadAt = lastReadAt
        self.averagePagesPerHour = averagePagesPerHour
        self.averageWordsPerMinute = averageWordsPerMinute
        self.totalPagesRead = totalPagesRead.map { max(0, $0) }
        self.totalWordsRead = totalWordsRead.map { max(0, $0) }
        self.longestSessionSeconds = max(0, longestSessionSeconds)
    }

    // MARK: - Recomputation

    /// Recomputes all aggregate fields from the given sessions.
    /// Idempotent — safe to call repeatedly.
    /// Sanitizes input: negative durations/counts are clamped to 0.
    func recompute(from sessions: [ReadingSession]) {
        let validSessions = sessions.filter { $0.bookFingerprintKey == bookFingerprintKey }

        sessionCount = validSessions.count

        // Safe accumulation: clamp negatives and use Int64 to avoid overflow
        var totalSeconds: Int64 = 0
        var maxSeconds = 0
        for session in validSessions {
            let clamped = max(0, session.durationSeconds)
            totalSeconds += Int64(clamped)
            maxSeconds = max(maxSeconds, clamped)
        }
        totalReadingSeconds = Int(min(totalSeconds, Int64(Int.max)))
        longestSessionSeconds = maxSeconds
        lastReadAt = validSessions.compactMap(\.endedAt).max() ?? validSessions.map(\.startedAt).max()

        let pages = validSessions.compactMap(\.pagesRead).map { max(0, $0) }
        totalPagesRead = pages.isEmpty ? nil : pages.reduce(0) { result, val in
            let (sum, overflow) = result.addingReportingOverflow(val)
            return overflow ? Int.max : sum
        }

        let words = validSessions.compactMap(\.wordsRead).map { max(0, $0) }
        totalWordsRead = words.isEmpty ? nil : words.reduce(0) { result, val in
            let (sum, overflow) = result.addingReportingOverflow(val)
            return overflow ? Int.max : sum
        }

        // Averages
        let totalHours = Double(totalReadingSeconds) / 3600.0
        if let totalPages = totalPagesRead, totalHours > 0 {
            averagePagesPerHour = Double(totalPages) / totalHours
        } else {
            averagePagesPerHour = nil
        }

        let totalMinutes = Double(totalReadingSeconds) / 60.0
        if let totalWords = totalWordsRead, totalMinutes > 0 {
            averageWordsPerMinute = Double(totalWords) / totalMinutes
        } else {
            averageWordsPerMinute = nil
        }
    }
}
