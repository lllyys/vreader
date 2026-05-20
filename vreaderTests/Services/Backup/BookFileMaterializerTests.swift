// Purpose: Tests for BookFileMaterializer — feature #46's restore-side
// download + verify + import orchestrator. Uses a stub BackupBlobReading +
// a wrapping BookImporter so the materializer's logic is exercised without
// real WebDAV or SwiftData.
//
// @coordinates-with: vreader/Services/Backup/BookFileMaterializer.swift,
//   vreader/Services/Backup/BackupBlobStore.swift,
//   dev-docs/plans/20260503-feature-46-materializing-restore.md

import Testing
import Foundation
import CryptoKit
@testable import vreader

@Suite("BookFileMaterializer — feature #46 WI-5")
struct BookFileMaterializerTests {

    // MARK: - Stub blob reader

    /// Collects progress callbacks from the @Sendable closure into an array.
    /// Actor-isolated because the materializer's progress callback is @Sendable
    /// and may fire from any context.
    actor ProgressCollector {
        private(set) var values: [Double] = []
        func record(_ value: Double) { values.append(value) }
    }

    actor StubBlobReader: BackupBlobReading {
        var blobs: [String: Data] = [:]
        var downloadError: BackupBlobStoreError?

        func setBlob(_ data: Data, at path: String) {
            blobs[path] = data
        }

        func setDownloadError(_ error: BackupBlobStoreError?) {
            downloadError = error
        }

        func existsWithSize(at path: String) async throws -> Int64? {
            guard let data = blobs[path] else { return nil }
            return Int64(data.count)
        }

        func download(from path: String) async throws -> Data {
            if let error = downloadError { throw error }
            guard let data = blobs[path] else {
                throw BackupBlobStoreError.underlying("not found: \(path)")
            }
            return data
        }
    }

    // MARK: - Helpers

