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
}
