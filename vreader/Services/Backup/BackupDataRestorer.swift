// Purpose: Production BackupDataRestoring implementation that decodes
// JSON sections produced by BackupDataCollector and writes them back into
// the persistence layer.
//
// Each restore method:
// - Decodes the section's versioned envelope.
// - Skips entries that no longer apply (missing books, malformed locators).
// - Uses additive upsert semantics: existing rows are updated in place,
//   missing rows are inserted, and entries already present are deduped via
//   PersistenceActor's existing dedupe logic (e.g. highlight profileKey).
// - Never deletes local data the backup doesn't mention. Restoration is a
//   merge, not a replace.
//
// @coordinates-with: BackupDataCollector.swift, PersistenceActor+Backup.swift,
//   WebDAVProvider.swift, ReaderSettingsStore.swift, PerBookSettings.swift

import Foundation
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "BackupRestorer")

/// Production BackupDataRestoring impl. Consumes Data blobs from the archive
/// and applies them to the persistence layer + UserDefaults.
final class BackupDataRestorer: BackupDataRestoring, @unchecked Sendable {
    private let persistence: PersistenceActor
    private let defaults: UserDefaults
    private let perBookSettingsBaseURL: URL

    init(
        persistence: PersistenceActor,
        defaults: UserDefaults = .standard,
        perBookSettingsBaseURL: URL
    ) {
        self.persistence = persistence
        self.defaults = defaults
        self.perBookSettingsBaseURL = perBookSettingsBaseURL
    }

    func restoreAnnotations(from data: Data) async throws {
        let envelope = try decodeAndValidate(BackupAnnotationsEnvelope.self, from: data, section: "annotations")
        try await persistence.restoreBackupAnnotations(envelope)
    }

    func restorePositions(from data: Data) async throws {
        let envelope = try decodeAndValidate(BackupPositionsEnvelope.self, from: data, section: "positions")
        try await persistence.restoreBackupPositions(envelope.positions)
    }

    func restoreSettings(from data: Data) async throws {
        let envelope = try decodeAndValidate(BackupSettingsEnvelope.self, from: data, section: "settings")
        for (key, value) in envelope.defaults {
            switch value {
            case .bool(let v): defaults.set(v, forKey: key)
            case .int(let v): defaults.set(v, forKey: key)
            case .double(let v): defaults.set(v, forKey: key)
            case .string(let v): defaults.set(v, forKey: key)
            case .data(let v): defaults.set(v, forKey: key)
            }
        }
    }

    func restoreCollections(from data: Data) async throws {
        let envelope = try decodeAndValidate(BackupCollectionsEnvelope.self, from: data, section: "collections")
        try await persistence.restoreBackupCollections(envelope.collections)
    }

    func restoreBookSources(from data: Data) async throws {
        let envelope = try decodeAndValidate(BackupBookSourcesEnvelope.self, from: data, section: "book-sources")
        try await persistence.upsertBackupBookSources(envelope.sources)
    }

    func restorePerBookSettings(from data: Data) async throws {
        let envelope = try decodeAndValidate(BackupPerBookSettingsEnvelope.self, from: data, section: "per-book-settings")
        var failures = 0
        for entry in envelope.entries {
            do {
                try PerBookSettingsStore.save(
                    entry.override,
                    for: entry.bookFingerprintKey,
                    baseURL: perBookSettingsBaseURL
                )
            } catch {
                failures += 1
                log.error(
                    "Failed to save per-book settings for \(entry.bookFingerprintKey, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
        if failures > 0 {
            throw BackupRestoreError.partialFailure(
                section: "per-book-settings",
                failed: failures,
                total: envelope.entries.count
            )
        }
    }

    func restoreReplacementRules(from data: Data) async throws {
        let envelope = try decodeAndValidate(BackupReplacementRulesEnvelope.self, from: data, section: "replacement-rules")
        try await persistence.upsertBackupReplacementRules(envelope.rules)
    }

    func restoreReadingHistory(from data: Data) async throws {
        let envelope = try decodeAndValidate(
            BackupReadingHistoryEnvelope.self, from: data, section: "reading-history"
        )
        try await persistence.restoreReadingHistory(envelope)
    }

    func restoreAIConversations(from data: Data) async throws {
        let envelope = try decodeAndValidate(
            BackupAIConversationsEnvelope.self, from: data, section: "ai-conversations"
        )
        try await persistence.restoreAIConversations(envelope)
    }

    // MARK: - Helpers

    private func decodeAndValidate<T: Decodable & BackupVersionedEnvelope>(
        _ type: T.Type, from data: Data, section: String
    ) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(type, from: data)
        // Validate against the explicit accepted SET, not the single "current"
        // constant: the v1↔v2 envelope shapes for the pre-v2 sections are
        // identical (no field migration), so a v1 archive must still restore
        // after the v2 bump. A genuinely-newer archive (v3+) is absent from the
        // set and still throws — accepting anything `<= current` would silently
        // pass a too-new archive without the handling it needs.
        guard kBackupAcceptedSchemaVersions.contains(envelope.schemaVersion) else {
            throw BackupRestoreError.unsupportedSchemaVersion(
                section: section,
                actual: envelope.schemaVersion,
                supported: kBackupCurrentSchemaVersion
            )
        }
        return envelope
    }
}
