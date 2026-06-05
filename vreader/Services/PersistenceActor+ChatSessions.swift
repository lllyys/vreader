// Purpose: Extension adding ChatSessionPersisting conformance to PersistenceActor
// (Feature #88 WI-2). Provides chat-session CRUD for the AI Chat tab. Mirrors
// PersistenceActor+Highlights: `ModelContext(modelContainer)`, `#Predicate`,
// `FetchDescriptor` with `fetchLimit`, `context.insert`, `try context.save()`,
// and maps @Model → ChatSessionRecord / ChatSessionSummary value types (never
// returns the @Model across the actor boundary).
//
// Sessions attach to the owning `Book` (fetched by `fingerprintKey`) so a
// book-delete cascades to its sessions via `Book.chatSessions`.
//
// Carry-forward contract (WI-1 Gate-4 audit):
// - create/update encode messages via ChatSessionPayloadMapper.encode → Data?;
//   on nil (encode failure) the messagesData write is SKIPPED so a good blob is
//   never overwritten with nil.
// - update does NOT re-encode when the EXISTING blob is `!isReadable` (a
//   future-version blob written by a newer build is preserved, not clobbered;
//   a rename may still apply).
// - the denormalized lastMessageSnippet / messageCount / updatedAt columns are
//   maintained on every create/update.
//
// @coordinates-with: PersistenceActor.swift, ChatSessionPersisting.swift,
//   ChatSession.swift, ChatSessionRecord.swift, ChatSessionPayload.swift, Book.swift

import Foundation
import SwiftData

extension PersistenceActor: ChatSessionPersisting {

    /// Trimmed prefix of a message's content used for the denormalized snippet.
    private static let snippetMaxLength = 80

    func createChatSession(
        bookFingerprintKey: String,
        title: String,
        messages: [ChatMessage]
    ) async throws -> ChatSessionRecord {
        let context = ModelContext(modelContainer)
        let key = bookFingerprintKey
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw ImportError.bookNotFound(key)
        }

        let session = ChatSession(
            bookFingerprintKey: bookFingerprintKey,
            title: title,
            messages: messages
        )
        // Denormalized columns: ChatSession.init seeds these from `messages`, but
        // snippet must be the trimmed prefix per the carry-forward contract.
        session.lastMessageSnippet = Self.snippet(for: messages)
        session.messageCount = messages.count

        session.book = book
        book.chatSessions.append(session)
        context.insert(session)
        try context.save()

        return Self.record(from: session)
    }

    func fetchChatSessionSummaries(forBookWithKey key: String) async throws -> [ChatSessionSummary] {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<ChatSession> { $0.bookFingerprintKey == key }
        let descriptor = FetchDescriptor<ChatSession>(predicate: predicate)

        let sessions = try context.fetch(descriptor)
        return sessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { Self.summary(from: $0) }
    }

    func fetchChatSession(sessionId: UUID) async throws -> ChatSessionRecord? {
        let context = ModelContext(modelContainer)
        let id = sessionId
        let predicate = #Predicate<ChatSession> { $0.sessionId == id }
        var descriptor = FetchDescriptor<ChatSession>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let session = try context.fetch(descriptor).first else {
            return nil
        }
        return Self.record(from: session)
    }

    func updateChatSession(
        sessionId: UUID,
        messages: [ChatMessage],
        title: String?
    ) async throws -> ChatSessionRecord {
        let context = ModelContext(modelContainer)
        let id = sessionId
        let predicate = #Predicate<ChatSession> { $0.sessionId == id }
        var descriptor = FetchDescriptor<ChatSession>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let session = try context.fetch(descriptor).first else {
            throw PersistenceError.recordNotFound("ChatSession \(sessionId)")
        }

        // Carry-forward: PRESERVE a future-version blob (existing data the current
        // build cannot interpret). A rename may still apply, but messages and the
        // denormalized message columns are left untouched so a newer build's data
        // is not clobbered.
        let canWriteMessages = ChatSessionPayloadMapper.isReadable(session.messagesData)
        if canWriteMessages {
            // Carry-forward: SKIP the write when encode fails (returns nil) so a
            // good stored blob is never overwritten with nil.
            if let encoded = ChatSessionPayloadMapper.encode(messages) {
                session.messagesData = encoded
                session.lastMessageSnippet = Self.snippet(for: messages)
                session.messageCount = messages.count
            }
        }

        if let title {
            session.title = title
        }
        session.updatedAt = Date()
        try context.save()

        return Self.record(from: session)
    }

    func renameChatSession(sessionId: UUID, title: String) async throws {
        let context = ModelContext(modelContainer)
        let id = sessionId
        let predicate = #Predicate<ChatSession> { $0.sessionId == id }
        var descriptor = FetchDescriptor<ChatSession>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let session = try context.fetch(descriptor).first else {
            throw PersistenceError.recordNotFound("ChatSession \(sessionId)")
        }

        session.title = title
        session.updatedAt = Date()
        try context.save()
    }

    func deleteChatSession(sessionId: UUID) async throws {
        let context = ModelContext(modelContainer)
        let id = sessionId
        let predicate = #Predicate<ChatSession> { $0.sessionId == id }
        var descriptor = FetchDescriptor<ChatSession>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let session = try context.fetch(descriptor).first else {
            return  // idempotent — missing id is a no-op
        }

        context.delete(session)
        try context.save()
    }

    // MARK: - Private mapping

    private static func snippet(for messages: [ChatMessage]) -> String {
        guard let content = messages.last?.content else { return "" }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(snippetMaxLength))
    }

    private static func record(from session: ChatSession) -> ChatSessionRecord {
        ChatSessionRecord(
            sessionId: session.sessionId,
            bookFingerprintKey: session.bookFingerprintKey,
            title: session.title,
            messages: session.messages,
            createdAt: session.createdAt,
            updatedAt: session.updatedAt
        )
    }

    private static func summary(from session: ChatSession) -> ChatSessionSummary {
        ChatSessionSummary(
            id: session.sessionId,
            title: session.title,
            snippet: session.lastMessageSnippet,
            updatedAt: session.updatedAt,
            messageCount: session.messageCount
        )
    }
}
