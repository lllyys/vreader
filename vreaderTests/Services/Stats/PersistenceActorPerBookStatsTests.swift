// Purpose: Tests for PersistenceActor's feature #101 per-book stats reads —
// `readingStats(forBookWithKey:)` (WI-1, the reader-open totals fetch) and
// `firstSessionDate(forBookWithKey:)` (WI-2a, the Book details "since
// <date>" source). Split from PersistenceActorStatsReadTests.swift for the
// ~300-line file budget (Gate-4); the shared helpers live once here.

import Foundation
import SwiftData
import Testing
@testable import vreader

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

// MARK: - readingStats(forBookWithKey:) (feature #101 WI-1)

@Suite("PersistenceActor per-book stats fetch (feature #101)")
struct PersistenceActorPerBookStatsTests {

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

// MARK: - firstSessionDate(forBookWithKey:) (feature #101 WI-2a)

@Suite("PersistenceActor first-session date (feature #101 WI-2a)")
struct PersistenceActorFirstSessionDateTests {

    @Test func returnsNilWithNoSessions() async throws {
        let actor = PersistenceActor(modelContainer: try makeContainer())
        #expect(try await actor.firstSessionDate(forBookWithKey: "epub:none:0") == nil)
    }

    @Test func returnsEarliestStartForTheRequestedBookOnly() async throws {
        let container = try makeContainer()
        let target = fingerprint("target")
        let other = fingerprint("other")
        let context = ModelContext(container)
        let earliest = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)
        let otherEarlier = Date(timeIntervalSince1970: 500_000)
        for (fp, started) in [(target, later), (target, earliest), (other, otherEarlier)] {
            context.insert(ReadingSession(
                bookFingerprint: fp, startedAt: started,
                endedAt: started.addingTimeInterval(600),
                durationSeconds: 600, deviceId: "test"
            ))
        }
        try context.save()

        let actor = PersistenceActor(modelContainer: container)
        let first = try await actor.firstSessionDate(forBookWithKey: target.canonicalKey)
        #expect(first == earliest)
    }
}
