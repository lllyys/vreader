// Purpose: High-fidelity integration tests for Bug #247 — WebDAV restore
// title round-trip. Uses the REAL `PersistenceActor` (in-memory
// `ModelContainer` with the production `SchemaV7`), REAL `BookImporter`
// with REAL `MetadataExtractor`s, and the REAL `BookFileMaterializer`
// against a `BackupBlobReading` stub. The only stub is the network/blob
// layer; everything from the manifest-driven download → SHA verify →
// import → SwiftData write goes through production code.
//
// These tests cover the verification-exception path (per AGENTS.md
// "Close gate — verified, not just merged"): the symptom is impossible
// to reproduce on a device without a live WebDAV server, so this
// integration test drives the SAME code paths the production failure
// would hit. Closure comment cites this test method.
//
// @coordinates-with: vreader/Services/Backup/BookFileMaterializer.swift,
//   vreader/Services/Backup/BookFileImportFinalizer.swift,
//   vreader/Services/BookImporter.swift, vreader/Services/PersistenceActor.swift,
//   vreader/Services/MetadataExtractor.swift,
//   docs/bugs.md (Bug #247)

import Testing
import Foundation
import CryptoKit
import SwiftData
@testable import vreader

@Suite("Bug #247 — title restore high-fidelity integration")
struct BookFileMaterializerTitleRestoreIntegrationTests {

    // MARK: - Stub blob reader (the only stubbed layer)

    actor StubBlobReader: BackupBlobReading {
        var blobs: [String: Data] = [:]

        func setBlob(_ data: Data, at path: String) {
            blobs[path] = data
        }

        func existsWithSize(at path: String) async throws -> Int64? {
            guard let data = blobs[path] else { return nil }
            return Int64(data.count)
        }

        func download(from path: String) async throws -> Data {
            guard let data = blobs[path] else {
                throw BackupBlobStoreError.underlying("not found: \(path)")
            }
            return data
        }
    }

    // MARK: - Helpers (real production wiring, in-memory)

    private static func sha256Hex(_ data: Data) -> String {
        Data(SHA256.hash(data: data)).map { String(format: "%02x", $0) }.joined()
    }

