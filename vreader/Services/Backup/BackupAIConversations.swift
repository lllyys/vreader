// Purpose: Codable DTOs for the `ai-conversations.json` backup section
// (feature #89) — every persisted ChatSession (Feature #88), including its
// message blob, round-tripped through the WebDAV backup ZIP so a restore
// reproduces AI conversation history exactly.
//
// This section is NEW in backup schema v3. A v1/v2 archive simply lacks the
// `ai-conversations.json` entry; the restorer skips it (forward compat).
//
// Kept in its own file rather than swelling BackupSectionDTOs.swift past the
// ~300-line guideline (mirrors BackupReadingHistory.swift).
//
// @coordinates-with: BackupSectionDTOs.swift, BackupDataCollector.swift,
//   BackupDataRestorer.swift, PersistenceActor+ChatSessionsBackup.swift,
//   ChatSession.swift, ChatSessionPayload.swift

import Foundation

/// The `ai-conversations.json` section envelope — every persisted ChatSession
/// (with its message blob) so a restore reproduces AI history exactly.
/// New in backup schema v3 (feature #89).
struct BackupAIConversationsEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let sessions: [BackupChatSession]
}

/// One persisted ChatSession row. Carries the messages as the SAME versioned
/// `ChatSessionPayload` blob stored in `ChatSession.messagesData` — we do NOT
/// re-derive a parallel Codable mirror of messages/citations (that already
/// lives in ChatSessionPayload.swift). `messagesPayloadData` carries the RAW
/// bytes (Codable serializes `Data` as base64 in JSON), nil when the stored
/// `messagesData` was nil. The denormalized snippet/count are carried so a
/// restore reproduces the Conversations-list projection without a re-decode.
///
/// The field is `Data?`, NOT a `String?` UTF-8 transcode: `messagesData`'s live
/// contract is raw bytes tolerant of corrupted/legacy/non-UTF8 content, and a
/// UTF-8 string round-trip would collapse non-UTF8 bytes to nil, silently
/// losing the blob. `Codable` already encodes `Data` as base64, so byte-
/// exactness is free.
struct BackupChatSession: Codable, Sendable, Equatable {
    let sessionId: UUID
    /// == `DocumentFingerprint.canonicalKey` of the owning book.
    let bookFingerprintKey: String
    let title: String
    /// Raw `ChatSessionPayload` blob bytes (byte-exact), nil when none stored.
    let messagesPayloadData: Data?
    let lastMessageSnippet: String
    let messageCount: Int
    let createdAt: Date
    let updatedAt: Date
}
