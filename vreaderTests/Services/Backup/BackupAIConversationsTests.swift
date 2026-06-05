// Purpose: Tests for the `ai-conversations.json` backup section (feature #89) —
// DTO round-trip, collector emit, restore round-trip + book re-association,
// byte-exact blob transport, book-missing/re-key edge cases, idempotency,
// schema-version tolerance, never-clobber, and protocol default impls.
//
// Containers build on Schema(SchemaV9.models) because ChatSession only exists
// from V9 (mirrors PersistenceActor+ChatSessionsTests).

import Foundation
import SwiftData
import Testing
@testable import vreader

@Suite("Backup ai-conversations section")
struct BackupAIConversationsTests {

    // MARK: - V9 container helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(SchemaV9.models)
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
            .appendingPathComponent("backup-ai-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func collector(_ container: ModelContainer) -> BackupDataCollector {
        BackupDataCollector(
            persistence: PersistenceActor(modelContainer: container),
            defaults: UserDefaults(suiteName: "ai-test-\(UUID().uuidString)")!,
            perBookSettingsBaseURL: tempDir()
        )
    }

    private func restorer(_ container: ModelContainer) -> BackupDataRestorer {
        BackupDataRestorer(
            persistence: PersistenceActor(modelContainer: container),
            defaults: UserDefaults(suiteName: "ai-test-\(UUID().uuidString)")!,
            perBookSettingsBaseURL: tempDir()
        )
    }

