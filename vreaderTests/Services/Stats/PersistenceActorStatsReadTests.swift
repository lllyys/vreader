// Purpose: Tests for PersistenceActor's reading-history read methods
// (fetchAllReadingSessions / fetchAllReadingStats) added in feature #58 WI-2.

import Foundation
import SwiftData
import Testing
@testable import vreader

@Suite("PersistenceActor reading-history reads")
struct PersistenceActorStatsReadTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func fingerprint(_ seed: String) -> DocumentFingerprint {
        var hex = ""
        let bytes = Array(seed.utf8)
        var i = 0
        while hex.count < 64 {
            hex += String(format: "%02x", bytes[i % bytes.count] &+ UInt8(i))
            i += 1
        }
        return DocumentFingerprint(
            contentSHA256: String(hex.prefix(64)), fileByteCount: 2048, format: .epub
        )
    }

    @Test func fetchAllReadingSessionsEmptyStore() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        let sessions = try await actor.fetchAllReadingSessions()
        #expect(sessions.isEmpty)
    }

    @Test func fetchAllReadingSessionsProjectsEveryField() async throws {
        let container = try makeContainer()
        let fp = fingerprint("alpha")
        let started = Date(timeIntervalSince1970: 1_000_000)
        let ended = Date(timeIntervalSince1970: 1_000_600)
        let context = ModelContext(container)
        let session = ReadingSession(
            bookFingerprint: fp, startedAt: started, endedAt: ended,
            durationSeconds: 600, pagesRead: 12, wordsRead: 3400,
            deviceId: "device-xyz", isRecovered: true
        )
        context.insert(session)
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let records = try await actor.fetchAllReadingSessions()
        #expect(records.count == 1)
        let r = try #require(records.first)
        #expect(r.sessionId == session.sessionId)
        #expect(r.bookFingerprintKey == fp.canonicalKey)
        #expect(r.startedAt == started)
        #expect(r.endedAt == ended)
        #expect(r.durationSeconds == 600)
        #expect(r.pagesRead == 12)
        #expect(r.wordsRead == 3400)
        #expect(r.deviceId == "device-xyz")
        #expect(r.isRecovered == true)
    }

    @Test func fetchAllReadingStatsProjectsEveryField() async throws {
        let container = try makeContainer()
        let fp = fingerprint("bravo")
        let lastRead = Date(timeIntervalSince1970: 2_000_000)
        let context = ModelContext(container)
        let stats = ReadingStats(
            bookFingerprint: fp, totalReadingSeconds: 7200, sessionCount: 5,
            lastReadAt: lastRead, averagePagesPerHour: 30.0, averageWordsPerMinute: 220.0,
            totalPagesRead: 60, totalWordsRead: 26_400, longestSessionSeconds: 1800
        )
        context.insert(stats)
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let records = try await actor.fetchAllReadingStats()
        #expect(records.count == 1)
        let r = try #require(records.first)
        #expect(r.bookFingerprintKey == fp.canonicalKey)
        #expect(r.totalReadingSeconds == 7200)
        #expect(r.sessionCount == 5)
        #expect(r.lastReadAt == lastRead)
        #expect(r.averagePagesPerHour == 30.0)
        #expect(r.averageWordsPerMinute == 220.0)
        #expect(r.totalPagesRead == 60)
        #expect(r.totalWordsRead == 26_400)
        #expect(r.longestSessionSeconds == 1800)
    }

    @Test func fetchAllReadingSessionsReturnsAllRows() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        for i in 0..<5 {
            context.insert(ReadingSession(
                bookFingerprint: fingerprint("book\(i)"),
                startedAt: Date(timeIntervalSince1970: Double(i) * 1000),
                durationSeconds: 100 + i
            ))
        }
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let records = try await actor.fetchAllReadingSessions()
        #expect(records.count == 5)
        #expect(Set(records.map(\.durationSeconds)) == [100, 101, 102, 103, 104])
    }

    // MARK: - seedSyntheticReadingSessions (Bug #263 — verification harness)

    /// A noon-UTC anchor avoids the `today` midnight edge: every band offset
    /// stays inside the calendar day / rolling window it is meant for.
    private func utcCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func noonAnchor() -> Date {
        // 2026-06-15 12:00:00 UTC — far enough into the year that the 300d band
        // crosses Jan 1 (so it lands OUTSIDE the calendar-YTD "Year" window),
        // and the day is mid-month so no rolling band straddles a month edge.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 15
        comps.hour = 12; comps.minute = 0; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")!
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    @Test func seedSyntheticReadingSessions_insertsSixDeterministicSessions() async throws {
        let container = try makeContainer()
        let actor = PersistenceActor(modelContainer: container)
        let fp = fingerprint("seeded-book")
        let key = fp.canonicalKey

        let count = try await actor.seedSyntheticReadingSessions(
            bookFingerprint: fp, secondsPerSession: 600, now: noonAnchor(), calendar: utcCalendar()
        )

        #expect(count == 6)
        let sessions = try await actor.fetchAllReadingSessions()
        #expect(sessions.count == 6)
        // Every seeded session is attached to the requested book.
        #expect(sessions.allSatisfy { $0.bookFingerprintKey == key })
        // Every session carries the requested per-session duration and a closed
        // [startedAt, endedAt] interval (so the dashboard's lastRead column has data).
        #expect(sessions.allSatisfy { $0.durationSeconds == 600 })
        #expect(sessions.allSatisfy { $0.endedAt != nil })
    }

    @Test func seedSyntheticReadingSessions_producesNonZeroIncreasingWindowTotals() async throws {
        let container = try makeContainer()
        let actor = PersistenceActor(modelContainer: container)
        // Give the book a Book row too, so the per-book table joins a real title.
        let key = try await CollectionTestHelper.insertBook(
            persistence: actor, title: "Seeded Book", sha: String(repeating: "c", count: 64)
        )
        let fp = try #require(DocumentFingerprint(canonicalKey: key))
        let now = noonAnchor()
        let s = 600

        _ = try await actor.seedSyntheticReadingSessions(
            bookFingerprint: fp, secondsPerSession: s, now: now, calendar: utcCalendar()
        )

        // Drive the SAME container through the real dashboard aggregator with
        // the SAME now + a fixed UTC calendar → deterministic window totals.
        let aggregator = ReadingStatsAggregator(
            modelContainer: container, calendarProvider: { [cal = utcCalendar()] in cal }
        )
        let snap = try await aggregator.snapshot(window: .allTime, sort: .default, now: now)

        func total(_ w: ReadingStatsWindow) -> Int { snap.total(for: w).totalSeconds }

        // Bands: today (midpoint of elapsed day), now-3d, now-15d, now-60d,
        // now-120d, now-300d. Rolling windows nest, so cumulative totals are
        // exact multiples of s:
        #expect(total(.today) == 1 * s)      // today band only (inside the calendar day)
        #expect(total(.last7Days) == 2 * s)  // + now-3d
        #expect(total(.last30Days) == 3 * s) // + now-15d
        #expect(total(.last90Days) == 4 * s) // + now-60d
        #expect(total(.last180Days) == 5 * s) // + now-120d
        #expect(total(.allTime) == 6 * s)    // every session

        // Strictly increasing across the rolling bands — this is what makes
        // Feature #58 criterion (b) "all windows render correct (differing)
        // totals" verifiable CU-free.
        #expect(total(.today) < total(.last7Days))
        #expect(total(.last7Days) < total(.last30Days))
        #expect(total(.last30Days) < total(.last90Days))
        #expect(total(.last90Days) < total(.last180Days))
        #expect(total(.last180Days) < total(.allTime))

        // The calendar-YTD "Year" window is now-dependent; it is bounded between
        // the 180d total (its widest rolling subset here) and the all-time total.
        #expect(total(.last365Days) >= total(.last180Days))
        #expect(total(.last365Days) <= total(.allTime))

        // The per-book table has exactly one row for the seeded book with a
        // non-zero in-window reading time (criterion c — table renders).
        #expect(snap.perBook.count == 1)
        let row = try #require(snap.perBook.first)
        #expect(row.bookFingerprintKey == key)
        #expect(row.title == "Seeded Book")
        #expect(row.readingSecondsInWindow == 6 * s) // allTime window
        #expect(row.lastReadAt != nil)
    }

    @Test func seedSyntheticReadingSessions_respectsExplicitSeconds() async throws {
        let container = try makeContainer()
        let actor = PersistenceActor(modelContainer: container)
        let fp = fingerprint("seeded-900")

        _ = try await actor.seedSyntheticReadingSessions(
            bookFingerprint: fp, secondsPerSession: 900, now: noonAnchor(), calendar: utcCalendar()
        )

        let aggregator = ReadingStatsAggregator(
            modelContainer: container, calendarProvider: { [cal = utcCalendar()] in cal }
        )
        let snap = try await aggregator.snapshot(window: .allTime, sort: .default, now: noonAnchor())
        #expect(snap.total(for: .allTime).totalSeconds == 6 * 900)
        #expect(snap.lifetimeTotalSeconds == 6 * 900)
    }

    @Test func seedSyntheticReadingSessions_todayBandSurvivesMidnightEdge() async throws {
        // Round-1 audit fix: when the command runs in the first hour after
        // local midnight, a fixed `now − 1h` anchor would slip into yesterday
        // and the "today" window would render 0. The midpoint-of-elapsed-day
        // anchor must keep the today session inside [startOfDay, now).
        //
        // Round-2 audit fix: 00:10 is chosen so the today session's nominal
        // [startedAt, startedAt+600s] interval (00:05 → 00:15) would extend
        // PAST `now` (00:10). endedAt must be clamped to now so no seeded
        // session shows a future lastReadAt.
        let container = try makeContainer()
        let actor = PersistenceActor(modelContainer: container)
        let fp = fingerprint("midnight-edge")

        // 2026-06-15 00:10:00 UTC — 10 minutes after midnight.
        var comps = DateComponents()
        comps.year = 2026; comps.month = 6; comps.day = 15
        comps.hour = 0; comps.minute = 10; comps.second = 0
        comps.timeZone = TimeZone(identifier: "UTC")!
        let now = Calendar(identifier: .gregorian).date(from: comps)!

        _ = try await actor.seedSyntheticReadingSessions(
            bookFingerprint: fp, secondsPerSession: 600, now: now, calendar: utcCalendar()
        )

        // The today session still buckets into "today" and contributes its full
        // durationSeconds (totals use the stored int, not the clamped interval).
        let aggregator = ReadingStatsAggregator(
            modelContainer: container, calendarProvider: { [cal = utcCalendar()] in cal }
        )
        let snap = try await aggregator.snapshot(window: .today, sort: .default, now: now)
        #expect(snap.total(for: .today).totalSeconds == 600,
                "the today session must count even 10 min after midnight")
        #expect(snap.total(for: .today).sessionCount == 1)

        // No seeded session may show a future endedAt (would surface as a
        // future per-book lastReadAt + skew last-read sorting).
        let sessions = try await actor.fetchAllReadingSessions()
        #expect(sessions.allSatisfy { ($0.endedAt ?? $0.startedAt) <= now },
                "endedAt must be clamped to now near midnight")
        let row = try #require(snap.perBook.first { $0.bookFingerprintKey == fp.canonicalKey })
        let lastRead = try #require(row.lastReadAt)
        #expect(lastRead <= now, "per-book lastReadAt must not be in the future")
    }

    @Test func seedSyntheticReadingSessions_recomputesReadingStatsForBook() async throws {
        // The handler also refreshes ReadingStats so the Library list's
        // reading-time sort reflects the seeded sessions (parity with the
        // production reader-close path).
        let container = try makeContainer()
        let actor = PersistenceActor(modelContainer: container)
        let fp = fingerprint("seeded-stats")
        let key = fp.canonicalKey

        _ = try await actor.seedSyntheticReadingSessions(
            bookFingerprint: fp, secondsPerSession: 600, now: noonAnchor(), calendar: utcCalendar()
        )

        let stats = try await actor.fetchAllReadingStats()
        let row = try #require(stats.first { $0.bookFingerprintKey == key })
        #expect(row.totalReadingSeconds == 6 * 600)
        #expect(row.sessionCount == 6)
    }
}

