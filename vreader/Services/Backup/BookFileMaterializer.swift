// Purpose: Downloads + verifies + imports book blobs from a backup manifest
// for feature #46's WebDAV materializing restore. Single responsibility:
// given [BackupLibraryEntry], make sure each blob is locally present (either
// already-imported or freshly downloaded + imported via BookImporter).
//
// Design (per audited plan dev-docs/plans/20260503-feature-46-...):
// - Serial over entries, monotonic progress callback, no parallelism by
//   default — avoids saturating WebDAV and EPUB pre-extraction churn.
// - Triple verification on download: byte count → SHA-256 → final
//   ImportResult.fingerprintKey vs manifest.fingerprintKey. The byte-count
//   check is cheap; SHA-256 catches in-flight corruption; the
//   import-fingerprint check catches extension/format confusion.
// - Preflight rehash on existing local files. BookImporter.atomicCopyToSandbox
//   trusts an existing final file without verifying its bytes; if a prior
//   crashed import left corrupt content there, the materializer re-downloads
//   rather than silently registering a row pointing at bad bytes.
//
// @coordinates-with: BackupBlobStore.swift, BookImporting (BookImporter),
//   BackupLibraryEntry (BackupSectionDTOs.swift),
//   dev-docs/plans/20260503-feature-46-materializing-restore.md

import CryptoKit
import Foundation
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "BookFileMaterializer")

/// Per-entry outcome from `materialize`. Caller (WebDAVProvider.restore)
/// aggregates these into a `BackupError.materializePartiallyFailed` if any
/// downloads/imports failed; happy-path entries proceed to metadata restore.
struct MaterializeResult: Sendable {
    let entry: BackupLibraryEntry
    let outcome: Outcome

    enum Outcome: Sendable, Equatable {
        case alreadyLocal                                     // hash verified
        case downloaded(fingerprintKey: String)
        case downloadFailed(BackupBlobStoreError)
        case sizeAfterDownloadMismatch(expected: Int64, actual: Int64)
        case sha256Mismatch(expected: String, actual: String)
        case importFailed(String)                              // ImportError stringified
        case fingerprintMismatchAfterImport(expected: String, actual: String)
    }

    /// True for `.alreadyLocal` and `.downloaded`. False otherwise.
    var isSuccess: Bool {
        switch outcome {
        case .alreadyLocal, .downloaded: return true
        default: return false
        }
    }
}

/// Resolves the local sandbox URL for a fingerprint key — mirrors
/// `LibraryBookItem.resolvedFileURL`'s convention (colons → underscores)
/// without depending on a SwiftData entity. Injected so tests can use a
/// throw-away temp directory.
typealias SandboxURLResolver = @Sendable (_ fingerprintKey: String, _ originalExtension: String) -> URL

final class BookFileMaterializer: Sendable {

    private let blobStore: any BackupBlobReading
    private let importer: any BookImporting
    private let finalizer: BookFileImportFinalizer
    private let resolveSandboxURL: SandboxURLResolver
    private let tempDirectory: URL

    init(
        blobStore: any BackupBlobReading,
        importer: any BookImporting,
        tempDirectory: URL,
        resolveSandboxURL: @escaping SandboxURLResolver = BookFileMaterializer.defaultSandboxResolver
    ) {
        self.blobStore = blobStore
        self.importer = importer
        self.finalizer = BookFileImportFinalizer(importer: importer)
        self.tempDirectory = tempDirectory
        self.resolveSandboxURL = resolveSandboxURL
    }

    // MARK: - Default resolver

    /// Mirrors `LibraryBookItem.resolvedFileURL`: Application Support /
    /// ImportedBooks / `<fingerprintKey-with-colons-as-underscores>.<ext>`.
    static let defaultSandboxResolver: SandboxURLResolver = { fingerprintKey, originalExtension in
        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        let safeName = fingerprintKey.replacingOccurrences(of: ":", with: "_")
        return booksDir
            .appendingPathComponent(safeName)
            .appendingPathExtension(originalExtension)
    }

    // MARK: - Classify

    /// Splits entries into (alreadyLocal, needsDownload). For an entry whose
    /// resolved sandbox URL exists locally, hashes the file and verifies
    /// SHA-256 against the manifest — mismatch counts as needsDownload.
    func classify(
        _ entries: [BackupLibraryEntry]
    ) async -> (alreadyLocal: [BackupLibraryEntry], needsDownload: [BackupLibraryEntry]) {
        var alreadyLocal: [BackupLibraryEntry] = []
        var needsDownload: [BackupLibraryEntry] = []
        for entry in entries {
            let localURL = resolveSandboxURL(entry.fingerprintKey, entry.originalExtension)
            if FileManager.default.fileExists(atPath: localURL.path),
               let localHash = try? localFileSHA256(at: localURL),
               localHash == entry.sha256 {
                alreadyLocal.append(entry)
            } else {
                needsDownload.append(entry)
            }
        }
        return (alreadyLocal, needsDownload)
    }

    // MARK: - Materialize

    /// Downloads + verifies + imports each entry serially. Reports progress
    /// 0...1 across the batch.
    func materialize(
        _ entries: [BackupLibraryEntry],
        progress: @Sendable (Double) -> Void
    ) async -> [MaterializeResult] {
        var results: [MaterializeResult] = []
        results.reserveCapacity(entries.count)
        progress(0.0)
        guard !entries.isEmpty else {
            progress(1.0)
            return results
        }
        for (index, entry) in entries.enumerated() {
            let result = await materializeOne(entry)
            results.append(result)
            progress(Double(index + 1) / Double(entries.count))
        }
        return results
    }

