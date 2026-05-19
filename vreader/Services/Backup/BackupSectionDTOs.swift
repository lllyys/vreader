// Purpose: Codable value types describing each section of a WebDAV backup ZIP.
// Versioned envelopes with `schemaVersion` so future archives can branch on
// older formats without breaking restore.
//
// @coordinates-with: BackupDataCollector.swift, BackupDataRestorer.swift,
//   PersistenceActor+Backup.swift

import Foundation

/// All section JSONs share a `schemaVersion` field so future revs can branch on it.
/// Currently only v1 is emitted.
let kBackupCurrentSchemaVersion = 1

/// Common shape every section envelope honors so the restorer can validate
/// `schemaVersion` without 7 special cases.
protocol BackupVersionedEnvelope {
    var schemaVersion: Int { get }
}

/// Errors thrown by the backup restore path.
enum BackupRestoreError: Error, Sendable, Equatable {
    /// Archive section was produced by a newer schema this client doesn't know about.
    case unsupportedSchemaVersion(section: String, actual: Int, supported: Int)
    /// One or more per-entry restores failed but others succeeded.
    case partialFailure(section: String, failed: Int, total: Int)
}

// MARK: - Annotations

/// Annotations section: highlights / bookmarks / notes flattened across all books.
struct BackupAnnotationsEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let highlights: [BackupHighlight]
    let bookmarks: [BackupBookmark]
    let notes: [BackupNote]
}

struct BackupHighlight: Codable, Sendable, Equatable {
    let highlightId: UUID
    let bookFingerprintKey: String
    let locatorJSON: String
    let selectedText: String
    let color: String
    let note: String?
    let createdAt: Date
    let updatedAt: Date
}

struct BackupBookmark: Codable, Sendable, Equatable {
    let bookmarkId: UUID
    let bookFingerprintKey: String
    let locatorJSON: String
    let title: String?
    let createdAt: Date
    let updatedAt: Date
}

struct BackupNote: Codable, Sendable, Equatable {
    let annotationId: UUID
    let bookFingerprintKey: String
    let locatorJSON: String
    let content: String
    let createdAt: Date
    let updatedAt: Date
}

// MARK: - Positions

/// Reading positions per book.
struct BackupPositionsEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let positions: [BackupPosition]
}

struct BackupPosition: Codable, Sendable, Equatable {
    let bookFingerprintKey: String
    let locatorJSON: String
    let updatedAt: Date
    let lastOpenedAt: Date?
}

// MARK: - Settings

/// Global app settings (UserDefaults snapshot for reader-related keys).
struct BackupSettingsEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let defaults: [String: BackupDefaultsValue]
}

/// Type-tagged UserDefaults value so we can faithfully round-trip mixed types.
enum BackupDefaultsValue: Codable, Sendable, Equatable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case data(Data)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Tag: String, Codable { case bool, int, double, string, data }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .bool(let v): try c.encode(Tag.bool, forKey: .type); try c.encode(v, forKey: .value)
        case .int(let v): try c.encode(Tag.int, forKey: .type); try c.encode(v, forKey: .value)
        case .double(let v): try c.encode(Tag.double, forKey: .type); try c.encode(v, forKey: .value)
        case .string(let v): try c.encode(Tag.string, forKey: .type); try c.encode(v, forKey: .value)
        case .data(let v): try c.encode(Tag.data, forKey: .type); try c.encode(v, forKey: .value)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tag = try c.decode(Tag.self, forKey: .type)
        switch tag {
        case .bool: self = .bool(try c.decode(Bool.self, forKey: .value))
        case .int: self = .int(try c.decode(Int.self, forKey: .value))
        case .double: self = .double(try c.decode(Double.self, forKey: .value))
        case .string: self = .string(try c.decode(String.self, forKey: .value))
        case .data: self = .data(try c.decode(Data.self, forKey: .value))
        }
    }
}

/// Reader-related UserDefaults keys covered by backup. Hard-coded (not derived
/// from `ReaderSettingsStore.*Key`) because the store is `@MainActor`-isolated
/// and these constants need to be reachable from non-isolated contexts.
enum BackupSettingsKeys {
    static let all: [String] = [
        "readerTheme",
        "readerTypography",
        "readerUseCustomBackground",
        "readerBackgroundOpacity",
        "readerEPUBLayout",
        "readerAutoPageTurn",
        "readerAutoPageTurnInterval",
        "readerPageTurnAnimation",
        "readerChineseConversion",
    ]
}

