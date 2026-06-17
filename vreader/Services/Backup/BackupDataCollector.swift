// Purpose: Production BackupDataCollecting implementation that serializes
// app state into JSON Data blobs for the WebDAV backup ZIP archive.
//
// Each method emits a versioned JSON envelope so future schema changes can
// remain backward-compatible. Restoration is mirrored in BackupDataRestorer.
//
// Schema decisions:
// - Every section JSON has a `schemaVersion` field for forward compat.
// - Highlights/bookmarks/notes are flattened across all books and tagged
//   with `bookFingerprintKey` so restore can re-attach to existing books.
// - Locator round-trips as JSON-encoded value (Locator is Codable).
// - Books that no longer exist on the restoring device are silently skipped.
//
// @coordinates-with: BackupSectionDTOs.swift, BackupDataRestorer.swift,
//   PersistenceActor+Backup.swift, WebDAVProvider.swift

import Foundation
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "BackupCollector")

/// Production BackupDataCollecting impl. Reads from PersistenceActor for
/// SwiftData-backed sections, from UserDefaults for global settings, and from
/// the file-based PerBookSettingsStore for per-book overrides.
final class BackupDataCollector: BackupDataCollecting, @unchecked Sendable {
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

    func collectAnnotations() async throws -> Data {
        let books = try await persistence.fetchAllLibraryBooks()
        var highlights: [BackupHighlight] = []
        var bookmarks: [BackupBookmark] = []
        var notes: [BackupNote] = []
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        for book in books {
            let key = book.fingerprintKey
            let hs = (try? await persistence.fetchHighlights(forBookWithKey: key)) ?? []
            let bs = (try? await persistence.fetchBookmarks(forBookWithKey: key)) ?? []
            let ns = (try? await persistence.fetchAnnotations(forBookWithKey: key)) ?? []

            for h in hs {
                guard let locJSON = locatorJSON(h.locator, encoder: encoder) else { continue }
                highlights.append(BackupHighlight(
                    highlightId: h.highlightId,
                    bookFingerprintKey: key,
                    locatorJSON: locJSON,
                    selectedText: h.selectedText,
                    color: h.color,
                    note: h.note,
                    createdAt: h.createdAt,
                    updatedAt: h.updatedAt
                ))
            }
            for b in bs {
                guard let locJSON = locatorJSON(b.locator, encoder: encoder) else { continue }
                bookmarks.append(BackupBookmark(
                    bookmarkId: b.bookmarkId,
                    bookFingerprintKey: key,
                    locatorJSON: locJSON,
                    title: b.title,
                    createdAt: b.createdAt,
                    updatedAt: b.updatedAt
                ))
            }
            for n in ns {
                guard let locJSON = locatorJSON(n.locator, encoder: encoder) else { continue }
                notes.append(BackupNote(
                    annotationId: n.annotationId,
                    bookFingerprintKey: key,
                    locatorJSON: locJSON,
                    content: n.content,
                    createdAt: n.createdAt,
                    updatedAt: n.updatedAt
                ))
            }
        }

        let env = BackupAnnotationsEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion,
            highlights: highlights,
            bookmarks: bookmarks,
            notes: notes
        )
        return try encode(env)
    }

    func collectPositions() async throws -> Data {
        let books = try await persistence.fetchAllLibraryBooks()
        var positions: [BackupPosition] = []
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        for book in books {
            let key = book.fingerprintKey
            guard let loc = try? await persistence.loadPosition(bookFingerprintKey: key) else {
                continue
            }
            guard let locJSON = locatorJSON(loc, encoder: encoder) else { continue }
            positions.append(BackupPosition(
                bookFingerprintKey: key,
                locatorJSON: locJSON,
                updatedAt: book.lastOpenedAt ?? book.addedAt,
                lastOpenedAt: book.lastOpenedAt
            ))
        }

        let env = BackupPositionsEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion, positions: positions
        )
        return try encode(env)
    }

    func collectSettings() async throws -> Data {
        var dict: [String: BackupDefaultsValue] = [:]
        for key in BackupSettingsKeys.all {
            guard let raw = defaults.object(forKey: key) else { continue }
            if let v = raw as? Bool, CFGetTypeID(raw as CFTypeRef) == CFBooleanGetTypeID() {
                dict[key] = .bool(v)
            } else if let v = raw as? Int {
                dict[key] = .int(v)
            } else if let v = raw as? Double {
                dict[key] = .double(v)
            } else if let v = raw as? String {
                dict[key] = .string(v)
            } else if let v = raw as? Data {
                dict[key] = .data(v)
            }
        }
        let env = BackupSettingsEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion, defaults: dict
        )
        return try encode(env)
    }

    func collectCollections() async throws -> Data {
        let collections = try await persistence.fetchAllCollections()
        var out: [BackupCollection] = []
        for c in collections {
            let keys = (try? await persistence.fetchBooksInCollection(name: c.name)) ?? []
            out.append(BackupCollection(
                name: c.name,
                createdAt: c.createdAt,
                bookFingerprintKeys: keys
            ))
        }
        let env = BackupCollectionsEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion, collections: out
        )
        return try encode(env)
    }

    func collectBookSources() async throws -> Data {
        let sources = await persistence.fetchAllBackupBookSources()
        let env = BackupBookSourcesEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion, sources: sources
        )
        return try encode(env)
    }

    func collectPerBookSettings() async throws -> Data {
        let books = try await persistence.fetchAllLibraryBooks()
        var entries: [BackupPerBookSettingsEntry] = []
        for book in books {
            guard let override = PerBookSettingsStore.settings(
                for: book.fingerprintKey,
                baseURL: perBookSettingsBaseURL
            ) else { continue }
            entries.append(BackupPerBookSettingsEntry(
                bookFingerprintKey: book.fingerprintKey,
                override: override
            ))
        }
        let env = BackupPerBookSettingsEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion, entries: entries
        )
        return try encode(env)
    }

    func collectReplacementRules() async throws -> Data {
        let rules = await persistence.fetchAllBackupReplacementRules()
        let env = BackupReplacementRulesEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion, rules: rules
        )
        return try encode(env)
    }

    func getBookCount() async -> Int {
        ((try? await persistence.fetchAllLibraryBooks()) ?? []).count
    }

    func collectLibraryManifest() async throws -> Data {
        let projections = (try? await persistence.fetchAllBooksForBackup()) ?? []
        let entries: [BackupLibraryEntry] = projections.compactMap { projection in
            guard let format = BookFormat(rawValue: projection.format) else {
                log.error("Skipping projection with unknown format \(projection.format, privacy: .public)")
                return nil
            }
            return BackupLibraryEntry(
                fingerprintKey: projection.fingerprintKey,
                format: projection.format,
                sha256: projection.sha256,
                byteCount: projection.byteCount,
                originalExtension: projection.originalExtension,
                title: projection.title,
                author: projection.author,
                addedAt: projection.addedAt,
                lastOpenedAt: projection.lastOpenedAt,
                blobPath: BlobPath.make(
                    format: format,
                    sha256: projection.sha256,
                    byteCount: projection.byteCount
                ),
                sourceCanonicalKey: projection.sourceCanonicalKey
            )
        }
        let envelope = BackupLibraryManifestEnvelope(schemaVersion: 1, books: entries)
        return try encode(envelope)
    }

    /// Feature #58 WI-5: emits `reading-history.json` carrying every
    /// `ReadingSession` and every `ReadingStats` row, so a restore reproduces
    /// reading history exactly. New in backup schema v2.
    ///
    /// The persistence fetches are NOT `try?`-swallowed: criterion (f) demands
    /// an exact round-trip, so a read failure must fail the backup loudly
    /// rather than silently emitting an empty section (which would discard the
    /// user's entire reading history on the next restore).
    func collectReadingHistory() async throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let sessionRecords = try await persistence.fetchAllReadingSessions()
        let sessions: [BackupReadingSession] = sessionRecords.map { record in
            BackupReadingSession(
                sessionId: record.sessionId,
                bookFingerprintKey: record.bookFingerprintKey,
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                durationSeconds: record.durationSeconds,
                pagesRead: record.pagesRead,
                wordsRead: record.wordsRead,
                startLocatorJSON: record.startLocator.flatMap { locatorJSON($0, encoder: encoder) },
                endLocatorJSON: record.endLocator.flatMap { locatorJSON($0, encoder: encoder) },
                deviceId: record.deviceId,
                isRecovered: record.isRecovered
            )
        }

        let statsRecords = try await persistence.fetchAllReadingStats()
        let stats: [BackupReadingStats] = statsRecords.map { record in
            BackupReadingStats(
                bookFingerprintKey: record.bookFingerprintKey,
                totalReadingSeconds: record.totalReadingSeconds,
                sessionCount: record.sessionCount,
                lastReadAt: record.lastReadAt,
                averagePagesPerHour: record.averagePagesPerHour,
                averageWordsPerMinute: record.averageWordsPerMinute,
                totalPagesRead: record.totalPagesRead,
                totalWordsRead: record.totalWordsRead,
                longestSessionSeconds: record.longestSessionSeconds
            )
        }

        let envelope = BackupReadingHistoryEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion, sessions: sessions, stats: stats
        )
        return try encode(envelope)
    }

    /// Feature #89: emits `ai-conversations.json` carrying every persisted
    /// `ChatSession` (with its raw message blob), so a restore reproduces AI
    /// conversation history exactly. New in backup schema v3.
    ///
    /// The persistence fetch is NOT `try?`-swallowed: a read failure must fail
    /// the backup loudly rather than silently emitting an empty section (which
    /// would discard the user's AI history on the next restore).
    func collectAIConversations() async throws -> Data {
        let sessions = try await persistence.fetchAllChatSessionsForBackup()
        let envelope = BackupAIConversationsEnvelope(
            schemaVersion: kBackupCurrentSchemaVersion, sessions: sessions
        )
        return try encode(envelope)
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }

    private func locatorJSON(_ locator: Locator, encoder: JSONEncoder) -> String? {
        guard let data = try? encoder.encode(locator) else {
            log.error("Failed to encode locator for backup")
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
