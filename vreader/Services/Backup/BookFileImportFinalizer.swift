// Purpose: Shared verify + import + fingerprint-check pipeline that
// both `BookFileMaterializer` (restore-all path, in-memory `Data`) and
// the lazy-download coordinator (#47 WI-4b enqueue path, file-URL via
// background URLSession) call once their bytes have landed on disk.
//
// Extracted from `BookFileMaterializer.materializeOne` (steps 4 + 6 + 7).
// The materializer keeps the download / byte-count / temp-write steps;
// the finalizer takes a localTempURL that already carries the right
// originalExtension and runs:
//   - Streaming SHA-256 verify against `entry.sha256`
//   - `BookImporter.importFile(at:source:)` with `.restore`
//   - Resulting `fingerprintKey` vs `entry.fingerprintKey` match
//
// Caller owns localTempURL lifetime (cleanup after finalize returns).
//
// Feature #47 WI-4a.
//
// @coordinates-with: BookFileMaterializer.swift,
//   BookImporting.swift, BackupSectionDTOs.swift,
//   LazyDownloadCoordinator.swift (future, WI-4b consumer),
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import CryptoKit
import Foundation
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "BookFileImportFinalizer")

struct BookFileImportFinalizer: Sendable {

    private let importer: any BookImporting

    init(importer: any BookImporting) {
        self.importer = importer
    }

    /// Finalizes a downloaded blob: verify SHA-256, import via
    /// `BookImporter`, verify the resulting fingerprint matches the
    /// manifest entry. Caller must:
    ///   - Ensure `localTempURL` carries the bytes claimed by `entry`.
    ///   - Have written the file with the correct `originalExtension`
    ///     so `BookImporter` can derive format from the path.
    ///   - Clean up `localTempURL` after this returns (success or fail).
    func finalize(localTempURL: URL, entry: BackupLibraryEntry) async -> MaterializeResult {
        // SHA-256 verify on the file. Streaming so very-large blobs
        // don't spike memory in the lazy-download path.
        let downloadedHash: String
        do {
            downloadedHash = try Self.localFileSHA256(at: localTempURL)
        } catch {
            return MaterializeResult(
                entry: entry,
                outcome: .importFailed("sha256-read-failed: \(error)")
            )
        }
        if downloadedHash != entry.sha256 {
            return MaterializeResult(
                entry: entry,
                outcome: .sha256Mismatch(expected: entry.sha256, actual: downloadedHash)
            )
        }

        // Import via the production importer (re-extracts metadata,
        // saves cover, fires indexing notification, applies dedupe).
        let importResult: ImportResult
        do {
            importResult = try await importer.importFile(at: localTempURL, source: .restore)
        } catch let importErr as ImportError {
            return MaterializeResult(entry: entry, outcome: .importFailed("\(importErr)"))
        } catch {
            return MaterializeResult(entry: entry, outcome: .importFailed("\(error)"))
        }

        // Verify fingerprint match — catches extension/format confusion
        // (e.g. AZW3 bytes labelled .epub) where BookImporter would
        // compute a different fingerprintKey from the bytes than what
        // the manifest claimed.
        guard importResult.fingerprintKey == entry.fingerprintKey else {
            return MaterializeResult(
                entry: entry,
                outcome: .fingerprintMismatchAfterImport(
                    expected: entry.fingerprintKey,
                    actual: importResult.fingerprintKey
                )
            )
        }

        return MaterializeResult(
            entry: entry,
            outcome: .downloaded(fingerprintKey: importResult.fingerprintKey)
        )
    }

    // MARK: - Hashing

    /// Streaming SHA-256 of a local file. Returns lowercase hex.
    /// Static so `BookFileMaterializer` can reuse it post-extraction
    /// for its preflight rehash without depending on a finalizer
    /// instance.
    static func localFileSHA256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 64 * 1024
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return Self.hexString(Data(hasher.finalize()))
    }

    private static func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
