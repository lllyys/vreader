// Purpose: Lightweight value types for ChatSession cross-actor transfer (Feature
// #88 WI-1). Mirrors HighlightRecord — never pass @Model objects across the
// PersistenceActor boundary. `ChatSessionRecord` is the FULL DTO (carries the
// decoded message array); `ChatSessionSummary` is the list-row projection built
// from the DENORMALIZED columns, requiring no blob decode.
//
// @coordinates-with: ChatSession.swift, PersistenceActor+ChatSessions.swift (WI-2)

import Foundation

/// Full value-type DTO for a chat session across the actor boundary.
struct ChatSessionRecord: Sendable, Equatable, Identifiable {
    var id: UUID { sessionId }

    let sessionId: UUID
    let bookFingerprintKey: String
    let title: String
    let messages: [ChatMessage]
    let createdAt: Date
    let updatedAt: Date
}

/// List-row projection of a chat session, built from the denormalized
/// `lastMessageSnippet` / `messageCount` columns — no blob decode required.
struct ChatSessionSummary: Sendable, Identifiable {
    let id: UUID
    let title: String
    let snippet: String
    let updatedAt: Date
    let messageCount: Int
}
