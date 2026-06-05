// Purpose: Tests for PersistenceActor+ChatSessions (Feature #88 WI-2) — CRUD,
// summary projection, sort order, book-delete cascade, and the WI-1 carry-forward
// contract (encode-nil skip, future-version-blob preservation). Mirrors
// PersistenceHighlightTests, but builds its own in-memory ModelContainer on
// SchemaV9 because ChatSession only exists from V9.

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("PersistenceActor — ChatSessions")
struct PersistenceActorChatSessionsTests {

    // MARK: - V9 container helpers

    private func makePersistence() throws -> PersistenceActor {
        let schema = Schema(SchemaV9.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return PersistenceActor(modelContainer: container)
    }

    private func makeFingerprint(
        sha: String = String(repeating: "a", count: 64)
    ) -> DocumentFingerprint {
        DocumentFingerprint(contentSHA256: sha, fileByteCount: 1024, format: .epub)
    }

    /// Inserts a book and returns its fingerprint key.
    @discardableResult
    private func insertBook(
        _ persistence: PersistenceActor,
        sha: String = String(repeating: "a", count: 64)
    ) async throws -> String {
        let fp = makeFingerprint(sha: sha)
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

    private func userMessage(_ content: String) -> ChatMessage {
        ChatMessage(role: .user, content: content)
    }

    private func assistantWithCitation(_ content: String) -> ChatMessage {
        ChatMessage(
            role: .assistant,
            content: content,
            citations: [
                ChatCitation(sourceKind: .scope, label: "Chapter 1", sequence: 1)
            ]
        )
    }

    // MARK: - Create + fetch

    @Test func createReturnsRecordWithFields() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)

        let record = try await persistence.createChatSession(
            bookFingerprintKey: key,
            title: "First chat",
            messages: [userMessage("hello"), assistantWithCitation("hi there")]
        )

        #expect(record.bookFingerprintKey == key)
        #expect(record.title == "First chat")
        #expect(record.messages.count == 2)
    }