    /// Inserts a Book row directly into the container, returns its fingerprint key.
    @discardableResult
    private func insertBook(_ container: ModelContainer, _ fp: DocumentFingerprint) async throws -> String {
        let persistence = PersistenceActor(modelContainer: container)
        let record = BookRecord(
            fingerprintKey: fp.canonicalKey,
            title: "Test Book",
            author: nil,
            coverImagePath: nil,
            fingerprint: fp,
            provenance: ImportProvenance(
                source: .filesApp,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000),
                originalURLBookmarkData: nil
            ),
            detectedEncoding: nil,
            addedAt: Date()
        )
        return try await persistence.insertBook(record).fingerprintKey
    }

    /// Seeds a ChatSession row through the actor (requires an existing Book).
    @discardableResult
    private func createSession(
        _ container: ModelContainer, bookKey: String, title: String = "Chat",
        messages: [ChatMessage]
    ) async throws -> UUID {
        let persistence = PersistenceActor(modelContainer: container)
        let record = try await persistence.createChatSession(
            bookFingerprintKey: bookKey, title: title, messages: messages
        )
        return record.sessionId
    }

    /// Seeds a ChatSession with a raw `messagesData` blob (book may be absent).
    /// Used for non-UTF8 byte-exactness and never-clobber edges.
    private func seedRawSession(
        _ container: ModelContainer, sessionId: UUID = UUID(), bookKey: String,
        title: String = "Raw", rawBlob: Data?, snippet: String = "snip",
        count: Int = 1, createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) throws {
        let context = ModelContext(container)
        let s = ChatSession(sessionId: sessionId, bookFingerprintKey: bookKey,
                            title: title, messages: [], createdAt: createdAt)
        s.messagesData = rawBlob
        s.lastMessageSnippet = snippet
        s.messageCount = count
        context.insert(s)
        try context.save()
    }

    private func userMessage(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    private func assistantWithCitation(_ content: String) -> ChatMessage {
        ChatMessage(
            role: .assistant, content: content,
            citations: [ChatCitation(sourceKind: .scope, label: "Chapter 1", sequence: 1)]
        )
    }

    private func decode(_ data: Data) throws -> BackupAIConversationsEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BackupAIConversationsEnvelope.self, from: data)
    }

    private func encode(_ env: BackupAIConversationsEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(env)
    }

    /// Reads ChatSession rows directly from the container (avoids actor mapping).
    private func fetchRows(_ container: ModelContainer) throws -> [ChatSession] {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<ChatSession>())
    }

    // MARK: - DTO Codable round-trip

    @Test func dtoCodableRoundTrips() throws {
        let blob = ChatSessionPayloadMapper.encode([userMessage("hi")])
        let session = BackupChatSession(
            sessionId: UUID(),
            bookFingerprintKey: fingerprint("dto").canonicalKey,
            title: "Title", messagesPayloadData: blob,
            lastMessageSnippet: "hi", messageCount: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let env = BackupAIConversationsEnvelope(schemaVersion: 3, sessions: [session])
        let decoded = try decode(try encode(env))
        #expect(decoded == env)
        #expect(decoded.sessions.first?.messagesPayloadData == blob)
    }

    // MARK: - Collector

    @Test func collectEmitsSchemaVersion3() async throws {
        let container = try makeContainer()
        let data = try await collector(container).collectAIConversations()
        let env = try decode(data)
        #expect(env.schemaVersion == kBackupCurrentSchemaVersion)
        #expect(env.schemaVersion == 3)
    }

    @Test func collectEmptyStoreEmitsEmptyEnvelope() async throws {
        let container = try makeContainer()
        let env = try decode(try await collector(container).collectAIConversations())
        #expect(env.sessions.isEmpty)
        #expect(env.schemaVersion == 3)
    }

    @Test func collectEmitsOneSessionPerSeededWithDecodableMessages() async throws {
        let container = try makeContainer()
        let fp = fingerprint("collect")
        let key = try await insertBook(container, fp)
        _ = try await createSession(container, bookKey: key, title: "T",
            messages: [userMessage("hello"), assistantWithCitation("answer")])

        let env = try decode(try await collector(container).collectAIConversations())
        #expect(env.sessions.count == 1)
        let s = try #require(env.sessions.first)
        #expect(s.bookFingerprintKey == key)
        #expect(s.messageCount == 2)
        let messages = ChatSessionPayloadMapper.decode(s.messagesPayloadData)
        #expect(messages.count == 2)
        #expect(messages.last?.citations.first?.sequence == 1)
        #expect(messages.last?.citations.first?.sourceKind == .scope)
    }

    // MARK: - Restore round-trip

    @Test func restoreRoundTripReAssociatesToBook() async throws {
        let source = try makeContainer()
        let fp = fingerprint("rtbook")
        let key = try await insertBook(source, fp)
        let sid = try await createSession(source, bookKey: key, title: "Roundtrip",
            messages: [userMessage("q"), assistantWithCitation("a")])
        let data = try await collector(source).collectAIConversations()

        let fresh = try makeContainer()
        _ = try await insertBook(fresh, fp)  // book present on restore target
        try await restorer(fresh).restoreAIConversations(from: data)

        let rows = try fetchRows(fresh)
        #expect(rows.count == 1)
        let r = try #require(rows.first)
        #expect(r.sessionId == sid)
        #expect(r.bookFingerprintKey == key)
        #expect(r.title == "Roundtrip")
        #expect(r.book?.fingerprintKey == key)
        // appears in book.chatSessions
        let book = try #require(r.book)
        #expect(book.chatSessions.contains { $0.sessionId == sid })
        let messages = ChatSessionPayloadMapper.decode(r.messagesData)
        #expect(messages.count == 2)
    }

    @Test func restoreMessagesSurviveExactly() async throws {
        let source = try makeContainer()
        let fp = fingerprint("msgexact")
        let key = try await insertBook(source, fp)
        let original = [userMessage("ask"), assistantWithCitation("cited reply")]
        _ = try await createSession(source, bookKey: key, messages: original)
        let data = try await collector(source).collectAIConversations()

        let fresh = try makeContainer()
        try await restorer(fresh).restoreAIConversations(from: data)
        let r = try #require(try fetchRows(fresh).first)
        let restored = ChatSessionPayloadMapper.decode(r.messagesData)
        #expect(restored == original)
    }

    // MARK: - Byte-exactness (Gate-2 Medium fix)

    @Test func nonUTF8BlobSurvivesByteExactly() async throws {
        let source = try makeContainer()
        let fp = fingerprint("nonutf8")
        let key = try await insertBook(source, fp)
        // Deliberately non-UTF8 / non-payload bytes.
        let raw = Data([0xFF, 0xFE, 0x00, 0x01, 0x80, 0xC0])
        try seedRawSession(source, bookKey: key, rawBlob: raw)
        let data = try await collector(source).collectAIConversations()

        // Confirm the DTO carried the exact bytes.
        let env = try decode(data)
        #expect(env.sessions.first?.messagesPayloadData == raw)

        let fresh = try makeContainer()
        try await restorer(fresh).restoreAIConversations(from: data)
        let r = try #require(try fetchRows(fresh).first)
        #expect(r.messagesData == raw)  // byte-exact, not nil'd by a String transcode
    }

    // MARK: - Book-missing edge

    @Test func sessionWithNoLocalBookStillRestoresWithNilBook() async throws {
        let source = try makeContainer()
        let fp = fingerprint("orphan")
        let key = try await insertBook(source, fp)
        let sid = try await createSession(source, bookKey: key,
            messages: [userMessage("hi")])
        let data = try await collector(source).collectAIConversations()

        let fresh = try makeContainer()  // NO Book rows
        try await restorer(fresh).restoreAIConversations(from: data)
        let rows = try fetchRows(fresh)
        #expect(rows.count == 1)
        let r = try #require(rows.first)
        #expect(r.sessionId == sid)
        #expect(r.bookFingerprintKey == key)
        #expect(r.book == nil)  // no throw, no association
    }

    // MARK: - Restore-over-existing re-keys to backup's book

    @Test func restoreOverExistingReKeysToBackupBookWhenPresent() async throws {
        let fpA = fingerprint("bookA")
        let fpB = fingerprint("bookB")
        let sid = UUID()
        let fresh = try makeContainer()
        // local row keyed to A, associated with A.
        let keyA = try await insertBook(fresh, fpA)
        _ = try await createSession(fresh, bookKey: keyA, messages: [userMessage("local")])
        // re-point the seeded session id (createSession generated its own id) —
        // instead seed via raw with sid keyed to A, associated to A explicitly.
        let context = ModelContext(fresh)
        let rowsA = try context.fetch(FetchDescriptor<ChatSession>())
        let existing = try #require(rowsA.first)
        existing.sessionId = sid
        try context.save()

        // book B present locally.
        let keyB = try await insertBook(fresh, fpB)
        let backup = BackupAIConversationsEnvelope(schemaVersion: 3, sessions: [
            BackupChatSession(
                sessionId: sid, bookFingerprintKey: keyB, title: "FromBackup",
                messagesPayloadData: ChatSessionPayloadMapper.encode([userMessage("backup")]),
                lastMessageSnippet: "backup", messageCount: 1,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
            )
        ])
        try await restorer(fresh).restoreAIConversations(from: try encode(backup))

        let r = try #require(try fetchRows(fresh).first { $0.sessionId == sid })
        #expect(r.bookFingerprintKey == keyB)  // re-keyed
        #expect(r.book?.fingerprintKey == keyB) // re-linked to B, not A
        // The OLD book A must RELEASE the moved session — verifies SwiftData's
        // inverse cleanup actually fires on the `row.book` reassignment, so no
        // stale cascade edge survives on A (Gate-4 Low).
        let bookA = try #require(try ModelContext(fresh).fetch(FetchDescriptor<Book>())
            .first { $0.fingerprintKey == keyA })
        #expect(!bookA.chatSessions.contains { $0.sessionId == sid })
    }

    @Test func restoreOverExistingReKeysAndClearsBookWhenBackupBookAbsent() async throws {
        let fpA = fingerprint("bookA2")
        let fpB = fingerprint("bookB2")
        let sid = UUID()
        let fresh = try makeContainer()
        let keyA = try await insertBook(fresh, fpA)
        _ = try await createSession(fresh, bookKey: keyA, messages: [userMessage("local")])
        let context = ModelContext(fresh)
        let existing = try #require(try context.fetch(FetchDescriptor<ChatSession>()).first)
        existing.sessionId = sid
        try context.save()

        // book B is ABSENT locally.
        let keyB = fpB.canonicalKey
        let backup = BackupAIConversationsEnvelope(schemaVersion: 3, sessions: [
            BackupChatSession(
                sessionId: sid, bookFingerprintKey: keyB, title: "FromBackup",
                messagesPayloadData: ChatSessionPayloadMapper.encode([userMessage("backup")]),
                lastMessageSnippet: "backup", messageCount: 1,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_500)
            )
        ])
        try await restorer(fresh).restoreAIConversations(from: try encode(backup))

        let r = try #require(try fetchRows(fresh).first { $0.sessionId == sid })
        #expect(r.bookFingerprintKey == keyB)  // re-keyed to B
        #expect(r.book == nil)  // stale A relation cleared
        // The OLD book A must RELEASE the session even though B is absent — the
        // `row.book = nil` clear must drop the inverse edge on A (Gate-4 Low).
        let bookA = try #require(try ModelContext(fresh).fetch(FetchDescriptor<Book>())
            .first { $0.fingerprintKey == keyA })
        #expect(!bookA.chatSessions.contains { $0.sessionId == sid })
    }

    // MARK: - Version tolerance

    /// A v2-TAGGED AI envelope (older archive that already carried the section
    /// under the v2 numbering) decodes + restores fine — `kBackupAcceptedSchemaVersions`
    /// includes 2. NOTE: the real forward-compat path where a v1/v2 archive simply
    /// LACKS `ai-conversations.json` is a provider-LOOP concern (the loop `try?`-skips
    /// an absent entry, generic across all sections) — exercised in
    /// `WebDAVProviderTests` orchestration, not at this restorer level (the restorer
    /// method is only invoked when the section is present). Renamed from the
    /// misleading `…WithoutSection…` (Gate-4 Low).
    @Test func v2TaggedAIEnvelopeIsAccepted() async throws {
        let v2 = BackupAIConversationsEnvelope(schemaVersion: 2, sessions: [])
        let fresh = try makeContainer()
        try await restorer(fresh).restoreAIConversations(from: try encode(v2))
        #expect(try fetchRows(fresh).isEmpty)
    }

    @Test func v3Accepted_v4Rejected() async throws {
        let fresh = try makeContainer()
        let v3 = BackupAIConversationsEnvelope(schemaVersion: 3, sessions: [])
        try await restorer(fresh).restoreAIConversations(from: try encode(v3))  // no throw

        let v4 = BackupAIConversationsEnvelope(schemaVersion: 4, sessions: [])
        await #expect(throws: BackupRestoreError.self) {
            try await self.restorer(fresh).restoreAIConversations(from: try self.encode(v4))
        }
    }

    // MARK: - Idempotency

    @Test func restoringTwiceDoesNotDuplicate() async throws {
        let source = try makeContainer()
        let fp = fingerprint("idem")
        let key = try await insertBook(source, fp)
        let sid = try await createSession(source, bookKey: key,
            messages: [userMessage("once")])
        let data = try await collector(source).collectAIConversations()

        let fresh = try makeContainer()
        _ = try await insertBook(fresh, fp)
        let r = restorer(fresh)
        try await r.restoreAIConversations(from: data)
        try await r.restoreAIConversations(from: data)

        let rows = try fetchRows(fresh)
        #expect(rows.count == 1)  // unique sessionId upsert
        let book = try #require(rows.first?.book)
        let dupes = book.chatSessions.filter { $0.sessionId == sid }
        #expect(dupes.count == 1)  // no duplicate book.chatSessions
    }

    // MARK: - Never-clobber future-version blob

    @Test func futureVersionBlobNotClobbered() async throws {
        let fp = fingerprint("future")
        let sid = UUID()
        let fresh = try makeContainer()
        // Seed an existing row with a synthetic future-version blob.
        let futureBlob = Data(#"{"version":99,"messages":[]}"#.utf8)
        try seedRawSession(fresh, sessionId: sid, bookKey: fp.canonicalKey,
            title: "OldTitle", rawBlob: futureBlob, snippet: "future", count: 5)
        #expect(ChatSessionPayloadMapper.isReadable(futureBlob) == false)

        // Backup tries to overwrite with a readable blob.
        let backup = BackupAIConversationsEnvelope(schemaVersion: 3, sessions: [
            BackupChatSession(
                sessionId: sid, bookFingerprintKey: fp.canonicalKey, title: "NewTitle",
                messagesPayloadData: ChatSessionPayloadMapper.encode([userMessage("new")]),
                lastMessageSnippet: "new", messageCount: 1,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                updatedAt: Date(timeIntervalSince1970: 1_700_000_999)
            )
        ])
        try await restorer(fresh).restoreAIConversations(from: try encode(backup))

        let r = try #require(try fetchRows(fresh).first { $0.sessionId == sid })
        #expect(r.messagesData == futureBlob)  // blob preserved
        #expect(r.title == "NewTitle")  // non-blob metadata may still update
    }

    // MARK: - Schema bump

    @Test func schemaConstantsBumpedTo3() {
        #expect(kBackupCurrentSchemaVersion == 3)
        #expect(kBackupAcceptedSchemaVersions == [1, 2, 3])
    }

    // MARK: - Corrupt JSON

    @Test func corruptJSONThrows() async throws {
        let garbage = Data("{not valid json".utf8)
        let fresh = try makeContainer()
        await #expect(throws: (any Error).self) {
            try await self.restorer(fresh).restoreAIConversations(from: garbage)
        }
    }

    // MARK: - Protocol default impls

    final class MinimalCollector: BackupDataCollecting, @unchecked Sendable {
        func collectAnnotations() async throws -> Data { Data("{}".utf8) }
        func collectPositions() async throws -> Data { Data("{}".utf8) }
        func collectSettings() async throws -> Data { Data("{}".utf8) }
        func collectCollections() async throws -> Data { Data("{}".utf8) }
        func collectBookSources() async throws -> Data { Data("{}".utf8) }
        func collectPerBookSettings() async throws -> Data { Data("{}".utf8) }
        func collectReplacementRules() async throws -> Data { Data("{}".utf8) }
        func getBookCount() async -> Int { 0 }
        // collectAIConversations uses the default impl.
    }

    @Test func collectorDefaultImplProducesValidEmptyAIConversations() async throws {
        let data = try await MinimalCollector().collectAIConversations()
        let env = try decode(data)
        #expect(env.schemaVersion == kBackupCurrentSchemaVersion)
        #expect(env.sessions.isEmpty)
    }

    final class MinimalRestorer: BackupDataRestoring, @unchecked Sendable {
        func restoreAnnotations(from data: Data) async throws {}
        func restorePositions(from data: Data) async throws {}
        func restoreSettings(from data: Data) async throws {}
        func restoreCollections(from data: Data) async throws {}
        func restoreBookSources(from data: Data) async throws {}
        func restorePerBookSettings(from data: Data) async throws {}
        func restoreReplacementRules(from data: Data) async throws {}
        // restoreAIConversations uses the default no-op impl.
    }

    @Test func restorerDefaultImplIsANoOp() async throws {
        try await MinimalRestorer().restoreAIConversations(from: Data("garbage".utf8))
    }
}
