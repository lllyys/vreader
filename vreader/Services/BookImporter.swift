// Purpose: Main import orchestrator. Receives a file URL, validates format,
// computes identity hash, checks for duplicates, copies to sandbox, extracts
// metadata, persists the Book record, and emits an indexing trigger.
//
// Key decisions:
// - Security-scoped URL access is wrapped with guaranteed cleanup (defer).
// - Atomic copy: write to temp file first, then rename into final location.
// - TXT and MD files run through EncodingDetector for binary masquerade + encoding.
// - Duplicate detection happens after hashing, before copy.
// - Indexing trigger is a Notification; the indexer is a separate concern.
//
// @coordinates-with: PersistenceActor.swift, ContentHasher.swift,
//   EncodingDetector.swift, MetadataExtractor.swift, ImportError.swift,
//   CustomCoverStore.swift

import Foundation
import OSLog

extension Notification.Name {
    /// Posted by `BookImporter` after a successful import — both new-row and
    /// duplicate-replace paths. `userInfo` carries `["fingerprintKey": String]`.
    /// Library views observe this to refresh without polling.
    ///
    /// Bug #197: incoming-URL imports via FileURLImportRouter (Feature #59)
    /// inserted the row but the library view (which uses an imperative
    /// `loadBooks()` array, not a reactive `@Query`) never observed the
    /// change. Posting this from the importer gives every import path —
    /// in-app Files-picker, Share Sheet, future flows — a free refresh
    /// signal without coupling the router to the view layer.
    static let bookDidImport = Notification.Name("vreader.import.bookDidImport")
}

/// Result of a successful import operation.
struct ImportResult: Sendable, Equatable {
    let fingerprintKey: String
    let title: String
    let author: String?
    let fingerprint: DocumentFingerprint
    let provenance: ImportProvenance
    let detectedEncoding: String?
    let isDuplicate: Bool
}

/// Orchestrates the book import pipeline.
final class BookImporter: BookImporting, Sendable {

    // Bug #139: `indexingNeededNotification` removed — was forward-looking
    // dead code. The header comment claimed "the indexer is a separate
    // concern" listening on the notification, but the indexer landed
    // differently: `ReaderSearchCoordinator.indexBookContent` runs lazily
    // when the user opens the search panel. Nothing in production observed
    // the notification.

    private let persistence: any BookPersisting
    private let sandboxBooksDirectory: URL

    /// Metadata extractors by format.
    private let extractors: [BookFormat: any MetadataExtractor]

    /// Feature flags — gates Kindle convert-on-import (#42 Phase 2 WI-4b).
    private let featureFlags: FeatureFlags

    private static let log = Logger(subsystem: "com.vreader.app", category: "BookImporter")

    init(
        persistence: any BookPersisting,
        sandboxBooksDirectory: URL,
        extractors: [BookFormat: any MetadataExtractor]? = nil,
        featureFlags: FeatureFlags = .shared
    ) {
        self.persistence = persistence
        self.sandboxBooksDirectory = sandboxBooksDirectory
        self.featureFlags = featureFlags
        self.extractors = extractors ?? [
            .txt: TXTMetadataExtractor(),
            .epub: EPUBMetadataExtractor(),
            .pdf: PDFMetadataExtractor(),
            .md: MDMetadataExtractor(),
            .azw3: AZW3MetadataExtractor(),
        ]
    }

