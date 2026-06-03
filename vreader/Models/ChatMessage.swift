// Purpose: Data model for individual chat messages in multi-turn AI conversations.
// Used by AIChatViewModel to track conversation history.
//
// Key decisions:
// - Identifiable for SwiftUI ForEach without explicit id.
// - Sendable for Swift 6 strict concurrency.
// - Timestamp stored for display and potential persistence.
// - Role enum covers user, assistant, and system (for book context injection).
//
// @coordinates-with: AIChatViewModel.swift, AIChatView.swift

import Foundation

/// The role of a message in an AI conversation.
enum ChatRole: String, Sendable, Equatable {
    case user
    case assistant
    case system
}

/// A single message in a multi-turn AI chat conversation.
struct ChatMessage: Identifiable, Sendable, Equatable {
    let id: UUID
    let role: ChatRole
    /// Message content. Mutable to support incremental streaming updates.
    var content: String
    let timestamp: Date
    /// Feature #86 WI-6: the provenance an assistant reply drew on — the "Drew on"
    /// chips. Stamped from the send-time snapshot of the context the request used.
    var citations: [ChatCitation]

    init(
        id: UUID = UUID(),
        role: ChatRole,
        content: String,
        timestamp: Date = Date(),
        citations: [ChatCitation] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.citations = citations
    }
}
