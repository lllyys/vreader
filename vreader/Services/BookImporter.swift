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
//   EncodingDetector.swift, MetadataExtractor.swift, ImportError.swift

import Foundation

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

    /// Posted after a successful import. `userInfo["fingerprintKey"]` contains the key.
    static let indexingNeededNotification = Notification.Name("BookImporter.indexingNeeded")

    private let persistence: any BookPersisting
    private let sandboxBooksDirectory: URL

    /// Metadata extractors by format.
    private let extractors: [BookFormat: any MetadataExtractor]

    init(
        persistence: any BookPersisting,
        sandboxBooksDirectory: URL,
        extractors: [BookFormat: any MetadataExtractor]? = nil
    ) {
        self.persistence = persistence
        self.sandboxBooksDirectory = sandboxBooksDirectory
        self.extractors = extractors ?? [
            .txt: TXTMetadataExtractor(),
            .epub: EPUBMetadataExtractor(),
            .pdf: PDFMetadataExtractor(),
            .md: MDMetadataExtractor(),
        ]
    }

    /// Imports a file into the library.
    ///
    /// - Parameters:
    ///   - fileURL: URL to the file to import. May be a security-scoped resource.
    ///   - source: How the file was provided (Files app, share sheet, etc.).
    /// - Returns: The import result with book identity and metadata.
    /// - Throws: `ImportError` for all failure modes.
    func importFile(
        at fileURL: URL,
        source: ImportSource
    ) async throws -> ImportResult {
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

        // Step 4: Text-specific validation (binary masquerade + encoding detection)
        // Only reads first 64KB for detection to avoid full-file memory spike.
        var detectedEncoding: String? = nil
        if format == .txt || format == .md {
            let sampleData = try readFileDataSample(at: fileURL, maxBytes: 64 * 1024)
            do {
                let encodingResult = try EncodingDetector.detect(data: sampleData)
                detectedEncoding = EncodingDetector.encodingName(encodingResult.encoding)
            } catch let error as ImportError {
                throw error
            } catch {
                throw ImportError.encodingDetectionFailed
            }
        }

        // Step 5: Compute content hash
        let hashResult = try await ContentHasher.hash(fileAt: fileURL)

        // Step 6: Build fingerprint
        guard let fingerprint = DocumentFingerprint.validated(
            contentSHA256: hashResult.sha256Hex,
            fileByteCount: hashResult.byteCount,
            format: format
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

            // Return persisted metadata. For an identical file (same SHA-256 + size),
            // detectedEncoding and other metadata are unchanged.
            return ImportResult(
                fingerprintKey: existing.fingerprintKey,
                title: existing.title,
                author: existing.author,
                fingerprint: existing.fingerprint,
                provenance: provenance,
                detectedEncoding: existing.detectedEncoding,
                isDuplicate: true
            )
        }

        // Step 8: Copy to sandbox (atomic: temp + rename)
        let sandboxCopy = try atomicCopyToSandbox(
            sourceURL: fileURL,
            fingerprintKey: fingerprintKey,
            format: format
        )
        let sandboxURL = sandboxCopy.url

        /// Rollback helper: only delete sandbox file if this import created it.
        /// Prevents deleting a valid file owned by a concurrent import.
        func rollbackSandboxIfOwned() {
            guard sandboxCopy.createdByThisImport else { return }
            try? FileManager.default.removeItem(at: sandboxURL)
        }

        // Step 9: Extract metadata from original URL (sandbox filename is hash-based)
        let extractor = extractors[format] ?? TXTMetadataExtractor()
        let metadata: BookMetadata
        do {
            metadata = try await extractor.extractMetadata(from: fileURL)
        } catch let importErr as ImportError {
            rollbackSandboxIfOwned()
            throw importErr
        } catch {
            rollbackSandboxIfOwned()
            throw ImportError.fileNotReadable("Metadata extraction failed: \(type(of: error))")
        }

        // Step 10: Build provenance
        let provenance = ImportProvenance(
            source: source,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )

        // Step 11: Persist book record
        let record = BookRecord(
            fingerprintKey: fingerprintKey,
            title: metadata.title,
            author: metadata.author,
            coverImagePath: metadata.coverImagePath,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: detectedEncoding,
            addedAt: Date()
        )

        let persisted: BookRecord
        do {
            persisted = try await persistence.insertBook(record)
        } catch let importErr as ImportError {
            rollbackSandboxIfOwned()
            throw importErr
        } catch {
            rollbackSandboxIfOwned()
            throw ImportError.persistenceFailed
        }

        // Step 12: Emit indexing trigger
        NotificationCenter.default.post(
            name: Self.indexingNeededNotification,
            object: nil,
            userInfo: ["fingerprintKey": fingerprintKey]
        )

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
