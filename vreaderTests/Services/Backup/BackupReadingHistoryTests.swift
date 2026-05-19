// Purpose: Tests for the `reading-history.json` backup section (feature #58
// WI-5) — collector, restorer round-trip, idempotency, schema-version
// decoupling, and missing/corrupt-section handling.

import Foundation
import SwiftData
import Testing
@testable import vreader

@Suite("Backup reading-history section")
struct BackupReadingHistoryTests {

    // MARK: - Fixtures

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
            contentSHA256: String(hex.prefix(64)), fileByteCount: 4096, format: .epub
        )
    }

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-rh-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func collector(_ container: ModelContainer) -> BackupDataCollector {
        BackupDataCollector(
            persistence: PersistenceActor(modelContainer: container),
            defaults: UserDefaults(suiteName: "rh-test-\(UUID().uuidString)")!,
            perBookSettingsBaseURL: tempDir()
        )
    }

    private func restorer(_ container: ModelContainer) -> BackupDataRestorer {
        BackupDataRestorer(
            persistence: PersistenceActor(modelContainer: container),
            defaults: UserDefaults(suiteName: "rh-test-\(UUID().uuidString)")!,
            perBookSettingsBaseURL: tempDir()
        )
    }

    private func seedSession(
        _ container: ModelContainer, book: DocumentFingerprint,
        sessionId: UUID = UUID(), startedAt: Date, endedAt: Date? = nil,
        duration: Int = 600, pages: Int? = 10, words: Int? = 2000,
        deviceId: String = "dev-1", isRecovered: Bool = false,
        startLocator: Locator? = nil, endLocator: Locator? = nil
    ) throws {
        let context = ModelContext(container)
        let s = ReadingSession(
            sessionId: sessionId, bookFingerprint: book, startedAt: startedAt,
            endedAt: endedAt, durationSeconds: duration, pagesRead: pages,
            wordsRead: words, startLocator: startLocator, endLocator: endLocator,
            deviceId: deviceId, isRecovered: isRecovered
        )
        context.insert(s)
        try context.save()
    }

    private func seedStats(
        _ container: ModelContainer, book: DocumentFingerprint,
        totalSeconds: Int = 3600, sessionCount: Int = 3, lastReadAt: Date?,
        avgPagesPerHour: Double? = nil, avgWordsPerMinute: Double? = nil,
        totalPages: Int? = nil, totalWords: Int? = nil, longestSession: Int = 1800
    ) throws {
        let context = ModelContext(container)
        let stats = ReadingStats(
            bookFingerprint: book, totalReadingSeconds: totalSeconds,
            sessionCount: sessionCount, lastReadAt: lastReadAt,
            averagePagesPerHour: avgPagesPerHour, averageWordsPerMinute: avgWordsPerMinute,
            totalPagesRead: totalPages, totalWordsRead: totalWords,
            longestSessionSeconds: longestSession
        )
        context.insert(stats)
        try context.save()
    }

    private func decode(_ data: Data) throws -> BackupReadingHistoryEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupReadingHistoryEnvelope.self, from: data)
    }

    // MARK: - Collector

    @Test func collectEmitsSchemaVersion2() async throws {
        let container = try makeContainer()
        let data = try await collector(container).collectReadingHistory()
        let envelope = try decode(data)
        #expect(envelope.schemaVersion == 2)
        #expect(envelope.schemaVersion == kBackupCurrentSchemaVersion)
    }

    @Test func collectEmptyStoreEmitsEmptyEnvelope() async throws {
        let container = try makeContainer()
        let envelope = try decode(try await collector(container).collectReadingHistory())
        #expect(envelope.sessions.isEmpty)
        #expect(envelope.stats.isEmpty)
    }

    @Test func collectRoundTripsEveryReadingSessionField() async throws {
        let container = try makeContainer()
        let fp = fingerprint("alpha")
        let id = UUID()
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        let ended = Date(timeIntervalSince1970: 1_700_000_600)
        try seedSession(container, book: fp, sessionId: id, startedAt: started,
                        endedAt: ended, duration: 600, pages: 15, words: 3300,
                        deviceId: "iphone-17-pro", isRecovered: true)

        let envelope = try decode(try await collector(container).collectReadingHistory())
        #expect(envelope.sessions.count == 1)
        let s = try #require(envelope.sessions.first)
        #expect(s.sessionId == id)
        #expect(s.bookFingerprintKey == fp.canonicalKey)
        #expect(s.startedAt == started)
        #expect(s.endedAt == ended)
        #expect(s.durationSeconds == 600)
        #expect(s.pagesRead == 15)
        #expect(s.wordsRead == 3300)
        #expect(s.deviceId == "iphone-17-pro")
        #expect(s.isRecovered == true)
    }

    // MARK: - Round-trip

    @Test func restoreRoundTripReproducesSessionsExactly() async throws {
        // Seed source, collect, then restore into a FRESH container.
        let source = try makeContainer()
        let fp = fingerprint("bravo")
        let id = UUID()
        let started = Date(timeIntervalSince1970: 1_600_000_000)
        try seedSession(source, book: fp, sessionId: id, startedAt: started,
                        endedAt: nil, duration: 900, pages: 20, words: 4000,
                        deviceId: "dev-x", isRecovered: false)
        let data = try await collector(source).collectReadingHistory()

        let fresh = try makeContainer()
        try await restorer(fresh).restoreReadingHistory(from: data)

        let restored = try await PersistenceActor(modelContainer: fresh).fetchAllReadingSessions()
        #expect(restored.count == 1)
        let r = try #require(restored.first)
        #expect(r.sessionId == id)
        #expect(r.bookFingerprintKey == fp.canonicalKey)
        #expect(r.startedAt == started)
        #expect(r.durationSeconds == 900)
        #expect(r.pagesRead == 20)
        #expect(r.wordsRead == 4000)
        #expect(r.deviceId == "dev-x")
    }

    @Test func restoredReadingStatsLastReadAtIsVerbatimNotRecomputed() async throws {
        // The crux: restore must NOT call recomputeStats (which stamps Date()).
        let source = try makeContainer()
        let fp = fingerprint("charlie")
        let fixedLastRead = Date(timeIntervalSince1970: 1_500_000_000)  // a fixed PAST date
        try seedStats(source, book: fp, totalSeconds: 7200, sessionCount: 9,
                      lastReadAt: fixedLastRead)
        let data = try await collector(source).collectReadingHistory()

        let fresh = try makeContainer()
        try await restorer(fresh).restoreReadingHistory(from: data)

        let restored = try await PersistenceActor(modelContainer: fresh).fetchAllReadingStats()
        #expect(restored.count == 1)
        let r = try #require(restored.first)
        // lastReadAt must EQUAL the seeded backup value — not restore-time.
        #expect(r.lastReadAt == fixedLastRead)
        #expect(r.totalReadingSeconds == 7200)
        #expect(r.sessionCount == 9)
    }

    @Test func restoreRoundTripPreservesStartAndEndLocators() async throws {
        // F2: BackupReadingSession carries the locators as JSON strings.
        let source = try makeContainer()
        let fp = fingerprint("locbook")
        let startLoc = try #require(Locator.validated(bookFingerprint: fp, page: 3))
        let endLoc = try #require(Locator.validated(bookFingerprint: fp, page: 17))
        let id = UUID()
        try seedSession(source, book: fp, sessionId: id,
                        startedAt: Date(timeIntervalSince1970: 1_650_000_000),
                        startLocator: startLoc, endLocator: endLoc)
        let data = try await collector(source).collectReadingHistory()

        let fresh = try makeContainer()
        try await restorer(fresh).restoreReadingHistory(from: data)
        let restored = try await PersistenceActor(modelContainer: fresh).fetchAllReadingSessions()
        let r = try #require(restored.first)
        #expect(r.startLocator?.page == 3)
        #expect(r.endLocator?.page == 17)
        #expect(r.startLocator?.bookFingerprint.canonicalKey == fp.canonicalKey)
    }

    @Test func malformedLocatorJSONDegradesToNilSessionStillRestores() async throws {
        // A session whose locator JSON is garbage must still restore — only the
        // locator is dropped (degrades to nil), not the whole session.
        let fp = fingerprint("malformedloc")
        let id = UUID()
        let envelope = BackupReadingHistoryEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion,
            sessions: [BackupReadingSession(
                sessionId: id, bookFingerprintKey: fp.canonicalKey,
                startedAt: Date(timeIntervalSince1970: 1_640_000_000), endedAt: nil,
                durationSeconds: 450, pagesRead: 8, wordsRead: 1500,
                startLocatorJSON: "{not valid locator json",
                endLocatorJSON: "also garbage",
                deviceId: "dev-m", isRecovered: false
            )],
            stats: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)

        let fresh = try makeContainer()
        try await restorer(fresh).restoreReadingHistory(from: data)
        let restored = try await PersistenceActor(modelContainer: fresh).fetchAllReadingSessions()
        #expect(restored.count == 1)
        let r = try #require(restored.first)
        #expect(r.sessionId == id)
        #expect(r.durationSeconds == 450)
        // Both locators degraded to nil — the session itself survived.
        #expect(r.startLocator == nil)
        #expect(r.endLocator == nil)
    }

    @Test func restoreReproducesEveryReadingStatsScalarVerbatim() async throws {
        // F9: every ReadingStats scalar restores verbatim (not just lastReadAt).
        let source = try makeContainer()
        let fp = fingerprint("fullstats")
        let lastRead = Date(timeIntervalSince1970: 1_450_000_000)
        try seedStats(source, book: fp, totalSeconds: 12_345, sessionCount: 42,
                      lastReadAt: lastRead, avgPagesPerHour: 33.5, avgWordsPerMinute: 215.0,
                      totalPages: 410, totalWords: 88_000, longestSession: 4321)
        let data = try await collector(source).collectReadingHistory()

        let fresh = try makeContainer()
        let r = restorer(fresh)
        try await r.restoreReadingHistory(from: data)

        func assertScalars(_ stats: ReadingStatsRecord) {
            #expect(stats.totalReadingSeconds == 12_345)
            #expect(stats.sessionCount == 42)
            #expect(stats.lastReadAt == lastRead)
            #expect(stats.averagePagesPerHour == 33.5)
            #expect(stats.averageWordsPerMinute == 215.0)
            #expect(stats.totalPagesRead == 410)
            #expect(stats.totalWordsRead == 88_000)
            #expect(stats.longestSessionSeconds == 4321)
        }
        let first = try await PersistenceActor(modelContainer: fresh).fetchAllReadingStats()
        assertScalars(try #require(first.first))

        // And again after a second restore — still verbatim, no recompute drift.
        try await r.restoreReadingHistory(from: data)
        let second = try await PersistenceActor(modelContainer: fresh).fetchAllReadingStats()
        assertScalars(try #require(second.first))
    }

    // MARK: - Idempotency

    @Test func restoringTwiceDoesNotDuplicate() async throws {
        let source = try makeContainer()
        let fp = fingerprint("delta")
        let id = UUID()
        try seedSession(source, book: fp, sessionId: id,
                        startedAt: Date(timeIntervalSince1970: 1_400_000_000))
        try seedStats(source, book: fp, lastReadAt: Date(timeIntervalSince1970: 1_400_000_000))
        let data = try await collector(source).collectReadingHistory()

        let fresh = try makeContainer()
        let r = restorer(fresh)
        try await r.restoreReadingHistory(from: data)
        try await r.restoreReadingHistory(from: data)  // second restore

        let actor = PersistenceActor(modelContainer: fresh)
        let sessions = try await actor.fetchAllReadingSessions()
        let stats = try await actor.fetchAllReadingStats()
        #expect(sessions.count == 1)  // no duplicate from the unique sessionId
        #expect(stats.count == 1)
    }

    @Test func restoringTwicePreservesLastReadAt() async throws {
        let source = try makeContainer()
        let fp = fingerprint("echo")
        let fixedLastRead = Date(timeIntervalSince1970: 1_300_000_000)
        try seedStats(source, book: fp, lastReadAt: fixedLastRead)
        let data = try await collector(source).collectReadingHistory()

        let fresh = try makeContainer()
        let r = restorer(fresh)
        try await r.restoreReadingHistory(from: data)
        try await r.restoreReadingHistory(from: data)

        let stats = try await PersistenceActor(modelContainer: fresh).fetchAllReadingStats()
        #expect(stats.first?.lastReadAt == fixedLastRead)
    }

    // MARK: - Schema-version decoupling

    @Test func schemaV1ReadingHistorySectionStillRestores() async throws {
        // A v1-tagged reading-history envelope must restore after the v2 bump
        // (kBackupAcceptedSchemaVersions decoupling).
        let v1Envelope = BackupReadingHistoryEnvelope(
            schemaVersion: 1,
            sessions: [BackupReadingSession(
                sessionId: UUID(), bookFingerprintKey: fingerprint("v1book").canonicalKey,
                startedAt: Date(timeIntervalSince1970: 1_200_000_000), endedAt: nil,
                durationSeconds: 300, pagesRead: nil, wordsRead: nil,
                startLocatorJSON: nil, endLocatorJSON: nil,
                deviceId: "v1-dev", isRecovered: false
            )],
            stats: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(v1Envelope)

        let fresh = try makeContainer()
        // Must NOT throw — v1 is in kBackupAcceptedSchemaVersions.
        try await restorer(fresh).restoreReadingHistory(from: data)
        let sessions = try await PersistenceActor(modelContainer: fresh).fetchAllReadingSessions()
        #expect(sessions.count == 1)
    }

    @Test func syntheticV3SectionThrowsUnsupportedSchemaVersion() async throws {
        let v3Envelope = BackupReadingHistoryEnvelope(
            schemaVersion: 3, sessions: [], stats: []
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(v3Envelope)

        let fresh = try makeContainer()
        await #expect(throws: BackupRestoreError.self) {
            try await self.restorer(fresh).restoreReadingHistory(from: data)
        }
    }

    @Test func corruptJSONThrows() async throws {
        let garbage = Data("{not valid json".utf8)
        let fresh = try makeContainer()
        await #expect(throws: (any Error).self) {
            try await self.restorer(fresh).restoreReadingHistory(from: garbage)
        }
    }

    // MARK: - Protocol default impls

    /// A minimal collector that implements NONE of the optional sections —
    /// proves the protocol default-impl keeps a pre-#58 collector compiling
    /// and producing a valid empty `reading-history.json`.
    final class MinimalCollector: BackupDataCollecting, @unchecked Sendable {
        func collectAnnotations() async throws -> Data { Data("{}".utf8) }
        func collectPositions() async throws -> Data { Data("{}".utf8) }
        func collectSettings() async throws -> Data { Data("{}".utf8) }
        func collectCollections() async throws -> Data { Data("{}".utf8) }
        func collectBookSources() async throws -> Data { Data("{}".utf8) }
        func collectPerBookSettings() async throws -> Data { Data("{}".utf8) }
        func collectReplacementRules() async throws -> Data { Data("{}".utf8) }
        func getBookCount() async -> Int { 0 }
        // collectLibraryManifest + collectReadingHistory use the default impls.
    }

    @Test func collectorDefaultImplProducesValidEmptyReadingHistory() async throws {
        let data = try await MinimalCollector().collectReadingHistory()
        let envelope = try decode(data)
        #expect(envelope.schemaVersion == kBackupCurrentSchemaVersion)
        #expect(envelope.sessions.isEmpty)
        #expect(envelope.stats.isEmpty)
    }

    /// A minimal restorer that implements NONE of the optional sections —
    /// proves the `restoreReadingHistory` default no-op keeps a pre-#58
    /// restorer compiling.
    final class MinimalRestorer: BackupDataRestoring, @unchecked Sendable {
        func restoreAnnotations(from data: Data) async throws {}
        func restorePositions(from data: Data) async throws {}
        func restoreSettings(from data: Data) async throws {}
        func restoreCollections(from data: Data) async throws {}
        func restoreBookSources(from data: Data) async throws {}
        func restorePerBookSettings(from data: Data) async throws {}
        func restoreReplacementRules(from data: Data) async throws {}
        // restoreReadingHistory uses the default no-op impl.
    }

    @Test func restorerDefaultImplIsANoOp() async throws {
        // The default restoreReadingHistory must not throw even on garbage —
        // it is a no-op.
        try await MinimalRestorer().restoreReadingHistory(from: Data("garbage".utf8))
    }

    // MARK: - Book-independence

    @Test func sessionForBookWithNoLocalBookRowStillRestores() async throws {
        // Reading history is book-independent — a session whose book key has
        // no matching Book row still lands (the post-restore-without-blob case).
        let source = try makeContainer()
        let fp = fingerprint("orphan")
        try seedSession(source, book: fp,
                        startedAt: Date(timeIntervalSince1970: 1_100_000_000))
        let data = try await collector(source).collectReadingHistory()

        let fresh = try makeContainer()  // no Book rows at all
        try await restorer(fresh).restoreReadingHistory(from: data)
        let sessions = try await PersistenceActor(modelContainer: fresh).fetchAllReadingSessions()
        #expect(sessions.count == 1)
        #expect(sessions.first?.bookFingerprintKey == fp.canonicalKey)
    }
}