    @Test func createForMissingBookThrows() async throws {
        let persistence = try makePersistence()
        let missingKey = makeFingerprint(sha: String(repeating: "b", count: 64)).canonicalKey

        await #expect(throws: (any Error).self) {
            _ = try await persistence.createChatSession(
                bookFingerprintKey: missingKey, title: "x", messages: []
            )
        }
    }

    @Test func fetchSummariesHasDenormalizedFields() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)

        let created = try await persistence.createChatSession(
            bookFingerprintKey: key,
            title: "Summary chat",
            messages: [userMessage("q"), assistantWithCitation("the last answer")]
        )

        let summaries = try await persistence.fetchChatSessionSummaries(forBookWithKey: key)
        #expect(summaries.count == 1)
        let summary = try #require(summaries.first)
        #expect(summary.id == created.sessionId)
        #expect(summary.title == "Summary chat")
        #expect(summary.snippet == "the last answer")
        #expect(summary.messageCount == 2)
    }

    @Test func fetchSummariesForMissingBookReturnsEmpty() async throws {
        let persistence = try makePersistence()
        let summaries = try await persistence.fetchChatSessionSummaries(
            forBookWithKey: "nonexistent:key:0"
        )
        #expect(summaries.isEmpty)
    }

    @Test func fetchFullRoundTripsMessagesIncludingCitation() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)

        let created = try await persistence.createChatSession(
            bookFingerprintKey: key,
            title: "Round trip",
            messages: [userMessage("question?"), assistantWithCitation("answer")]
        )

        let fetched = try #require(
            try await persistence.fetchChatSession(sessionId: created.sessionId)
        )
        #expect(fetched.sessionId == created.sessionId)
        #expect(fetched.messages.count == 2)
        #expect(fetched.messages.last?.content == "answer")
        let citations = fetched.messages.last?.citations ?? []
        #expect(citations.count == 1)
        #expect(citations.first?.label == "Chapter 1")
        #expect(citations.first?.sequence == 1)
    }

    @Test func fetchMissingSessionReturnsNil() async throws {
        let persistence = try makePersistence()
        let result = try await persistence.fetchChatSession(sessionId: UUID())
        #expect(result == nil)
    }

    // MARK: - Update

    @Test func updateReplacesMessagesAndDenormalizedFields() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)
        let created = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "T", messages: [userMessage("first")]
        )

        let updated = try await persistence.updateChatSession(
            sessionId: created.sessionId,
            messages: [userMessage("first"), assistantWithCitation("second answer")],
            title: nil
        )

        #expect(updated.messages.count == 2)
        #expect(updated.title == "T")            // nil title leaves it unchanged
        #expect(updated.updatedAt >= created.updatedAt)

        let summary = try #require(
            try await persistence.fetchChatSessionSummaries(forBookWithKey: key).first
        )
        #expect(summary.messageCount == 2)
        #expect(summary.snippet == "second answer")
    }

    @Test func updateWithTitleChangesTitle() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)
        let created = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "Old", messages: [userMessage("x")]
        )

        let updated = try await persistence.updateChatSession(
            sessionId: created.sessionId,
            messages: [userMessage("x")],
            title: "New title"
        )
        #expect(updated.title == "New title")
    }

    @Test func updateMissingSessionThrows() async throws {
        let persistence = try makePersistence()
        await #expect(throws: (any Error).self) {
            _ = try await persistence.updateChatSession(
                sessionId: UUID(), messages: [], title: nil
            )
        }
    }

    // MARK: - Rename

    @Test func renameChangesTitle() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)
        let created = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "Before", messages: [userMessage("x")]
        )

        try await persistence.renameChatSession(sessionId: created.sessionId, title: "After")

        let fetched = try #require(
            try await persistence.fetchChatSession(sessionId: created.sessionId)
        )
        #expect(fetched.title == "After")
    }

    @Test func renameMissingSessionThrows() async throws {
        let persistence = try makePersistence()
        await #expect(throws: (any Error).self) {
            try await persistence.renameChatSession(sessionId: UUID(), title: "x")
        }
    }

    // MARK: - Delete

    @Test func deleteRemovesSession() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)
        let created = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "Doomed", messages: [userMessage("x")]
        )

        try await persistence.deleteChatSession(sessionId: created.sessionId)

        let summaries = try await persistence.fetchChatSessionSummaries(forBookWithKey: key)
        #expect(summaries.isEmpty)
        let fetched = try await persistence.fetchChatSession(sessionId: created.sessionId)
        #expect(fetched == nil)
    }

    @Test func deleteMissingSessionIsIdempotent() async throws {
        let persistence = try makePersistence()
        try await persistence.deleteChatSession(sessionId: UUID())
        // No throw.
    }

    // MARK: - Sort order

    @Test func summariesSortedByUpdatedAtDescending() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)

        let a = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "A", messages: [userMessage("a")]
        )
        let b = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "B", messages: [userMessage("b")]
        )
        // Touch A so its updatedAt is newest → it should sort first.
        _ = try await persistence.updateChatSession(
            sessionId: a.sessionId, messages: [userMessage("a2")], title: nil
        )

        let summaries = try await persistence.fetchChatSessionSummaries(forBookWithKey: key)
        #expect(summaries.count == 2)
        #expect(summaries.first?.id == a.sessionId)
        #expect(summaries.last?.id == b.sessionId)
    }

    // MARK: - Cascade

    @Test func deletingBookCascadesToSessions() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)
        _ = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "Will cascade", messages: [userMessage("x")]
        )

        try await persistence.deleteBook(fingerprintKey: key)

        let summaries = try await persistence.fetchChatSessionSummaries(forBookWithKey: key)
        #expect(summaries.isEmpty)
    }

    // MARK: - Empty + idempotency + CJK

    @Test func emptyMessagesSession() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)

        let created = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "Empty", messages: []
        )
        #expect(created.messages.isEmpty)

        let summary = try #require(
            try await persistence.fetchChatSessionSummaries(forBookWithKey: key).first
        )
        #expect(summary.messageCount == 0)
        #expect(summary.snippet == "")
    }

    @Test func doubleCreateProducesDistinctIds() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)

        let first = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "One", messages: [userMessage("x")]
        )
        let second = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "Two", messages: [userMessage("y")]
        )

        #expect(first.sessionId != second.sessionId)
        let summaries = try await persistence.fetchChatSessionSummaries(forBookWithKey: key)
        #expect(summaries.count == 2)
    }

    @Test func cjkTitleAndContentRoundTrip() async throws {
        let persistence = try makePersistence()
        let key = try await insertBook(persistence)

        let title = "红楼梦の会話"
        let content = "这是一段中文与日本語の混合内容。"
        let created = try await persistence.createChatSession(
            bookFingerprintKey: key,
            title: title,
            messages: [userMessage(content)]
        )

        let fetched = try #require(
            try await persistence.fetchChatSession(sessionId: created.sessionId)
        )
        #expect(fetched.title == title)
        #expect(fetched.messages.first?.content == content)

        let summary = try #require(
            try await persistence.fetchChatSessionSummaries(forBookWithKey: key).first
        )
        #expect(summary.title == title)
        #expect(summary.snippet == content)
    }

    // MARK: - Carry-forward: future-version blob preserved

    @Test func updatePreservesFutureVersionBlob() async throws {
        let schema = Schema(SchemaV9.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let persistence = PersistenceActor(modelContainer: container)
        let key = try await insertBook(persistence)

        let created = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "Future", messages: [userMessage("present")]
        )

        // Simulate a future-build blob the current build cannot interpret by
        // writing a higher-version envelope directly into the stored row.
        let futureBlob = try makeFutureVersionBlob()
        #expect(ChatSessionPayloadMapper.isReadable(futureBlob) == false)
        try writeRawMessagesData(
            futureBlob, sessionId: created.sessionId, container: container
        )

        // An update must NOT clobber the future-version blob with re-encoded
        // current-version messages. A rename CAN still apply.
        _ = try await persistence.updateChatSession(
            sessionId: created.sessionId,
            messages: [userMessage("should not be written")],
            title: "Renamed though"
        )

        let stored = try readRawMessagesData(
            sessionId: created.sessionId, container: container
        )
        #expect(stored == futureBlob)   // blob preserved verbatim

        let fetched = try #require(
            try await persistence.fetchChatSession(sessionId: created.sessionId)
        )
        #expect(fetched.title == "Renamed though")  // rename still applied
        #expect(fetched.messages.isEmpty)            // future blob decodes to []
    }

    // MARK: - Raw-blob test helpers

    @Test func updatePreservesFutureVersionBlobWithIncompatibleShape() async throws {
        // Gate-4 WI-2 Medium: a future blob whose MESSAGE SHAPE can't decode into
        // today's ChatSessionPayload must STILL be protected — `isReadable` inspects
        // only the top-level version header, not the full shape. Pre-fix, the
        // full-decode failure made `isReadable` return true → the blob got clobbered.
        let schema = Schema(SchemaV9.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let persistence = PersistenceActor(modelContainer: container)
        let key = try await insertBook(persistence)

        let created = try await persistence.createChatSession(
            bookFingerprintKey: key, title: "FutureShape", messages: [userMessage("present")]
        )

        // A version newer than this build AND a message shape this build can't decode.
        let incompatible = Data(#"{"version": 4242, "messages": [{"unknownField": "x", "schemaChanged": 1}]}"#.utf8)
        #expect(ChatSessionPayloadMapper.isReadable(incompatible) == false,
                "a future version is protected even when its message shape can't decode")
        try writeRawMessagesData(incompatible, sessionId: created.sessionId, container: container)

        _ = try await persistence.updateChatSession(
            sessionId: created.sessionId,
            messages: [userMessage("must not be written")],
            title: nil
        )

        let stored = try readRawMessagesData(sessionId: created.sessionId, container: container)
        #expect(stored == incompatible, "incompatible-shape future blob preserved verbatim")
    }

    private func makeFutureVersionBlob() throws -> Data {
        // A valid envelope with a version newer than the current build understands.
        let json = #"{"version": 9999, "messages": []}"#
        return Data(json.utf8)
    }

    private func writeRawMessagesData(
        _ data: Data, sessionId: UUID, container: ModelContainer
    ) throws {
        let context = ModelContext(container)
        let predicate = #Predicate<ChatSession> { $0.sessionId == sessionId }
        var descriptor = FetchDescriptor<ChatSession>(predicate: predicate)
        descriptor.fetchLimit = 1
        let session = try #require(try context.fetch(descriptor).first)
        session.messagesData = data
        try context.save()
    }

    private func readRawMessagesData(
        sessionId: UUID, container: ModelContainer
    ) throws -> Data? {
        let context = ModelContext(container)
        let predicate = #Predicate<ChatSession> { $0.sessionId == sessionId }
        var descriptor = FetchDescriptor<ChatSession>(predicate: predicate)
        descriptor.fetchLimit = 1
        let session = try #require(try context.fetch(descriptor).first)
        return session.messagesData
    }
}
