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
        let envelope = try decode(BackupAnnotationsEnvelope.self, from: data)
        try await persistence.restoreBackupAnnotations(envelope)
    }

    func restorePositions(from data: Data) async throws {
        let envelope = try decode(BackupPositionsEnvelope.self, from: data)
        try await persistence.restoreBackupPositions(envelope.positions)
    }

    func restoreSettings(from data: Data) async throws {
        let envelope = try decode(BackupSettingsEnvelope.self, from: data)
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
        let envelope = try decode(BackupCollectionsEnvelope.self, from: data)
        try await persistence.restoreBackupCollections(envelope.collections)
    }

    func restoreBookSources(from data: Data) async throws {
        let envelope = try decode(BackupBookSourcesEnvelope.self, from: data)
        try await persistence.upsertBackupBookSources(envelope.sources)
    }

    func restorePerBookSettings(from data: Data) async throws {
        let envelope = try decode(BackupPerBookSettingsEnvelope.self, from: data)
        for entry in envelope.entries {
            do {
                try PerBookSettingsStore.save(
                    entry.override,
                    for: entry.bookFingerprintKey,
                    baseURL: perBookSettingsBaseURL
                )
            } catch {
                log.error(
                    "Failed to save per-book settings for \(entry.bookFingerprintKey, privacy: .public): \(String(describing: error), privacy: .public)"
                )
            }
        }
    }

    func restoreReplacementRules(from data: Data) async throws {
        let envelope = try decode(BackupReplacementRulesEnvelope.self, from: data)
        try await persistence.upsertBackupReplacementRules(envelope.rules)
    }

    // MARK: - Helpers

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
