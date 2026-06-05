// Purpose: Extension adding AI-conversations backup FETCH + RESTORE to
// PersistenceActor (feature #89). Collects every ChatSession (Feature #88) into
// Sendable value types for the `ai-conversations.json` section, and upserts
// them back on restore.
//
// Why a separate file (not PersistenceActor+ChatSessions.swift): that file owns
// the live CRUD; this is the self-contained backup fetch + restore, mirroring
// PersistenceActor+ReadingHistory.swift.
//
// Key decisions:
// - fetch returns [BackupChatSession] value types — never a @Model across the
//   actor boundary. Sorted by createdAt for deterministic output. The message
//   blob is copied RAW (s.messagesData → messagesPayloadData), byte-exact.
// - restore UPSERTs keyed by @Attribute(.unique) sessionId: prefetch existing +
//   books, update-in-place / insert-if-absent (same shape as restoreSessions).
// - "backup value wins": the existing-row branch ALWAYS re-keys
//   row.bookFingerprintKey = backup.bookFingerprintKey, so a restore over a
//   drifted local row doesn't keep the stale key (summaries fetch by key).
// - honors the #88 ChatSessionPayloadMapper.isReadable never-clobber contract:
//   a future-version blob is preserved (metadata may still update).
// - re-associates row.book if the book exists locally; CLEARS row.book = nil
//   when absent so a stale relation isn't left mis-linked. The book.chatSessions
//   append is guarded against double-insert (idempotent).
//
// @coordinates-with: BackupAIConversations.swift, BackupDataCollector.swift,
//   BackupDataRestorer.swift, ChatSession.swift, ChatSessionPayload.swift, Book.swift

import Foundation
import SwiftData

extension PersistenceActor {

    /// Collect side — every ChatSession as a Sendable DTO (book-independent,
    /// captures sessions whose book was deleted). Sorted by createdAt.
    func fetchAllChatSessionsForBackup() async throws -> [BackupChatSession] {
        let context = ModelContext(modelContainer)
        let sessions = try context.fetch(FetchDescriptor<ChatSession>(
            sortBy: [SortDescriptor(\.createdAt)]
        ))
        return sessions.map { s in
            BackupChatSession(
                sessionId: s.sessionId,
                bookFingerprintKey: s.bookFingerprintKey,
                title: s.title,
                messagesPayloadData: s.messagesData,   // raw bytes, byte-exact
                lastMessageSnippet: s.lastMessageSnippet,
                messageCount: s.messageCount,
                createdAt: s.createdAt,
                updatedAt: s.updatedAt
            )
        }
    }

    /// Restore side — upserts every backed-up ChatSession by its unique
    /// `sessionId`, re-keying to the backup's book and re-associating the
    /// `book` relation when that book exists locally.
    func restoreAIConversations(_ envelope: BackupAIConversationsEnvelope) async throws {
        let context = ModelContext(modelContainer)

        let existing = try context.fetch(FetchDescriptor<ChatSession>())
        var byId: [UUID: ChatSession] = [:]
        for s in existing where byId[s.sessionId] == nil { byId[s.sessionId] = s }

        var bookByKey: [String: Book] = [:]
        for b in try context.fetch(FetchDescriptor<Book>()) where bookByKey[b.fingerprintKey] == nil {
            bookByKey[b.fingerprintKey] = b
        }

        for backup in envelope.sessions {
            let row: ChatSession
            if let existingRow = byId[backup.sessionId] {
                row = existingRow
                // Never clobber a future-version blob (the #88 contract).
                if ChatSessionPayloadMapper.isReadable(row.messagesData) {
                    row.messagesData = backup.messagesPayloadData
                    row.lastMessageSnippet = backup.lastMessageSnippet
                    row.messageCount = backup.messageCount
                }
                // "backup value wins" — always re-key to the backup's book so a
                // drifted local row doesn't keep a stale key.
                row.bookFingerprintKey = backup.bookFingerprintKey
                row.title = backup.title
                row.createdAt = backup.createdAt
                row.updatedAt = backup.updatedAt
            } else {
                let newRow = ChatSession(
                    sessionId: backup.sessionId,
                    bookFingerprintKey: backup.bookFingerprintKey,
                    title: backup.title,
                    createdAt: backup.createdAt
                )
                newRow.messagesData = backup.messagesPayloadData
                newRow.lastMessageSnippet = backup.lastMessageSnippet
                newRow.messageCount = backup.messageCount
                newRow.updatedAt = backup.updatedAt
                context.insert(newRow)
                byId[backup.sessionId] = newRow
                row = newRow
            }

            if let book = bookByKey[backup.bookFingerprintKey] {
                if row.book?.fingerprintKey != book.fingerprintKey {
                    row.book = book
                }
                if !book.chatSessions.contains(where: { $0.sessionId == row.sessionId }) {
                    book.chatSessions.append(row)
                }
            } else {
                // Book absent → clear any stale relation; the row stays queryable
                // via its (re-keyed) bookFingerprintKey.
                row.book = nil
            }
        }

        try context.save()
    }
}