// MARK: - readingStats(forBookWithKey:) (feature #101)

@Suite("PersistenceActor per-book stats fetch (feature #101)")
struct PersistenceActorPerBookStatsTests {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func fingerprint(_ seed: String) -> DocumentFingerprint {
        var hex = ""
        let bytes = Array(seed.utf8)
        var i = 0
        while hex.count < 64 {
            hex += String(format: "%02x", bytes[i % bytes.count] &+ UInt8(i))
            i += 1
        }
        return DocumentFingerprint(
            contentSHA256: String(hex.prefix(64)), fileByteCount: 2048, format: .epub
        )
    }

    @Test func returnsNilForUnknownBook() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        let record = try await actor.readingStats(forBookWithKey: "epub:none:0")
        #expect(record == nil)
    }

    @Test func returnsOnlyTheRequestedBooksRecord() async throws {
        let container = try makeContainer()
        let target = fingerprint("target")
        let other = fingerprint("other")
        let context = ModelContext(container)
        context.insert(ReadingStats(
            bookFingerprint: target, totalReadingSeconds: 24_000, sessionCount: 23,
            lastReadAt: Date(timeIntervalSince1970: 3_000_000),
            averagePagesPerHour: nil, averageWordsPerMinute: nil,
            totalPagesRead: nil, totalWordsRead: nil, longestSessionSeconds: 900
        ))
        context.insert(ReadingStats(
            bookFingerprint: other, totalReadingSeconds: 60, sessionCount: 1,
            lastReadAt: nil, averagePagesPerHour: nil, averageWordsPerMinute: nil,
            totalPagesRead: nil, totalWordsRead: nil, longestSessionSeconds: 60
        ))
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let record = try #require(
            try await actor.readingStats(forBookWithKey: target.canonicalKey))
        #expect(record.bookFingerprintKey == target.canonicalKey)
        #expect(record.totalReadingSeconds == 24_000)
        #expect(record.sessionCount == 23)
        #expect(record.longestSessionSeconds == 900)
    }

    @Test func zeroSessionRecordReadsAsFirstSessionInput() async throws {
        // A stats row with sessionCount == 0 is what the lifecycle helper
        // maps to isFirstSession — pin the projection.
        let container = try makeContainer()
        let fp = fingerprint("fresh")
        let context = ModelContext(container)
        context.insert(ReadingStats(
            bookFingerprint: fp, totalReadingSeconds: 0, sessionCount: 0,
            lastReadAt: nil, averagePagesPerHour: nil, averageWordsPerMinute: nil,
            totalPagesRead: nil, totalWordsRead: nil, longestSessionSeconds: 0
        ))
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let record = try #require(
            try await actor.readingStats(forBookWithKey: fp.canonicalKey))
        #expect(record.totalReadingSeconds == 0)
        #expect(record.sessionCount == 0)
    }
}