    /// Imports a file into the library.
    ///
    /// - Parameters:
    ///   - fileURL: URL to the file to import. May be a security-scoped resource.
    ///   - source: How the file was provided (Files app, share sheet, etc.).
    ///   - titleOverride: Optional title that wins over the extractor's
    ///     filename-derived title. Whitespace-trimmed before use; empty
    ///     or whitespace-only strings are treated as nil (no override).
    ///     Bug #247: WebDAV restore path uses this to surface
    ///     `BackupLibraryEntry.title` from the manifest so restored
    ///     TXT/MD/PDF books keep their original names.
    /// - Returns: The import result with book identity and metadata.
    /// - Throws: `ImportError` for all failure modes.
    func importFile(
        at fileURL: URL,
        source: ImportSource,
        titleOverride: String? = nil
    ) async throws -> ImportResult {
        // Normalize the override once at the entry point so the same
        // value reaches both the insert (new-row) and updateBookTitle
        // (dedupe-hit) paths AND the returned `ImportResult.title`.
        // Three rules, in order:
        //   1. trim leading/trailing whitespace + newlines
        //   2. empty (after trim) → nil (no override)
        //   3. cap at 255 characters — matches `Book.init`'s defense-in-
        //      depth truncation and `MetadataExtractor.maxTitleLength`.
        //      Without this, an oversized manifest title would persist
        //      truncated on insert but un-truncated on dedupe-update,
        //      AND `ImportResult.title` would diverge from the DB row
        //      on the new-row path.
        let trimmedOverride: String? = {
            guard let raw = titleOverride else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(255))
        }()
        // Step 0: Reject non-file and directory URLs
        guard fileURL.isFileURL else {
            throw ImportError.fileNotReadable("Not a file URL")
        }
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
            throw ImportError.fileNotReadable("Cannot import a directory")
        }

        // Step 1: Validate format
        let format = try resolveFormat(fileURL: fileURL)

        // Step 2: Access security-scoped resource
        let accessGranted = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        // Step 3: Verify file is readable (security scope failure may cause this)
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            if !accessGranted {
                throw ImportError.securityScopeAccessDenied
            }
            throw ImportError.fileNotReadable("File does not exist or is not readable")
        }

        // Step 3.5 (Feature #42 Phase 2 WI-4b): Kindle convert-on-import (gated,
        // default OFF). When ON and the file is a Kindle format, convert it to a
        // self-describing EPUB and run the ENTIRE rest of the pipeline over the
        // converted file — so identity/fingerprint/blob/metadata are all the
        // EPUB's (a first-class EPUB; design decisions #1/#2). The source's own
        // title/author/cover are baked into the EPUB (WI-4a), so the downstream
        // EPUBMetadataExtractor recovers correct display metadata from the blob.
        var workingURL = fileURL
        var workingFormat = format
        var convertedTempURL: URL? = nil
        var kindleOriginExtension: String? = nil
        defer {
            // The converted EPUB is a temp file; it's copied into the sandbox by
            // Step 8, so clean up the temp on every exit path.
            if let temp = convertedTempURL { try? FileManager.default.removeItem(at: temp) }
        }
        if featureFlags.isEnabled(.kindleConvertOnImport), format.isKindleConvertible {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                let sourcePath = fileURL.path
                // Off-main: libmobi decode + EPUB packaging is CPU-bound (design
                // decision #6 — never block the @MainActor importer entry).
                let converted = try await Task.detached(priority: .userInitiated) {
                    try MobiEPUBConverter.convertToFile(mobiPath: sourcePath, destinationDir: tempDir)
                }.value
                convertedTempURL = converted
                kindleOriginExtension = fileURL.pathExtension.lowercased()
                workingURL = converted
                workingFormat = .epub
                Self.log.info("Kindle convert-on-import: converted source to EPUB")
            } catch let error as MobiDecodeError {
                // SEMANTIC failure (DRM/corrupt/no-markup) → import the original
                // Kindle file natively; the user never loses the ability to
                // import a book the converter can't yet handle (decision #8).
                Self.log.warning("Kindle conversion failed semantically (\(String(describing: error), privacy: .public)) — importing native")
            } catch let error as MobiEPUBError {
                Self.log.warning("Kindle conversion failed (assembly: \(String(describing: error), privacy: .public)) — importing native")
            }
            // A filesystem/ZIPWriter write failure is NOT caught here → it
            // propagates as a real import error (decision #8 — IO faults are not
            // silently masked as a fallback).
        }

        // Step 4: Text-specific validation (binary masquerade + encoding detection)
        // Only reads first 64KB for detection to avoid full-file memory spike.
        var detectedEncoding: String? = nil
        if workingFormat == .txt || workingFormat == .md {
            let sampleData = try readFileDataSample(at: workingURL, maxBytes: 64 * 1024)
            do {
                let encodingResult = try EncodingDetector.detect(data: sampleData)
                detectedEncoding = EncodingDetector.encodingName(encodingResult.encoding)
            } catch let error as ImportError {
                throw error
            } catch {
                throw ImportError.encodingDetectionFailed
            }
        }

        // Step 5: Compute content hash (of the working file — the converted EPUB
        // when convert-on-import ran, else the original).
        let hashResult = try await ContentHasher.hash(fileAt: workingURL)

        // Step 6: Build fingerprint
        guard let fingerprint = DocumentFingerprint.validated(
            contentSHA256: hashResult.sha256Hex,
            fileByteCount: hashResult.byteCount,
            format: workingFormat
        ) else {
            throw ImportError.hashComputationFailed("Invalid hash result")
        }

        // Step 7: Check for duplicate
        let fingerprintKey = fingerprint.canonicalKey
        if let existing = try await persistence.findBook(byFingerprintKey: fingerprintKey) {
            // Replace provenance with the new import source
            let provenance = ImportProvenance(
                source: source,
                importedAt: Date(),
                originalURLBookmarkData: nil
            )
            try await persistence.replaceProvenance(provenance, toBookWithKey: fingerprintKey)

            // Bug #247: when restore supplies a manifest title override,
            // update the existing row's title so a dedupe-hit on restore
            // surfaces the manifest title (the source of truth) instead
            // of whatever stale title the prior import left behind.
            // We update only when the override actually differs — saves
            // a SwiftData write on the common case where the user
            // re-imports the same file from the same source.
            let resolvedTitle: String
            let resolvedAuthor: String?
            if let override = trimmedOverride, override != existing.title {
                try await persistence.updateBookTitle(
                    fingerprintKey: fingerprintKey,
                    title: override,
                    author: nil  // Don't clobber an existing author on a routine dedupe.
                )
                resolvedTitle = override
                resolvedAuthor = existing.author
            } else {
                resolvedTitle = existing.title
                resolvedAuthor = existing.author
            }

            // Bug #197: duplicate path still surfaces the row so a user who
            // re-shares an already-imported file sees the library reflect it
            // (selection, scroll-to-row, or just confirmation that "it's
            // already there"). The library observer treats this as a refresh
            // signal, not a row-insertion signal.
            NotificationCenter.default.post(
                name: .bookDidImport,
                object: nil,
                userInfo: ["fingerprintKey": existing.fingerprintKey]
            )

            // Return persisted metadata. For an identical file (same SHA-256 + size),
            // detectedEncoding and other metadata are unchanged.
            return ImportResult(
                fingerprintKey: existing.fingerprintKey,
                title: resolvedTitle,
                author: resolvedAuthor,
                fingerprint: existing.fingerprint,
                provenance: provenance,
                detectedEncoding: existing.detectedEncoding,
                isDuplicate: true
            )
        }

        // Step 8: Copy to sandbox (atomic: temp + rename). Copies the WORKING
        // file — the converted EPUB when convert-on-import ran.
        let sandboxCopy = try atomicCopyToSandbox(
            sourceURL: workingURL,
            fingerprintKey: fingerprintKey,
            format: workingFormat
        )
        let sandboxURL = sandboxCopy.url

        /// Rollback helper: only delete sandbox file if this import created it.
        /// Prevents deleting a valid file owned by a concurrent import.
        func rollbackSandboxIfOwned() {
            guard sandboxCopy.createdByThisImport else { return }
            try? FileManager.default.removeItem(at: sandboxURL)
        }

        // Step 9: Extract metadata from the working URL (sandbox filename is
        // hash-based). For a converted Kindle book the working file is the
        // self-describing EPUB, so EPUBMetadataExtractor recovers the source's
        // title/author/cover (baked in by WI-4a) — correct display metadata.
        let extractor = extractors[workingFormat] ?? TXTMetadataExtractor()
        let metadata: BookMetadata
        do {
            metadata = try await extractor.extractMetadata(from: workingURL)
        } catch let importErr as ImportError {
            rollbackSandboxIfOwned()
            throw importErr
        } catch {
            rollbackSandboxIfOwned()
            throw ImportError.fileNotReadable("Metadata extraction failed: \(type(of: error))")
        }

        // Step 9.5: Extract and save cover image (non-fatal)
        if !CustomCoverStore.hasCover(for: fingerprintKey) {
            if let coverImage = await extractor.extractCoverImage(from: sandboxURL) {
                try? CustomCoverStore.saveCover(coverImage, for: fingerprintKey)
            }
        }

        // Step 10: Build provenance. When convert-on-import ran, record the
        // Kindle origin (best-effort, non-load-bearing — design decision #5).
        let provenance = ImportProvenance(
            source: source,
            importedAt: Date(),
            originalURLBookmarkData: nil,
            convertedFromKindleExtension: kindleOriginExtension,
            converterVersion: kindleOriginExtension == nil ? nil : MobiEPUBConverter.version
        )

        // Step 11: Persist book record
        // Preserve the source URL's extension so backup → restore can reconstruct
        // it on a fresh device. Particularly matters for MOBI/PRC/AZW which all
        // collapse to canonical BookFormat.azw3 — without this, restore loses
        // the user's original extension.
        // The canonical blob extension is the WORKING file's — "epub" for a
        // converted Kindle book (the blob IS an EPUB; the original Kindle
        // extension lives in provenance, Step 10). Restore reconstructs the
        // blob from this, so it must match the stored bytes.
        let pathExt = workingURL.pathExtension.lowercased()
        let originalExt: String? = pathExt.isEmpty ? nil : pathExt
        // Bug #247: when the caller (typically the WebDAV restore path)
        // supplies a non-empty title override, it wins over the extractor's
        // filename-derived title. The override has already been trimmed
        // and validated above; the extractor's title is the fallback when
        // no override is supplied (in-app picker, share sheet, etc.) or
        // when restoring an older manifest with no per-entry title.
        let resolvedTitle = trimmedOverride ?? metadata.title
        let record = BookRecord(
            fingerprintKey: fingerprintKey,
            title: resolvedTitle,
            author: metadata.author,
            coverImagePath: metadata.coverImagePath,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: detectedEncoding,
            addedAt: Date(),
            originalExtension: originalExt
        )

        let persisted: BookRecord
        do {
            persisted = try await persistence.insertBook(record)
        } catch let importErr as ImportError {
            rollbackSandboxIfOwned()
            try? CustomCoverStore.removeCover(for: fingerprintKey)
            throw importErr
        } catch {
            rollbackSandboxIfOwned()
            try? CustomCoverStore.removeCover(for: fingerprintKey)
            throw ImportError.persistenceFailed
        }

        // Bug #139: Step 12 (indexing-trigger notification) removed. Lazy
        // indexing on search-open is the actual production path.

        // Bug #197: post the .bookDidImport refresh signal so any library
        // view (regardless of which entry path triggered the import — in-app
        // picker, Share Sheet via FileURLImportRouter, future flows) can
        // reload its book list without polling. Posted AFTER persist so
        // observers reading from SwiftData see the new row.
        NotificationCenter.default.post(
            name: .bookDidImport,
            object: nil,
            userInfo: ["fingerprintKey": persisted.fingerprintKey]
        )

        // Step 13: EPUB pre-extraction for instant open (WI-8)
        if persisted.fingerprint.format == .epub {
            Task.detached(priority: .utility) {
                await EPUBPreExtractor.preExtract(epubURL: sandboxURL)
            }
        }

        return ImportResult(
            fingerprintKey: persisted.fingerprintKey,
            title: persisted.title,
            author: persisted.author,
            fingerprint: persisted.fingerprint,
            provenance: provenance,
            detectedEncoding: detectedEncoding,
            isDuplicate: false
        )
    }

    // MARK: - Private

    /// Resolves the BookFormat from the file extension.
    private func resolveFormat(fileURL: URL) throws -> BookFormat {
        let ext = fileURL.pathExtension.lowercased()

        for format in BookFormat.allCases where format.isImportableV1 {
            if format.fileExtensions.contains(ext) {
                return format
            }
        }

        throw ImportError.unsupportedFormat(ext)
    }

    /// Reads a sample of file data for encoding detection.
    /// Only reads up to `maxBytes` to avoid full-file memory spike on large files.
    private func readFileDataSample(at url: URL, maxBytes: Int) throws -> Data {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let data = handle.readData(ofLength: maxBytes)
            return data
        } catch {
            throw ImportError.fileNotReadable("File read failed: \(type(of: error))")
        }
    }

    /// Result of a sandbox copy operation.
    private struct SandboxCopyResult {
        let url: URL
        /// True if this call created the file; false if it already existed.
        let createdByThisImport: Bool
    }

    /// Atomically copies the source file to the sandbox directory.
    /// Uses temp file + rename for crash safety.
    private func atomicCopyToSandbox(
        sourceURL: URL,
        fingerprintKey: String,
        format: BookFormat
    ) throws -> SandboxCopyResult {
        // Ensure sandbox directory exists
        try FileManager.default.createDirectory(
            at: sandboxBooksDirectory,
            withIntermediateDirectories: true
        )

        let safeName = fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let ext = format.fileExtensions.first ?? "bin"
        let finalURL = sandboxBooksDirectory
            .appendingPathComponent(safeName)
            .appendingPathExtension(ext)

        // If already exists (re-import after crash or concurrent import), return existing
        if FileManager.default.fileExists(atPath: finalURL.path) {
            return SandboxCopyResult(url: finalURL, createdByThisImport: false)
        }

        let tempURL = sandboxBooksDirectory
            .appendingPathComponent(".\(safeName)_\(UUID().uuidString).tmp")

        do {
            try FileManager.default.copyItem(at: sourceURL, to: tempURL)
        } catch {
            throw ImportError.sandboxCopyFailed("Copy failed: \(type(of: error))")
        }

        do {
            try FileManager.default.moveItem(at: tempURL, to: finalURL)
        } catch {
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            // If finalURL now exists, a concurrent import won the race — not an error
            if FileManager.default.fileExists(atPath: finalURL.path) {
                return SandboxCopyResult(url: finalURL, createdByThisImport: false)
            }
            throw ImportError.sandboxCopyFailed("Rename failed")
        }

        return SandboxCopyResult(url: finalURL, createdByThisImport: true)
    }
}