// MARK: - Collections

struct BackupCollectionsEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let collections: [BackupCollection]
}

struct BackupCollection: Codable, Sendable, Equatable {
    let name: String
    let createdAt: Date
    let bookFingerprintKeys: [String]
}

// MARK: - Book Sources

struct BackupBookSourcesEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let sources: [BackupBookSource]
}

struct BackupBookSource: Codable, Sendable, Equatable {
    let sourceURL: String
    let sourceName: String
    let sourceGroup: String?
    let sourceType: Int
    let enabled: Bool
    let searchURL: String?
    let header: String?
    let ruleSearchData: Data?
    let ruleBookInfoData: Data?
    let ruleTocData: Data?
    let ruleContentData: Data?
    let compatibilityLevel: String?
    let lastUpdateTime: Date?
    let customOrder: Int
}

// MARK: - Per-Book Settings

struct BackupPerBookSettingsEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let entries: [BackupPerBookSettingsEntry]
}

struct BackupPerBookSettingsEntry: Codable, Sendable, Equatable {
    let bookFingerprintKey: String
    let override: PerBookSettingsOverride
}

// MARK: - Replacement Rules

struct BackupReplacementRulesEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let rules: [BackupReplacementRule]
}

struct BackupReplacementRule: Codable, Sendable, Equatable {
    let ruleId: UUID
    let pattern: String
    let replacement: String
    let isRegex: Bool
    let scopeKey: String
    let enabled: Bool
    let order: Int
    let label: String
    let createdAt: Date
}

// MARK: - Library Manifest (feature #46 WI-2)

/// Library manifest section emitted as `library-manifest.json` inside the
/// backup ZIP starting with feature #46. Backward-compatible: old (v1-format)
/// backups without this section restore exactly as before — metadata-only,
/// no book materialization. New backups carry one entry per local book so the
/// restorer can download missing blobs and reconstruct the library on a
/// fresh device.
struct BackupLibraryManifestEnvelope: Codable, Sendable, Equatable, BackupVersionedEnvelope {
    let schemaVersion: Int
    let books: [BackupLibraryEntry]
}

/// Per-book entry in the library manifest. Carries the canonical fingerprint
/// fields plus the blob path on the WebDAV server so the materializer doesn't
/// need to recompute it from format + sha256 + byteCount on every entry.
///
/// `originalExtension` is non-optional here (the projection coalesces nil to
/// the canonical extension before emission, see `BackupBookProjection` /
/// `PersistenceActor.fetchAllBooksForBackup`).
struct BackupLibraryEntry: Codable, Sendable, Equatable {
    /// Canonical `{format}:{sha256}:{byteCount}` — primary key for re-attaching
    /// positions/annotations after restore.
    let fingerprintKey: String

    /// Canonical `BookFormat.rawValue` — `"epub"`, `"azw3"`, `"txt"`, `"md"`, `"pdf"`.
    let format: String

    /// Hex SHA-256 of the original file bytes.
    let sha256: String

    /// Original file byte count.
    let byteCount: Int64

    /// Original source extension at import time, e.g. `"mobi"` for AZW3-canonical
    /// books that were imported as `.mobi`. Used by the materializer to write
    /// the downloaded blob to a temp file with the user's original extension.
    let originalExtension: String

    /// Display-only title and author. The materializer re-extracts these from
    /// the imported file via `MetadataExtractor`; they're carried in the manifest
    /// so future selective-restore UI (feature #47) can show them before
    /// downloading the blob.
    let title: String?
    let author: String?

    /// When the user added the book to their library.
    let addedAt: Date

    /// When the book was last opened, if ever. Restored alongside the position
    /// so the restored library shows the right "Last Read" sort order.
    let lastOpenedAt: Date?

    /// Content-addressed WebDAV path to the blob, e.g.
    /// `"VReader/books/azw3/<sha256>_<byteCount>.azw3"`. Always agrees with
    /// `BlobPath.make(format:sha256:byteCount:)`.
    let blobPath: String
}