    // MARK: - Per-entry algorithm

    private func materializeOne(_ entry: BackupLibraryEntry) async -> MaterializeResult {
        let localURL = resolveSandboxURL(entry.fingerprintKey, entry.originalExtension)

        // Step 1: existing local file → preflight hash + ensure SwiftData
        // row exists for it. Bug #114: previously this short-circuited
        // to `.alreadyLocal` whenever the file's SHA matched, but if the
        // user had deleted the row earlier (which leaves the sandbox
        // file behind today), the row never came back and the book
        // stayed invisible in the library. Now we still skip the
        // download (the bytes are good) but route through BookImporter
        // so the row gets re-inserted on dedupe-miss. BookImporter's
        // step 7 fast-paths the dedupe-hit case by replacing provenance.
        if FileManager.default.fileExists(atPath: localURL.path) {
            if let localHash = try? localFileSHA256(at: localURL), localHash == entry.sha256 {
                return await reimportLocalFile(entry: entry, at: localURL)
            }
            // Corrupt local file (wrong bytes for the fingerprint). Remove
            // before download — BookImporter would otherwise trust the
            // existing file at the final path without rehashing.
            try? FileManager.default.removeItem(at: localURL)
        }

        // Step 2: download.
        let bytes: Data
        do {
            bytes = try await blobStore.download(from: entry.blobPath)
        } catch let error as BackupBlobStoreError {
            return MaterializeResult(entry: entry, outcome: .downloadFailed(error))
        } catch {
            return MaterializeResult(
                entry: entry,
                outcome: .downloadFailed(.underlying("\(error)"))
            )
        }

        // Step 3: byte-count check (cheap, catches truncation).
        if Int64(bytes.count) != entry.byteCount {
            return MaterializeResult(
                entry: entry,
                outcome: .sizeAfterDownloadMismatch(expected: entry.byteCount, actual: Int64(bytes.count))
            )
        }

        // Step 4: write to a temp file with originalExtension so BookImporter
        // can derive format from the extension. Path includes the SHA-256 to
        // stay unique across concurrent restores.
        let tempURL: URL
        do {
            try FileManager.default.createDirectory(
                at: tempDirectory, withIntermediateDirectories: true
            )
            tempURL = tempDirectory
                .appendingPathComponent("restore_\(entry.sha256)")
                .appendingPathExtension(entry.originalExtension)
            try bytes.write(to: tempURL)
        } catch {
            return MaterializeResult(
                entry: entry,
                outcome: .importFailed("temp write failed: \(error)")
            )
        }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        // Steps 5-7 (SHA verify + import + fingerprint match) are shared
        // with the lazy-download path (#47 WI-4b) and live in the
        // finalizer. The finalizer re-hashes the file rather than
        // trusting an in-memory hash so both paths share identical
        // verification semantics.
        return await finalizer.finalize(localTempURL: tempURL, entry: entry)
    }

    /// Bug #114: when the canonical sandbox file is already present and
    /// SHA-matches, route through BookImporter so the SwiftData row gets
    /// reinserted if the user previously deleted it (the historical
    /// deleteBook path leaves the file behind). Importer's step 7
    /// fast-paths the dedupe-hit case to a `replaceProvenance` call,
    /// so the row+file consistent case stays cheap. We map the result
    /// back to `.alreadyLocal` because no new bytes transferred — the
    /// caller's "imported / already had it" accounting still reads
    /// correctly.
    ///
    /// Bug #247: pass `entry.title` as the importer's titleOverride so a
    /// dedupe-hit (existing row) or new insert here surfaces the manifest
    /// title rather than the canonical sandbox filename
    /// (`<sha>_<bytes>.<ext>`). For filename-derived-title formats
    /// (TXT, MD, PDF with empty Title metadata) the manifest title is
    /// the only place the original book name survives the round-trip.
    private func reimportLocalFile(
        entry: BackupLibraryEntry,
        at localURL: URL
    ) async -> MaterializeResult {
        let importResult: ImportResult
        do {
            importResult = try await importer.importFile(
                at: localURL,
                source: .restore,
                titleOverride: entry.title
            )
        } catch let error as ImportError {
            return MaterializeResult(entry: entry, outcome: .importFailed("\(error)"))
        } catch {
            return MaterializeResult(entry: entry, outcome: .importFailed("\(error)"))
        }
        // Defensive: make sure the importer's computed fingerprintKey
        // agrees with the manifest. A mismatch would mean the file at
        // the canonical path doesn't actually carry the bytes the
        // entry claims — preflight hash above should have caught it,
        // but a final check is cheap.
        guard importResult.fingerprintKey == entry.fingerprintKey else {
            return MaterializeResult(
                entry: entry,
                outcome: .fingerprintMismatchAfterImport(
                    expected: entry.fingerprintKey,
                    actual: importResult.fingerprintKey
                )
            )
        }
        return MaterializeResult(entry: entry, outcome: .alreadyLocal)
    }

    // MARK: - Hashing helpers

    /// Streaming SHA-256 of a local file (chunked so very-large blobs don't
    /// spike memory). Returns lowercase hex matching `entry.sha256` format.
    private func localFileSHA256(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        let chunkSize = 64 * 1024
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hexString(Data(hasher.finalize()))
    }

    private func hexString(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
