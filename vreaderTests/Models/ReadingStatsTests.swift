// Purpose: Tests for ReadingStats model — initialization, recomputation from sessions, edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("ReadingStats")
struct ReadingStatsTests {

    static let sampleFP = DocumentFingerprint(
        contentSHA256: "stats123", fileByteCount: 1024, format: .epub
    )

    // MARK: - Initialization

    @Test func initSetsDefaults() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        #expect(stats.bookFingerprintKey == Self.sampleFP.canonicalKey)
        #expect(stats.totalReadingSeconds == 0)
        #expect(stats.sessionCount == 0)
        #expect(stats.lastReadAt == nil)
        #expect(stats.averagePagesPerHour == nil)
        #expect(stats.averageWordsPerMinute == nil)
        #expect(stats.totalPagesRead == nil)
        #expect(stats.totalWordsRead == nil)
        #expect(stats.longestSessionSeconds == 0)
    }

    @Test func bookFingerprintKeyMatchesFingerprint() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        #expect(stats.bookFingerprintKey == Self.sampleFP.canonicalKey)
    }

    // MARK: - Recomputation

    @Test func recomputeFromSingleSession() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        let endDate = Date(timeIntervalSince1970: 1_700_001_800)
        let session = ReadingSession(
            bookFingerprint: Self.sampleFP,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: endDate,
            durationSeconds: 1800,
            pagesRead: 10,
            wordsRead: 3000,
            deviceId: "device-1"
        )

        stats.recompute(from: [session])

        #expect(stats.sessionCount == 1)
        #expect(stats.totalReadingSeconds == 1800)
        #expect(stats.longestSessionSeconds == 1800)
        #expect(stats.totalPagesRead == 10)
        #expect(stats.totalWordsRead == 3000)
        #expect(stats.lastReadAt == endDate)
    }

    @Test func recomputeFromMultipleSessions() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        let session1 = ReadingSession(
            bookFingerprint: Self.sampleFP,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_001_800),
            durationSeconds: 1800,
            pagesRead: 10,
            wordsRead: 3000,
            deviceId: "device-1"
        )
        let session2 = ReadingSession(
            bookFingerprint: Self.sampleFP,
            startedAt: Date(timeIntervalSince1970: 1_700_100_000),
            endedAt: Date(timeIntervalSince1970: 1_700_103_600),
            durationSeconds: 3600,
            pagesRead: 20,
            wordsRead: 6000,
            deviceId: "device-1"
        )

        stats.recompute(from: [session1, session2])

        #expect(stats.sessionCount == 2)
        #expect(stats.totalReadingSeconds == 5400)  // 1800 + 3600
        #expect(stats.longestSessionSeconds == 3600)
        #expect(stats.totalPagesRead == 30)  // 10 + 20
        #expect(stats.totalWordsRead == 9000)  // 3000 + 6000
    }

    @Test func recomputeIgnoresSessionsFromOtherBooks() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        let otherFP = DocumentFingerprint(contentSHA256: "other", fileByteCount: 999, format: .pdf)
        let mySession = ReadingSession(
            bookFingerprint: Self.sampleFP,
            durationSeconds: 1800,
            pagesRead: 10
        )
        let otherSession = ReadingSession(
            bookFingerprint: otherFP,
            durationSeconds: 9999,
            pagesRead: 100
        )

        stats.recompute(from: [mySession, otherSession])

        #expect(stats.sessionCount == 1)
        #expect(stats.totalReadingSeconds == 1800)
        #expect(stats.totalPagesRead == 10)
    }

    @Test func recomputeAveragePagesPerHour() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        let session = ReadingSession(
            bookFingerprint: Self.sampleFP,
            durationSeconds: 3600,  // 1 hour
            pagesRead: 30
        )

        stats.recompute(from: [session])

        #expect(stats.averagePagesPerHour == 30.0)
    }

    @Test func recomputeAverageWordsPerMinute() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        let session = ReadingSession(
            bookFingerprint: Self.sampleFP,
            durationSeconds: 600,  // 10 minutes
            pagesRead: nil,
            wordsRead: 2500
        )

        stats.recompute(from: [session])

        #expect(stats.averageWordsPerMinute == 250.0)
    }

    // MARK: - Recomputation Edge Cases

    @Test func recomputeFromEmptySessions() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        // Pre-set some values
        stats.sessionCount = 5
        stats.totalReadingSeconds = 9999

        stats.recompute(from: [])

        #expect(stats.sessionCount == 0)
        #expect(stats.totalReadingSeconds == 0)
        #expect(stats.longestSessionSeconds == 0)
        #expect(stats.lastReadAt == nil)
        #expect(stats.averagePagesPerHour == nil)
        #expect(stats.averageWordsPerMinute == nil)
    }

    @Test func recomputeIsIdempotent() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        let session = ReadingSession(
            bookFingerprint: Self.sampleFP,
            durationSeconds: 1800,
            pagesRead: 10,
            wordsRead: 3000
        )

        stats.recompute(from: [session])
        let firstCount = stats.sessionCount
        let firstDuration = stats.totalReadingSeconds

        stats.recompute(from: [session])
        #expect(stats.sessionCount == firstCount)
        #expect(stats.totalReadingSeconds == firstDuration)
    }

    @Test func recomputeWithSessionsLackingPagesAndWords() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        let session = ReadingSession(
            bookFingerprint: Self.sampleFP,
            durationSeconds: 1800,
            pagesRead: nil,
            wordsRead: nil
        )

        stats.recompute(from: [session])

        #expect(stats.sessionCount == 1)
        #expect(stats.totalReadingSeconds == 1800)
        #expect(stats.totalPagesRead == nil)
        #expect(stats.totalWordsRead == nil)
        #expect(stats.averagePagesPerHour == nil)
        #expect(stats.averageWordsPerMinute == nil)
    }

    @Test func recomputeWithZeroDurationSessions() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        let session = ReadingSession(
            bookFingerprint: Self.sampleFP,
            durationSeconds: 0,
            pagesRead: 5,
            wordsRead: 1000
        )

        stats.recompute(from: [session])

        #expect(stats.sessionCount == 1)
        #expect(stats.totalReadingSeconds == 0)
        // Averages should be nil when duration is 0 (avoid division by zero)
        #expect(stats.averagePagesPerHour == nil)
        #expect(stats.averageWordsPerMinute == nil)
    }

    @Test func recomputeLastReadAtUsesLatestEndDate() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let late = Date(timeIntervalSince1970: 1_700_100_000)

        let session1 = ReadingSession(
            bookFingerprint: Self.sampleFP,
            startedAt: early,
            endedAt: early,
            durationSeconds: 100
        )
        let session2 = ReadingSession(
            bookFingerprint: Self.sampleFP,
            startedAt: late,
            endedAt: late,
            durationSeconds: 200
        )

        stats.recompute(from: [session1, session2])
        #expect(stats.lastReadAt == late)
    }

    @Test func recomputeLastReadAtFallsBackToStartedAt() {
        let stats = ReadingStats(bookFingerprint: Self.sampleFP)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = ReadingSession(
            bookFingerprint: Self.sampleFP,
            startedAt: start,
            endedAt: nil,  // Session not ended
            durationSeconds: 100
        )

        stats.recompute(from: [session])
        #expect(stats.lastReadAt == start)
    }
}