    private static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    }

    private static func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("matz_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func makeSandboxDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Builds a manifest entry for `data` of the given format. Computes a
    /// real SHA-256 and BlobPath so tests aren't full of magic constants.
    private static func makeEntry(
        data: Data,
        format: BookFormat = .epub,
        originalExtension: String? = nil
    ) -> BackupLibraryEntry {
        let sha = sha256Hex(data)
        let bytes = Int64(data.count)
        let ext = originalExtension ?? format.fileExtensions.first ?? format.rawValue
        return BackupLibraryEntry(
            fingerprintKey: "\(format.rawValue):\(sha):\(bytes)",
            format: format.rawValue,
            sha256: sha,
            byteCount: bytes,
            originalExtension: ext,
            title: "T",
            author: "A",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            blobPath: BlobPath.make(format: format, sha256: sha, byteCount: bytes)
        )
    }

    /// Returns (materializer, blobReader, importer, sandboxDir, tempDir).
    private static func makeRig() async throws -> (BookFileMaterializer, StubBlobReader, MockPersistenceActor, URL, URL) {
        let blobReader = StubBlobReader()
        let mockPersistence = MockPersistenceActor()
        let sandbox = try makeSandboxDir()
        let temp = try makeTempDir()
        let importer = BookImporter(persistence: mockPersistence, sandboxBooksDirectory: sandbox)

        // Sandbox resolver mirrors LibraryBookItem's convention but rooted at
        // our test sandbox dir — keeps tests isolated from
        // Application Support (which the production resolver targets).
        let resolver: SandboxURLResolver = { fingerprintKey, originalExtension in
            let safeName = fingerprintKey.replacingOccurrences(of: ":", with: "_")
            return sandbox.appendingPathComponent(safeName).appendingPathExtension(originalExtension)
        }

        let materializer = BookFileMaterializer(
            blobStore: blobReader,
            importer: importer,
            tempDirectory: temp,
            resolveSandboxURL: resolver
        )
        return (materializer, blobReader, mockPersistence, sandbox, temp)
    }

    // MARK: - Empty input

    @Test func materialize_emptyEntries_returnsEmptyAndCallsProgress() async throws {
        let (materializer, _, _, _, _) = try await Self.makeRig()
        let collector = ProgressCollector()
        let results = await materializer.materialize([]) { value in
            Task { await collector.record(value) }
        }
        // Drain the inflight Tasks before reading.
        await Task.yield()
        await Task.yield()
        #expect(results.isEmpty)
        let updates = await collector.values
        #expect(updates.contains(0.0))
        #expect(updates.contains(1.0))
    }

    // MARK: - Happy path: fresh download

    @Test func materialize_singleMissingEntry_downloadsAndImports() async throws {
        let (materializer, blobReader, mock, _, _) = try await Self.makeRig()
        let payload = Data(repeating: 0x42, count: 1024)  // EPUB-ish bytes
        // Real ZIP magic so BookImporter accepts the file as EPUB.
        let epubBytes = Data([0x50, 0x4B, 0x03, 0x04]) + payload
        let entry = Self.makeEntry(data: epubBytes, format: .epub)
        await blobReader.setBlob(epubBytes, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        switch results[0].outcome {
        case .downloaded(let key):
            #expect(key == entry.fingerprintKey)
        default:
            Issue.record("expected .downloaded, got \(results[0].outcome)")
        }
        // Persisted via importer.
        let stored = await mock.book(forKey: entry.fingerprintKey)
        #expect(stored != nil)
        #expect(stored?.originalExtension == "epub")
    }

    // MARK: - Already-local skip

    @Test func materialize_existingLocalFileWithMatchingHash_skipsDownload() async throws {
        let (materializer, blobReader, persistence, sandbox, _) = try await Self.makeRig()
        let payload = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0xAB, count: 512)
        let entry = Self.makeEntry(data: payload, format: .epub)
        // Seed the persistence row so this is the "row + file consistent"
        // happy path — bug #114 carved out the "row missing" sub-case
        // below as a separate test.
        let prior = BookRecord(
            fingerprintKey: entry.fingerprintKey,
            title: entry.title ?? "T",
            author: entry.author,
            coverImagePath: nil,
            fingerprint: DocumentFingerprint(
                contentSHA256: entry.sha256,
                fileByteCount: entry.byteCount,
                format: BookFormat(rawValue: entry.format) ?? .epub
            ),
            provenance: ImportProvenance(source: .filesApp, importedAt: Date(), originalURLBookmarkData: nil),
            detectedEncoding: nil,
            addedAt: entry.addedAt,
            originalExtension: entry.originalExtension,
            lastOpenedAt: entry.lastOpenedAt,
            fileState: .local,
            blobPath: nil
        )
        await persistence.seed(prior)
        // Pre-place the file at the resolved sandbox location with matching
        // bytes — materializer should hash + skip download.
        let safeName = entry.fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let localURL = sandbox.appendingPathComponent(safeName).appendingPathExtension(entry.originalExtension)
        try payload.write(to: localURL)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        #expect(results[0].outcome == .alreadyLocal)
        // Blob was not requested — we never called download.
        let stored = await blobReader.blobs
        #expect(stored.isEmpty)
    }

    // MARK: - Bug #114: orphan file (canonical file present, no SwiftData row)

    @Test func materialize_localFilePresentButRowMissing_reimportsAndInsertsRow() async throws {
        // Bug #114: deleteBook removes the SwiftData row but leaves the
        // sandbox file in place. On next restore, the materializer's
        // `.alreadyLocal` short-circuit returned success without ever
        // calling BookImporter — so the row never came back and the
        // book stayed invisible in the library.
        //
        // Fixed behavior: when the canonical file exists but no row
        // exists for the fingerprintKey, treat the file as a download
        // result and run the import path so the row gets inserted.
        let (materializer, blobReader, persistence, sandbox, _) = try await Self.makeRig()
        let payload = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0x77, count: 512)
        let entry = Self.makeEntry(data: payload, format: .epub)

        // Pre-place the canonical file (the orphan) but DO NOT seed a row.
        let safeName = entry.fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let localURL = sandbox.appendingPathComponent(safeName).appendingPathExtension(entry.originalExtension)
        try payload.write(to: localURL)

        // Confirm the orphan precondition before running the materializer.
        let preRow = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        #expect(preRow == nil)

        let results = await materializer.materialize([entry]) { _ in }

        #expect(results.count == 1)
        // Either outcome is acceptable as long as it counts as success;
        // the critical invariant is the row now exists.
        #expect(results[0].isSuccess)
        // Blob still not requested — we don't re-download an already-good file.
        let stored = await blobReader.blobs
        #expect(stored.isEmpty)
        // The row got inserted.
        let postRow = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        #expect(postRow != nil)
        #expect(postRow?.fingerprintKey == entry.fingerprintKey)
    }

    // MARK: - Corrupt local file (preflight rehash catches it)

    @Test func materialize_corruptLocalFile_redownloadsClean() async throws {
        let (materializer, blobReader, _, sandbox, _) = try await Self.makeRig()
        let goodPayload = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0xCC, count: 256)
        let entry = Self.makeEntry(data: goodPayload, format: .epub)
        // Pre-place a CORRUPT file at the resolved sandbox location (right
        // size, wrong bytes) — without preflight rehash, BookImporter
        // would trust this file. Materializer should detect mismatch + remove.
        let safeName = entry.fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let localURL = sandbox.appendingPathComponent(safeName).appendingPathExtension(entry.originalExtension)
        let corrupt = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0x00, count: 256)
        try corrupt.write(to: localURL)
        await blobReader.setBlob(goodPayload, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        switch results[0].outcome {
        case .downloaded:
            break  // expected
        default:
            Issue.record("expected .downloaded after preflight detected corrupt local, got \(results[0].outcome)")
        }
    }

    // MARK: - Download failure

    @Test func materialize_downloadFailure_returnsDownloadFailed() async throws {
        let (materializer, blobReader, _, _, _) = try await Self.makeRig()
        let entry = Self.makeEntry(data: Data([0x50, 0x4B, 0x03, 0x04, 0xAB]), format: .epub)
        await blobReader.setDownloadError(.underlying("network timeout"))

        let results = await materializer.materialize([entry]) { _ in }
        switch results[0].outcome {
        case .downloadFailed:
            break  // expected
        default:
            Issue.record("expected .downloadFailed, got \(results[0].outcome)")
        }
    }

    // MARK: - Size mismatch on download

    @Test func materialize_downloadSizeMismatch_returnsSizeMismatch() async throws {
        let (materializer, blobReader, _, _, _) = try await Self.makeRig()
        // Build entry claiming a specific size, then return wrong-sized bytes.
        let manifestPayload = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0xEE, count: 1024)
        let entry = Self.makeEntry(data: manifestPayload, format: .epub)
        // Server returns truncated bytes.
        let truncated = Data(manifestPayload.prefix(100))
        await blobReader.setBlob(truncated, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        switch results[0].outcome {
        case .sizeAfterDownloadMismatch(let expected, let actual):
            #expect(expected == Int64(manifestPayload.count))
            #expect(actual == Int64(truncated.count))
        default:
            Issue.record("expected .sizeAfterDownloadMismatch, got \(results[0].outcome)")
        }
    }

    // MARK: - SHA-256 mismatch (size matches, bytes differ)

    @Test func materialize_sha256Mismatch_returnsHashError() async throws {
        let (materializer, blobReader, _, _, _) = try await Self.makeRig()
        let manifestPayload = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0x11, count: 1024)
        let entry = Self.makeEntry(data: manifestPayload, format: .epub)
        // Server returns SAME-size but DIFFERENT bytes.
        let tampered = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0x22, count: 1024)
        await blobReader.setBlob(tampered, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        switch results[0].outcome {
        case .sha256Mismatch(let expected, let actual):
            #expect(expected == entry.sha256)
            #expect(actual == Self.sha256Hex(tampered))
        default:
            Issue.record("expected .sha256Mismatch, got \(results[0].outcome)")
        }
    }

    // MARK: - MOBI extension preservation

    @Test func materialize_mobiUnderAzw3_writesTempWithMobiExtension() async throws {
        let (materializer, blobReader, mock, _, temp) = try await Self.makeRig()
        // MOBI/PRC/AZW collapse to canonical .azw3 in BookFormat. The manifest
        // carries originalExtension = "mobi" so the materializer writes the
        // temp blob with .mobi extension; BookImporter resolves format by
        // extension and accepts it as .azw3.
        let mobiBytes = Data([0x00, 0x00, 0x42, 0x4F, 0x4F, 0x4B, 0x4D, 0x4F, 0x42, 0x49])  // "BOOKMOBI" header
        let entry = Self.makeEntry(data: mobiBytes, format: .azw3, originalExtension: "mobi")
        await blobReader.setBlob(mobiBytes, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        switch results[0].outcome {
        case .downloaded:
            // Verify the imported book's originalExtension survived.
            let stored = await mock.book(forKey: entry.fingerprintKey)
            #expect(stored?.originalExtension == "mobi")
            #expect(stored?.fingerprint.format == .azw3)
        default:
            Issue.record("expected .downloaded for MOBI as .azw3, got \(results[0].outcome)")
        }
        // Temp file was cleaned up after import.
        let leftover = (try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? []
        #expect(leftover.isEmpty)
    }

    // MARK: - Bug #247: WebDAV restore preserves book titles from manifest

    /// TXT files have no embedded title metadata, so `TXTMetadataExtractor`
    /// derives the title from the on-disk filename. The materializer writes
    /// the downloaded blob to a temp file named `restore_<sha256>.txt`, so
    /// without a title override the persisted Book ends up with title
    /// `restore_<sha256-hex>` — the bug the user reported on 2026-05-20.
    ///
    /// Fix: pass `entry.title` from the manifest as a `titleOverride` to
    /// `BookImporter.importFile(...)`, which uses it for the persisted
    /// title when non-empty. Manifest-as-source-of-truth (matches the
    /// invariant `BackupSectionDTOs.swift:258-262`'s doc-comment names).
    @Test func materialize_txtWithManifestTitle_preservesOriginalTitle() async throws {
        let (materializer, blobReader, persistence, _, _) = try await Self.makeRig()
        // Plain UTF-8 TXT bytes. The actual title is in the manifest;
        // the on-disk filename will be `restore_<sha256>.txt`.
        let txtBytes = "Chapter 1. War and Peace.\n".data(using: .utf8)!
        let sha = Self.sha256Hex(txtBytes)
        let bytes = Int64(txtBytes.count)
        let originalTitle = "war-and-peace"
        let entry = BackupLibraryEntry(
            fingerprintKey: "txt:\(sha):\(bytes)",
            format: BookFormat.txt.rawValue,
            sha256: sha,
            byteCount: bytes,
            originalExtension: "txt",
            title: originalTitle,
            author: "Tolstoy",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            blobPath: BlobPath.make(format: .txt, sha256: sha, byteCount: bytes)
        )
        await blobReader.setBlob(txtBytes, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        #expect(results[0].isSuccess)

        let stored = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        #expect(stored != nil)
        // Bug #247: pre-fix this would equal `restore_<sha256>` (the temp
        // filename TXTMetadataExtractor derived from). Post-fix the
        // manifest title wins.
        #expect(stored?.title == originalTitle)
    }

    /// MD files share the filename-derived-title behavior with TXT (see
    /// `MDMetadataExtractor`). Identical bug surface, identical fix.
    @Test func materialize_mdWithManifestTitle_preservesOriginalTitle() async throws {
        let (materializer, blobReader, persistence, _, _) = try await Self.makeRig()
        let mdBytes = "# Heading\n\nbody.\n".data(using: .utf8)!
        let sha = Self.sha256Hex(mdBytes)
        let bytes = Int64(mdBytes.count)
        let originalTitle = "design-notes"
        let entry = BackupLibraryEntry(
            fingerprintKey: "md:\(sha):\(bytes)",
            format: BookFormat.md.rawValue,
            sha256: sha,
            byteCount: bytes,
            originalExtension: "md",
            title: originalTitle,
            author: nil,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            blobPath: BlobPath.make(format: .md, sha256: sha, byteCount: bytes)
        )
        await blobReader.setBlob(mdBytes, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        #expect(results[0].isSuccess)

        let stored = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        #expect(stored?.title == originalTitle)
    }

    /// When the manifest carries a nil title (older backups, edge case),
    /// fall back to the extractor's filename-derived title. The fix must
    /// not regress this path. The book is still restored; the user just
    /// keeps the SHA-prefixed title until they manually rename.
    @Test func materialize_nilManifestTitle_fallsBackToExtractedTitle() async throws {
        let (materializer, blobReader, persistence, _, _) = try await Self.makeRig()
        let txtBytes = "Some body.\n".data(using: .utf8)!
        let sha = Self.sha256Hex(txtBytes)
        let bytes = Int64(txtBytes.count)
        let entry = BackupLibraryEntry(
            fingerprintKey: "txt:\(sha):\(bytes)",
            format: BookFormat.txt.rawValue,
            sha256: sha,
            byteCount: bytes,
            originalExtension: "txt",
            title: nil,  // Older manifest with no title — pre-bug-#247 backups.
            author: nil,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            blobPath: BlobPath.make(format: .txt, sha256: sha, byteCount: bytes)
        )
        await blobReader.setBlob(txtBytes, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        #expect(results[0].isSuccess)

        let stored = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        // Falls back to TXTMetadataExtractor's filename-derived title.
        // The book is still restored; just with the SHA-prefixed title.
        #expect(stored?.title.hasPrefix("restore_") == true)
    }

    /// Whitespace-only or empty manifest titles must not silently override
    /// — that would produce a Book with title `""` and break library row
    /// display. Treat empty/whitespace as nil for override purposes.
    @Test func materialize_whitespaceOnlyManifestTitle_doesNotOverride() async throws {
        let (materializer, blobReader, persistence, _, _) = try await Self.makeRig()
        let txtBytes = "Hello.\n".data(using: .utf8)!
        let sha = Self.sha256Hex(txtBytes)
        let bytes = Int64(txtBytes.count)
        let entry = BackupLibraryEntry(
            fingerprintKey: "txt:\(sha):\(bytes)",
            format: BookFormat.txt.rawValue,
            sha256: sha,
            byteCount: bytes,
            originalExtension: "txt",
            title: "   \n\t  ",  // Pathological whitespace-only manifest title.
            author: nil,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            blobPath: BlobPath.make(format: .txt, sha256: sha, byteCount: bytes)
        )
        await blobReader.setBlob(txtBytes, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        #expect(results[0].isSuccess)

        let stored = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        // Whitespace-only override is ignored; extractor's title wins.
        // The persisted title is the SHA-prefixed temp filename — not "".
        #expect(stored?.title.isEmpty == false)
        #expect(stored?.title.hasPrefix("restore_") == true)
    }

    // MARK: - Classify

    @Test func classify_partitionsCorrectly() async throws {
        let (materializer, _, _, sandbox, _) = try await Self.makeRig()
        let dataA = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0x01, count: 100)
        let dataB = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: 0x02, count: 200)
        let entryA = Self.makeEntry(data: dataA, format: .epub)
        let entryB = Self.makeEntry(data: dataB, format: .epub)

        // Place entryA locally; entryB is missing.
        let safeNameA = entryA.fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let localA = sandbox.appendingPathComponent(safeNameA).appendingPathExtension(entryA.originalExtension)
        try dataA.write(to: localA)

        let (alreadyLocal, needsDownload) = await materializer.classify([entryA, entryB])
        #expect(alreadyLocal.map(\.fingerprintKey) == [entryA.fingerprintKey])
        #expect(needsDownload.map(\.fingerprintKey) == [entryB.fingerprintKey])
    }

    // MARK: - Progress monotonicity

    @Test func materialize_threeEntries_progressMonotonicAndEndsAtOne() async throws {
        let (materializer, blobReader, _, _, _) = try await Self.makeRig()
        var entries: [BackupLibraryEntry] = []
        for i in 0..<3 {
            let bytes = Data([0x50, 0x4B, 0x03, 0x04]) + Data(repeating: UInt8(i), count: 32 + i)
            let e = Self.makeEntry(data: bytes, format: .epub)
            await blobReader.setBlob(bytes, at: e.blobPath)
            entries.append(e)
        }
        let collector = ProgressCollector()
        let results = await materializer.materialize(entries) { value in
            Task { await collector.record(value) }
        }
        // Drain inflight Task.appends.
        for _ in 0..<10 { await Task.yield() }
        #expect(results.count == 3)
        let updates = await collector.values
        #expect(updates.first == 0.0)
        #expect(updates.last == 1.0)
        // Monotonic non-decreasing.
        for i in 1..<updates.count {
            #expect(updates[i] >= updates[i - 1])
        }
    }
}
