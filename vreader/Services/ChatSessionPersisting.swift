// Purpose: Boundary protocol for chat-session persistence operations (Feature
// #88 WI-2). Mirrors HighlightPersisting — enables mock injection in the VM
// tests (WI-3) and keeps the @MainActor AIChatViewModel decoupled from the
// concrete PersistenceActor.
//
// @coordinates-with: PersistenceActor+ChatSessions.swift, ChatSessionRecord.swift,
//   ChatSession.swift, ChatMessage.swift

import Foundation

/// Protocol for chat-session persistence operations, enabling mock injection in tests.
protocol ChatSessionPersisting: Sendable {
    /// Creates a new chat session for a book. Returns the created record.
    /// The session attaches to the `Book` identified by `bookFingerprintKey`
    /// so a book-delete cascades to its sessions.
    func createChatSession(
        bookFingerprintKey: String,
        title: String,
        messages: [ChatMessage]
    ) async throws -> ChatSessionRecord

    /// Fetches the list-row summaries for a book, sorted by `updatedAt` descending.
    /// Built from the denormalized columns — no message-blob decode.
    func fetchChatSessionSummaries(forBookWithKey key: String) async throws -> [ChatSessionSummary]

    /// Fetches a single session's full DTO (with decoded messages), or nil if absent.
    func fetchChatSession(sessionId: UUID) async throws -> ChatSessionRecord?

    /// Replaces a session's messages (and optionally its title). Maintains the
    /// denormalized snippet / count and bumps `updatedAt`. Returns the updated record.
    /// `title: nil` leaves the existing title unchanged.
    func updateChatSession(
        sessionId: UUID,
        messages: [ChatMessage],
        title: String?
    ) async throws -> ChatSessionRecord

    /// Renames a session (title only); bumps `updatedAt`.
    func renameChatSession(sessionId: UUID, title: String) async throws

    /// Deletes a session by id. Idempotent — a missing id is a no-op.
    func deleteChatSession(sessionId: UUID) async throws
}
