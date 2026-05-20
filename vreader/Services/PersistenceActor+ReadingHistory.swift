// Purpose: Extension adding reading-history backup RESTORE to PersistenceActor
// (feature #58 WI-5). Upserts ReadingSession + ReadingStats rows from the
// `reading-history.json` backup section.
//
// Why a separate file (not PersistenceActor+Backup.swift): that file is already
// over the ~300-line guideline; this is a self-contained restore method.
//
// Key decisions:
// - UPSERT keyed by the @Attribute(.unique) columns (ReadingSession.sessionId,
//   ReadingStats.bookFingerprintKey) — prefetch + update-in-place + insert-if-
//   absent, exactly how restoreBackupAnnotations avoids the unique-constraint
//   violation on a re-run.
// - ReadingStats fields are written VERBATIM from the backup — restore does NOT
//   call recomputeStats. recomputeStats force-sets lastReadAt = Date() (its
//   "Bug #45 v5" line, correct for the reader-close caller, wrong for restore);
//   calling it would rewrite every restored lastReadAt to restore-time and
//   violate criterion (f) "preserves ReadingStats exactly".
// - Conflict policy: the backup value WINS (a restore is an explicit "make this
//   device match the backup" act). Local rows not in the backup are untouched
//   (additive merge, like every other restore section).
//
// @coordinates-with: BackupReadingHistory.swift, BackupDataRestorer.swift,
//   ReadingSession.swift, ReadingStats.swift

import Foundation
import OSLog
import SwiftData

private let log = Logger(subsystem: "com.vreader.app", category: "BackupRestorer")

extension PersistenceActor {

    /// Restores the `reading-history.json` section — upserts every
    /// `ReadingSession` and `ReadingStats` row from the backup.
    func restoreReadingHistory(_ envelope: BackupReadingHistoryEnvelope) async throws {
        let context = ModelContext(modelContainer)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try restoreSessions(envelope.sessions, context: context, decoder: decoder)
        try restoreStats(envelope.stats, context: context)

        try context.save()
    }

    // MARK: - Sessions

    private func restoreSessions(
        _ sessions: [BackupReadingSession], context: ModelContext, decoder: JSONDecoder
    ) throws {
        // Prefetch every existing session, indexed by the unique sessionId.
        let existing = try context.fetch(FetchDescriptor<ReadingSession>())
        var byId: [UUID: ReadingSession] = [:]
        for session in existing { byId[session.sessionId] = session }

        for backup in sessions {
            // The DocumentFingerprint is reconstructed from the canonical key.
            guard let fingerprint = DocumentFingerprint(canonicalKey: backup.bookFingerprintKey) else {
                log.error("Skipping reading session with unparseable fingerprint key")
                continue
            }
            let startLocator = decodeLocator(backup.startLocatorJSON, decoder: decoder)
            let endLocator = decodeLocator(backup.endLocatorJSON, decoder: decoder)

            if let row = byId[backup.sessionId] {
                // Update in place — the model's mutators (@Model didSet is
                // unreliable). The backup value wins.
                row.updateBookFingerprint(fingerprint)
                row.startedAt = backup.startedAt
                row.endedAt = backup.endedAt
                row.updateDuration(backup.durationSeconds)
                row.updatePagesRead(backup.pagesRead)
                row.updateWordsRead(backup.wordsRead)
                row.startLocator = startLocator
                row.endLocator = endLocator
                row.deviceId = backup.deviceId
                row.isRecovered = backup.isRecovered
            } else {
                let row = ReadingSession(
                    sessionId: backup.sessionId,
                    bookFingerprint: fingerprint,
                    startedAt: backup.startedAt,
                    endedAt: backup.endedAt,
                    durationSeconds: backup.durationSeconds,
                    pagesRead: backup.pagesRead,
                    wordsRead: backup.wordsRead,
                    startLocator: startLocator,
                    endLocator: endLocator,
                    deviceId: backup.deviceId,
                    isRecovered: backup.isRecovered
                )
                context.insert(row)
                byId[backup.sessionId] = row
            }
        }
    }

    // MARK: - Stats

    private func restoreStats(
        _ stats: [BackupReadingStats], context: ModelContext
    ) throws {
        // Prefetch existing stats, indexed by the unique bookFingerprintKey.
        let existing = try context.fetch(FetchDescriptor<ReadingStats>())
        var byKey: [String: ReadingStats] = [:]
        for row in existing where byKey[row.bookFingerprintKey] == nil {
            byKey[row.bookFingerprintKey] = row
        }

        for backup in stats {
            guard let fingerprint = DocumentFingerprint(canonicalKey: backup.bookFingerprintKey) else {
                log.error("Skipping reading stats with unparseable fingerprint key")
                continue
            }
            let row: ReadingStats
            if let existingRow = byKey[backup.bookFingerprintKey] {
                row = existingRow
            } else {
                row = ReadingStats(bookFingerprint: fingerprint)
                context.insert(row)
                byKey[backup.bookFingerprintKey] = row
            }
            // Write the backed-up scalars VERBATIM — no recomputeStats (which
            // would stamp lastReadAt = Date() and violate criterion (f)).
            row.totalReadingSeconds = backup.totalReadingSeconds
            row.sessionCount = backup.sessionCount
            row.lastReadAt = backup.lastReadAt
            row.averagePagesPerHour = backup.averagePagesPerHour
            row.averageWordsPerMinute = backup.averageWordsPerMinute
            row.totalPagesRead = backup.totalPagesRead
            row.totalWordsRead = backup.totalWordsRead
            row.longestSessionSeconds = backup.longestSessionSeconds
        }
    }

    // MARK: - Helpers

    /// Decodes a `Locator` JSON string; a nil or malformed string degrades to
    /// nil (the session still restores — only its locator is dropped) rather
    /// than failing the whole section.
    private func decodeLocator(_ json: String?, decoder: JSONDecoder) -> Locator? {
        guard let json,
              let data = json.data(using: .utf8),
              let locator = try? decoder.decode(Locator.self, from: data)
        else { return nil }
        return locator
    }
}
