// Purpose: Codable DTOs for the `reading-history.json` backup section
// (feature #58 WI-5) — ReadingSession + ReadingStats round-tripped through
// the WebDAV backup ZIP.
//
// This section is NEW in backup schema v2. A v1 archive simply lacks the
// `reading-history.json` entry; the restorer skips it (edge case f).
//
// Kept in its own file rather than swelling BackupSectionDTOs.swift past the
// ~300-line guideline.
//
// @coordinates-with: BackupSectionDTOs.swift, BackupDataCollector.swift,
//   BackupDataRestorer.swift, PersistenceActor+Backup.swift, ReadingSession.swift,
//   ReadingStats.swift

import Foundation

/// The `reading-history.json` section envelope — every `ReadingSession` plus
/// every `ReadingStats` row, so a restore reproduces reading history exactly.
struct BackupReadingHistoryEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let sessions: [BackupReadingSession]
    let stats: [BackupReadingStats]
}

/// One `ReadingSession` row. Mirrors EVERY persisted field so criterion (f)
/// ("preserves `ReadingSession` exactly") holds. `bookFingerprintKey` IS the
/// canonical key — the `DocumentFingerprint` is reconstructed on restore via
/// `init(canonicalKey:)`, exactly as `BackupLibraryEntry` does. Locators
/// round-trip as JSON strings (matching `BackupHighlight.locatorJSON`).
struct BackupReadingSession: Codable, Sendable, Equatable {
    let sessionId: UUID
    /// == `DocumentFingerprint.canonicalKey`.
    let bookFingerprintKey: String
    let startedAt: Date
    let endedAt: Date?
    let durationSeconds: Int
    let pagesRead: Int?
    let wordsRead: Int?
    /// `Locator` as a JSON string; nil when the session has no start locator.
    let startLocatorJSON: String?
    let endLocatorJSON: String?
    let deviceId: String
    let isRecovered: Bool
}

/// One `ReadingStats` row — the per-book lifetime aggregate. Restored verbatim
/// (NOT recomputed) so the backed-up `lastReadAt` survives intact.
struct BackupReadingStats: Codable, Sendable, Equatable {
    let bookFingerprintKey: String
    let totalReadingSeconds: Int
    let sessionCount: Int
    let lastReadAt: Date?
    let averagePagesPerHour: Double?
    let averageWordsPerMinute: Double?
    let totalPagesRead: Int?
    let totalWordsRead: Int?
    let longestSessionSeconds: Int
}
