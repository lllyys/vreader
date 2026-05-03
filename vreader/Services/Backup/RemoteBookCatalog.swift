// Purpose: Decodes a backup ZIP's `library-manifest.json` into the
// `[BackupLibraryEntry]` rows the selective-restore picker (#47 WI-6)
// shows the user, and that the lazy-download enqueue path (#47 WI-4b)
// later consults to construct download URLs / record blobPath +
// expectedSHA256 onto the inserted `.remoteOnly` rows.
//
// Single responsibility: extract + decode. Network I/O (downloading the
// ZIP from WebDAV) lives in the caller — typically `WebDAVProvider`'s
// existing fetch path so the catalog reuses the same auth + retry
// surface as the restore-all flow.
//
// Feature #47 WI-4a.
//
// @coordinates-with: BackupSectionDTOs.swift (BackupLibraryEntry,
//   BackupLibraryManifestEnvelope), ZIPWriter.swift (extractEntry),
//   SelectiveRestoreCoordinator.swift (future, WI-4b consumer),
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import Foundation
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "RemoteBookCatalog")

enum RemoteBookCatalogError: Error, Sendable, Equatable {
    /// The backup ZIP does not contain a `library-manifest.json` entry.
    /// Older (pre-#46) backups fall in this bucket and surface as a
    /// "this backup has no recoverable book files" message in the UI.
    case manifestMissing
    /// The manifest entry exists but failed JSON decoding (corrupt
    /// envelope, unknown schemaVersion, missing required fields).
    case manifestUndecodable(reason: String)
    /// The manifest decoded but its declared `schemaVersion` is newer
    /// than this client supports.
    case manifestSchemaVersionTooNew(saw: Int, supported: Int)

    static func == (lhs: RemoteBookCatalogError, rhs: RemoteBookCatalogError) -> Bool {
        switch (lhs, rhs) {
        case (.manifestMissing, .manifestMissing): return true
        case let (.manifestUndecodable(a), .manifestUndecodable(b)): return a == b
        case let (.manifestSchemaVersionTooNew(la, lb), .manifestSchemaVersionTooNew(ra, rb)):
            return la == ra && lb == rb
        default: return false
        }
    }
}

/// Pure decoding utility — no I/O, no actor. Tests pass in canned ZIP
/// bytes built with `ZIPWriter.createArchive`; production callers fetch
/// the ZIP via the existing transport then hand the bytes here.
enum RemoteBookCatalog {

    /// Maximum schema version this client understands. Bumped together
    /// with `BackupLibraryManifestEnvelope.schemaVersion` whenever the
    /// shape changes incompatibly.
    static let supportedSchemaVersion = 1

    /// Filename inside the backup ZIP that carries the library
    /// manifest. Mirrored from `WebDAVProvider`'s emit path.
    static let manifestFilename = "library-manifest.json"

    /// Decodes the library manifest from a backup ZIP. Returns the
    /// list of book entries the user can selectively restore.
    /// - Throws `RemoteBookCatalogError` for missing / undecodable /
    ///   future-schema manifests; never returns nil + empty.
    static func loadEntries(fromBackupZIP zipData: Data) throws -> [BackupLibraryEntry] {
        let manifestData: Data
        do {
            manifestData = try ZIPWriter.extractEntry(named: manifestFilename, from: zipData)
        } catch {
            log.info("library-manifest.json missing — older backup, no books to restore")
            throw RemoteBookCatalogError.manifestMissing
        }

        let envelope: BackupLibraryManifestEnvelope
        do {
            envelope = try JSONDecoder().decode(
                BackupLibraryManifestEnvelope.self, from: manifestData
            )
        } catch {
            throw RemoteBookCatalogError.manifestUndecodable(reason: "\(error)")
        }

        guard envelope.schemaVersion <= supportedSchemaVersion else {
            throw RemoteBookCatalogError.manifestSchemaVersionTooNew(
                saw: envelope.schemaVersion,
                supported: supportedSchemaVersion
            )
        }

        return envelope.books
    }
}
