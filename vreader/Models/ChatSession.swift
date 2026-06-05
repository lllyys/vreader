// Purpose: A persisted, switchable AI conversation about a book (Feature #88).
// One book may have many sessions; the active conversation can be switched,
// renamed, and deleted. Mirrors the Highlight @Model shape: a `@Attribute(.unique)`
// primitive key, a `Data?` blob column for the message array, and a `@Transient`
// computed accessor that maps blob ⇄ domain via ChatSessionPayloadMapper (like
// `Highlight.anchorData` / `Highlight.anchor`).
//
// Key decisions:
// - messagesData is stored as raw Data? to avoid SwiftData Codable decode
//   crashes on legacy/corrupted rows; the computed `messages` property decodes
//   tolerantly (nil/empty/garbage → []), never crashing.
// - `book` is the OPTIONAL INVERSE back-reference only; the book-delete cascade
//   lives on the PARENT array `Book.chatSessions` (Gate-2 High 1).
// - lastMessageSnippet / messageCount are DENORMALIZED summary columns so the
//   Conversations-sheet list renders without decoding every blob (Gate-2 M1).
//   They are maintained on save by the persistence layer (WI-2).
//
// @coordinates-with: ChatSessionPayload.swift, ChatSessionRecord.swift, Book.swift,
//   PersistenceActor+ChatSessions.swift (WI-2)

import Foundation
import SwiftData

@Model
final class ChatSession {
    @Attribute(.unique) var sessionId: UUID

    /// The book this conversation belongs to (matches `Book.fingerprintKey`).
    var bookFingerprintKey: String

    /// Display title — auto-derived from the first user message, else "New conversation".
    var title: String

    /// Raw JSON bytes of the `ChatSessionPayload` envelope. Stored as a simple
    /// Data? column (not the domain type, which is not Codable). Use the computed
    /// `messages` accessor for typed access.
    var messagesData: Data?

    // MARK: - Denormalized summary (Gate-2 Medium 1)

    /// Snippet of the last message, maintained on save — lets the Conversations
    /// list render without decoding the blob.
    var lastMessageSnippet: String

    /// Number of messages in the conversation, maintained on save.
    var messageCount: Int

    var createdAt: Date
    var updatedAt: Date

    // MARK: - Computed Messages

    /// Decoded messages from `messagesData`. Returns [] when data is missing,
    /// empty, or corrupted — never crashes.
    @Transient var messages: [ChatMessage] {
        ChatSessionPayloadMapper.decode(messagesData)
    }

    // MARK: - Relationship

    /// Optional inverse back-reference. The cascade lives on `Book.chatSessions`.
    var book: Book?

    // MARK: - Init

    init(
        sessionId: UUID = UUID(),
        bookFingerprintKey: String,
        title: String = "New conversation",
        messages: [ChatMessage] = [],
        createdAt: Date = Date()
    ) {
        self.sessionId = sessionId
        self.bookFingerprintKey = bookFingerprintKey
        self.title = title
        self.messagesData = ChatSessionPayloadMapper.encode(messages)
        self.lastMessageSnippet = messages.last?.content ?? ""
        self.messageCount = messages.count
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }
}