    private static func makeTempDir(_ tag: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bug247-\(tag)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Builds a production-grade rig with the real PersistenceActor
    /// (in-memory SchemaV7), real BookImporter (with all real metadata
    /// extractors), real BookFileMaterializer, and the only stub at the
    /// blob-reader boundary.
    private static func makeRig() async throws -> (
        BookFileMaterializer,
        StubBlobReader,
        PersistenceActor,
        URL,  // sandbox
        URL   // temp staging
    ) {
        let schema = Schema(SchemaV7.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let persistence = PersistenceActor(modelContainer: container)
        let sandbox = try makeTempDir("sandbox")
        let temp = try makeTempDir("temp")
        let importer = BookImporter(persistence: persistence, sandboxBooksDirectory: sandbox)
        let blobReader = StubBlobReader()
        let resolver: SandboxURLResolver = { fingerprintKey, originalExtension in
            let safeName = fingerprintKey.replacingOccurrences(of: ":", with: "_")
            return sandbox
                .appendingPathComponent(safeName)
                .appendingPathExtension(originalExtension)
        }
        let materializer = BookFileMaterializer(
            blobStore: blobReader,
            importer: importer,
            tempDirectory: temp,
            resolveSandboxURL: resolver
        )
        return (materializer, blobReader, persistence, sandbox, temp)
    }

    private static func makeEntry(
        data: Data,
        format: BookFormat,
        title: String?,
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
            title: title,
            author: nil,
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastOpenedAt: nil,
            blobPath: BlobPath.make(format: format, sha256: sha, byteCount: bytes)
        )
    }

    // MARK: - End-to-end: restored TXT keeps its manifest title

    /// The original user-reported symptom (2026-05-20): "the books from
    /// web-dav backups lost there names". Drives the real production
    /// path end-to-end — same code that runs against a live WebDAV
    /// server, sans the network. If this test fails, the fix didn't
    /// thread the manifest title through.
    @Test func restoreTXT_preservesManifestTitle() async throws {
        let (materializer, blobs, persistence, _, _) = try await Self.makeRig()
        let txt = "Chapter 1.\n\nIt was the best of times.\n".data(using: .utf8)!
        let entry = Self.makeEntry(data: txt, format: .txt, title: "A Tale of Two Cities")
        await blobs.setBlob(txt, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        #expect(results[0].isSuccess)

        let stored = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        #expect(stored != nil)
        // Production path drives BookImporter → MetadataExtractor →
        // TXTMetadataExtractor → `BookMetadata.fromFilename(fileURL)`,
        // which without the override would produce `restore_<sha>`. With
        // the fix, the manifest title wins.
        #expect(stored?.title == "A Tale of Two Cities")
        // Sanity: NOT the SHA-prefixed temp name.
        #expect(stored?.title.hasPrefix("restore_") == false)
        // Format round-trip intact.
        #expect(stored?.fingerprint.format == .txt)
    }

    /// MD has the same filename-derived extractor path as TXT.
    @Test func restoreMD_preservesManifestTitle() async throws {
        let (materializer, blobs, persistence, _, _) = try await Self.makeRig()
        let md = "# Design notes\n\n- alpha\n- beta\n".data(using: .utf8)!
        let entry = Self.makeEntry(data: md, format: .md, title: "Architecture Notes")
        await blobs.setBlob(md, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        #expect(results[0].isSuccess)

        let stored = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        #expect(stored?.title == "Architecture Notes")
        #expect(stored?.title.hasPrefix("restore_") == false)
    }

    /// PDF uses a stub extractor that falls back to filename when no
    /// `Title` metadata is present. The fix should surface the manifest
    /// title for these PDFs too.
    @Test func restorePDF_preservesManifestTitle() async throws {
        let (materializer, blobs, persistence, _, _) = try await Self.makeRig()
        // Minimal PDF header — BookImporter only checks the extension
        // for format resolution, not magic bytes.
        let pdf = "%PDF-1.4\n%fake content for test\n".data(using: .utf8)!
        let entry = Self.makeEntry(data: pdf, format: .pdf, title: "User Manual v3")
        await blobs.setBlob(pdf, at: entry.blobPath)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        #expect(results[0].isSuccess)

        let stored = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        #expect(stored?.title == "User Manual v3")
    }

    /// Restoring multiple books in a single batch — each should keep its
    /// own manifest title. Catches "first wins" / "last wins" bugs in
    /// the override threading.
    @Test func restoreMultipleBooks_eachKeepsItsOwnTitle() async throws {
        let (materializer, blobs, persistence, _, _) = try await Self.makeRig()
        let txt1 = "Body of book one.\n".data(using: .utf8)!
        let txt2 = "Body of book two with different bytes.\n".data(using: .utf8)!
        let txt3 = "And a third one.\n".data(using: .utf8)!
        let e1 = Self.makeEntry(data: txt1, format: .txt, title: "First Book")
        let e2 = Self.makeEntry(data: txt2, format: .txt, title: "Second Book")
        let e3 = Self.makeEntry(data: txt3, format: .txt, title: "Third Book")
        await blobs.setBlob(txt1, at: e1.blobPath)
        await blobs.setBlob(txt2, at: e2.blobPath)
        await blobs.setBlob(txt3, at: e3.blobPath)

        let results = await materializer.materialize([e1, e2, e3]) { _ in }
        #expect(results.count == 3)
        for r in results { #expect(r.isSuccess) }

        let stored1 = try await persistence.findBook(byFingerprintKey: e1.fingerprintKey)
        let stored2 = try await persistence.findBook(byFingerprintKey: e2.fingerprintKey)
        let stored3 = try await persistence.findBook(byFingerprintKey: e3.fingerprintKey)
        #expect(stored1?.title == "First Book")
        #expect(stored2?.title == "Second Book")
        #expect(stored3?.title == "Third Book")
    }

    /// Dedupe-hit path: when a book is already imported (with its own
    /// title), restoring from a backup that has a different title should
    /// update the existing row to the manifest title. This exercises
    /// the production `updateBookTitle` call path with a real
    /// PersistenceActor.
    @Test func restoreAfterPriorImport_dedupeHitUpdatesTitleToManifest() async throws {
        let (materializer, blobs, persistence, _, _) = try await Self.makeRig()
        let txt = "Same content under two different names.\n".data(using: .utf8)!
        let entry = Self.makeEntry(data: txt, format: .txt, title: "Real Book Title")
        await blobs.setBlob(txt, at: entry.blobPath)

        // Simulate a prior import that left the row with a stale title
        // (e.g., a restore from before this bug was fixed).
        let priorTitle = "restore_\(entry.sha256.prefix(16))"
        let priorRecord = BookRecord(
            fingerprintKey: entry.fingerprintKey,
            title: String(priorTitle),
            author: nil,
            coverImagePath: nil,
            fingerprint: DocumentFingerprint(
                contentSHA256: entry.sha256,
                fileByteCount: entry.byteCount,
                format: .txt
            ),
            provenance: ImportProvenance(
                source: .filesApp,
                importedAt: Date(timeIntervalSince1970: 1_700_000_000),
                originalURLBookmarkData: nil
            ),
            detectedEncoding: "utf-8",
            addedAt: Date(timeIntervalSince1970: 1_700_000_000),
            originalExtension: "txt"
        )
        _ = try await persistence.insertBook(priorRecord)
        let pre = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        #expect(pre?.title.hasPrefix("restore_") == true)

        // Run the materializer — should hit the download path, then the
        // BookImporter dedupe branch, then updateBookTitle.
        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        #expect(results[0].isSuccess)

        let post = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        #expect(post?.title == "Real Book Title")
    }

    /// Already-local file path (preflight rehash hits, then reimport via
    /// BookImporter to ensure the row exists). The override should
    /// still flow through.
    @Test func restoreAlreadyLocalFile_titleOverrideStillApplies() async throws {
        let (materializer, blobs, persistence, sandbox, _) = try await Self.makeRig()
        let txt = "Content already on disk.\n".data(using: .utf8)!
        let entry = Self.makeEntry(data: txt, format: .txt, title: "Local Book")
        await blobs.setBlob(txt, at: entry.blobPath)

        // Pre-place the file at the canonical sandbox path WITHOUT a row.
        let safeName = entry.fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let localURL = sandbox
            .appendingPathComponent(safeName)
            .appendingPathExtension(entry.originalExtension)
        try txt.write(to: localURL)

        // Confirm no row pre-exists.
        let pre = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        #expect(pre == nil)

        let results = await materializer.materialize([entry]) { _ in }
        #expect(results.count == 1)
        #expect(results[0].isSuccess)

        let stored = try await persistence.findBook(byFingerprintKey: entry.fingerprintKey)
        #expect(stored != nil)
        // The reimportLocalFile path threads the override too — without
        // this, the title would be the canonical-sandbox filename
        // (`<sha>_<bytes>.<ext>`).
        #expect(stored?.title == "Local Book")
    }
}
