// Purpose: Tests for BookImporter — the main import orchestrator.
// Uses MockPersistenceActor and real file system for integration-like tests.

import Testing
import Foundation
@testable import vreader

@Suite("BookImporter")
struct BookImporterTests {

    // MARK: - Setup Helpers

    private func makeTempTxtFile(content: String = "Hello, world!") throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_\(UUID().uuidString).txt")
        try content.data(using: .utf8)!.write(to: url)
        return url
    }

    private func makeTempEpubFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_\(UUID().uuidString).epub")
        try Data([0x50, 0x4B, 0x03, 0x04]).write(to: url)  // ZIP magic bytes
        return url
    }

    private func makeTempPdfFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_\(UUID().uuidString).pdf")
        try "%PDF-1.4 fake content".data(using: .utf8)!.write(to: url)
        return url
    }

    private func makeSandboxDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeImporter(
        persistence: MockPersistenceActor? = nil,
        sandboxDir: URL? = nil
    ) async throws -> (BookImporter, MockPersistenceActor, URL) {
        let mock = persistence ?? MockPersistenceActor()
        let sandbox = try sandboxDir ?? makeSandboxDir()
        let importer = BookImporter(
            persistence: mock,
            sandboxBooksDirectory: sandbox
        )
        return (importer, mock, sandbox)
    }

    // MARK: - Happy Path: TXT Import

    @Test func importTxtFileSucceeds() async throws {
        let fileURL = try makeTempTxtFile(content: "Hello, world!")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, mock, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(
            at: fileURL,
            source: .filesApp
        )

        #expect(result.title == fileURL.deletingPathExtension().lastPathComponent)
        #expect(result.fingerprint.format == .txt)
        #expect(result.detectedEncoding == "utf-8")

        // Book was persisted
        let stored = await mock.book(forKey: result.fingerprintKey)
        #expect(stored != nil)
        #expect(stored?.fingerprintKey == result.fingerprintKey)
    }

    @Test func importTxtCopiesFileToSandbox() async throws {
        let fileURL = try makeTempTxtFile(content: "Copy me!")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: fileURL, source: .filesApp)

        // Verify file exists in sandbox
        let expectedPath = sandbox
            .appendingPathComponent(result.fingerprintKey.replacingOccurrences(of: ":", with: "_"))
            .appendingPathExtension("txt")
        #expect(FileManager.default.fileExists(atPath: expectedPath.path))
    }

    // MARK: - Happy Path: EPUB Import

    @Test func importEpubFileSucceeds() async throws {
        let fileURL = try makeTempEpubFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: fileURL, source: .filesApp)
        #expect(result.fingerprint.format == .epub)
        #expect(result.detectedEncoding == nil)
    }

    // MARK: - Happy Path: PDF Import

    @Test func importPdfFileSucceeds() async throws {
        let fileURL = try makeTempPdfFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: fileURL, source: .icloudDrive)
        #expect(result.fingerprint.format == .pdf)
        #expect(result.provenance.source == .icloudDrive)
    }

    // MARK: - Duplicate Detection

    @Test func duplicateImportReturnsExistingBook() async throws {
        let fileURL = try makeTempTxtFile(content: "Identical content")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, mock, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        // First import
        let first = try await importer.importFile(at: fileURL, source: .filesApp)

        // Second import of same file
        let second = try await importer.importFile(at: fileURL, source: .shareSheet)

        #expect(first.fingerprintKey == second.fingerprintKey)
        #expect(first.isDuplicate == false)
        #expect(second.isDuplicate == true)

        // Only first import should call insertBook; second detects duplicate via findBook
        let insertCount = await mock.insertCallCount
        #expect(insertCount == 1)
    }

    @Test func sameFilenameWithDifferentContentCreatesNewBook() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("same_name_\(UUID().uuidString).txt")

        // First version
        try "Version 1".data(using: .utf8)!.write(to: url)
        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let first = try await importer.importFile(at: url, source: .filesApp)

        // Overwrite with different content
        try "Version 2".data(using: .utf8)!.write(to: url)
        let second = try await importer.importFile(at: url, source: .filesApp)

        // Different content => different fingerprint
        #expect(first.fingerprintKey != second.fingerprintKey)

        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Unsupported Format

    @Test func unsupportedFormatThrows() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_\(UUID().uuidString).docx")
        try "fake docx".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        do {
            _ = try await importer.importFile(at: url, source: .filesApp)
            Issue.record("Expected unsupportedFormat error")
        } catch let error as ImportError {
            guard case .unsupportedFormat(let ext) = error else {
                Issue.record("Expected unsupportedFormat, got \(error)")
                return
            }
            #expect(ext == "docx")
        }
    }

    @Test func mdFormatImportsSuccessfully() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_\(UUID().uuidString).md")
        try "# Markdown".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: url, source: .filesApp)
        #expect(result.fingerprint.format == .md)
        #expect(result.detectedEncoding == "utf-8")
        #expect(result.title == "Markdown") // Title extracted from H1
    }

    // MARK: - Binary Masquerade

    @Test func binaryTxtFileRejected() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_\(UUID().uuidString).txt")
        // 50% control bytes => binary masquerade
        var bytes = [UInt8](repeating: 0x41, count: 100)
        for i in 0..<50 { bytes[i] = 0x01 }
        try Data(bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        do {
            _ = try await importer.importFile(at: url, source: .filesApp)
            Issue.record("Expected binaryMasquerade error")
        } catch let error as ImportError {
            #expect(error == .binaryMasquerade)
        }
    }

    // MARK: - Empty TXT

    @Test func emptyTxtFileSucceeds() async throws {
        let fileURL = try makeTempTxtFile(content: "")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: fileURL, source: .filesApp)
        #expect(result.fingerprint.format == .txt)
        #expect(result.fingerprint.fileByteCount == 0)
    }

    // MARK: - File Not Readable

    @Test func nonexistentFileThrows() async throws {
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).txt")

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        do {
            _ = try await importer.importFile(at: fakeURL, source: .filesApp)
            Issue.record("Expected fileNotReadable error")
        } catch let error as ImportError {
            // BookImporter checks readability before hashing, so this should be fileNotReadable
            guard case .fileNotReadable = error else {
                Issue.record("Expected fileNotReadable, got \(error)")
                return
            }
        }
    }

    // MARK: - Title From Filename

    @Test func titleExtractedFromFilename() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("My Great Book_\(UUID().uuidString).txt")
        try "content".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: url, source: .filesApp)
        #expect(result.title.hasPrefix("My Great Book_"))
    }

    // MARK: - Provenance Recorded

    @Test func provenanceRecorded() async throws {
        let fileURL = try makeTempTxtFile(content: "provenance test")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, mock, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: fileURL, source: .shareSheet)
        let stored = await mock.book(forKey: result.fingerprintKey)

        #expect(stored?.provenance.source == .shareSheet)
    }

    // MARK: - Unicode Filename

    @Test func unicodeFilenameHandled() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("日本語テスト_\(UUID().uuidString).txt")
        try "content".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: url, source: .filesApp)
        #expect(result.title.contains("日本語テスト"))
    }

    // Bug #139: `indexingTriggerPosted` test removed alongside its
    // production source. The notification was dead code (no production
    // observer); lazy indexing in `ReaderSearchCoordinator` is the real
    // path. Other tests in this suite cover import-success regression.

    // MARK: - Bug #247: titleOverride for restore paths

    /// When the caller supplies a non-empty `titleOverride`, the persisted
    /// Book title is the override, not the extractor's filename-derived
    /// title. This is the path the WebDAV restore materializer uses to
    /// thread the manifest's `BackupLibraryEntry.title` through.
    @Test func importFile_withTitleOverride_usesOverrideForPersistedTitle() async throws {
        // Use a TXT file with a SHA-prefixed temp filename to mirror the
        // production restore path's temp file naming convention.
        let dir = FileManager.default.temporaryDirectory
        let tempName = "restore_abc123def456"
        let fileURL = dir.appendingPathComponent("\(tempName)_\(UUID().uuidString).txt")
        try "Real book content".data(using: .utf8)!.write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, mock, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let originalTitle = "Hamlet"
        let result = try await importer.importFile(
            at: fileURL,
            source: .restore,
            titleOverride: originalTitle
        )
        #expect(result.title == originalTitle)

        let stored = await mock.book(forKey: result.fingerprintKey)
        #expect(stored?.title == originalTitle)
    }

    /// Nil override = current behavior (filename-derived title for TXT).
    @Test func importFile_nilTitleOverride_usesExtractedTitle() async throws {
        let fileURL = try makeTempTxtFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(
            at: fileURL,
            source: .restore,
            titleOverride: nil
        )
        // Filename-derived (e.g. "test_<uuid>") — extractor wins when no override.
        let filenameStem = fileURL.deletingPathExtension().lastPathComponent
        #expect(result.title == filenameStem)
    }

    /// Empty/whitespace override is ignored (would otherwise leave the
    /// Book with a blank title that breaks library rendering).
    @Test func importFile_emptyTitleOverride_doesNotOverride() async throws {
        let fileURL = try makeTempTxtFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let extractedFilename = fileURL.deletingPathExtension().lastPathComponent
        let resultEmpty = try await importer.importFile(
            at: fileURL,
            source: .restore,
            titleOverride: ""
        )
        #expect(resultEmpty.title == extractedFilename)

        // Different SHA file for the second import to avoid dedupe.
        let fileURL2 = try makeTempTxtFile(content: "Distinct content for second test")
        defer { try? FileManager.default.removeItem(at: fileURL2) }
        let resultWhitespace = try await importer.importFile(
            at: fileURL2,
            source: .restore,
            titleOverride: "   \t\n  "
        )
        #expect(resultWhitespace.title == fileURL2.deletingPathExtension().lastPathComponent)
    }

    /// Pathologically long overrides (>255 chars) get capped at 255 to
    /// match `Book.init`'s defense-in-depth truncation. Without this, the
    /// returned `ImportResult.title` would diverge from what's actually
    /// persisted in SwiftData on the new-row path AND the dedupe-hit
    /// path would silently bypass `Book.init`'s cap, leaving the DB row
    /// with an over-long title. Codex audit Medium fix.
    @Test func importFile_overlongTitleOverride_truncatedTo255() async throws {
        let fileURL = try makeTempTxtFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, mock, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let overlong = String(repeating: "A", count: 600)
        let expectedCap = String(repeating: "A", count: 255)
        let result = try await importer.importFile(
            at: fileURL,
            source: .restore,
            titleOverride: overlong
        )
        #expect(result.title == expectedCap)
        let stored = await mock.book(forKey: result.fingerprintKey)
        #expect(stored?.title == expectedCap)
        #expect(stored?.title.count == 255)
    }

    /// Override is trimmed before persistence — leading/trailing whitespace
    /// from manifests shouldn't survive into the persisted Book title.
    @Test func importFile_trimmedTitleOverride_persistsTrimmedValue() async throws {
        let fileURL = try makeTempTxtFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(
            at: fileURL,
            source: .restore,
            titleOverride: "   Pride and Prejudice   "
        )
        #expect(result.title == "Pride and Prejudice")
    }

    /// Title override on a duplicate-import path updates the existing
    /// row's title — restore-replacing a previously-imported book should
    /// surface the manifest title, not keep whatever stale title the
    /// existing row had from a long-ago first import.
    @Test func importFile_titleOverrideOnDuplicate_updatesPersistedTitle() async throws {
        let fileURL = try makeTempTxtFile(content: "Identical content")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, mock, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        // First import: no override → extractor-derived title.
        let first = try await importer.importFile(at: fileURL, source: .filesApp)
        let originalExtractedTitle = first.title

        // Second import: same content, with manifest-style title override.
        let manifestTitle = "From-Manifest Title"
        let second = try await importer.importFile(
            at: fileURL,
            source: .restore,
            titleOverride: manifestTitle
        )
        #expect(second.isDuplicate == true)
        #expect(second.fingerprintKey == first.fingerprintKey)
        // The override takes effect on the duplicate path too — manifest
        // is the source of truth, so a duplicate replace must surface it.
        #expect(second.title == manifestTitle)
        let stored = await mock.book(forKey: first.fingerprintKey)
        #expect(stored?.title == manifestTitle)
        #expect(stored?.title != originalExtractedTitle)
    }
}

// MARK: - Test Helpers

/// Actor-isolated notification collector for race-free notification capture in tests.
/// Stores only Sendable primitives extracted from notifications.
private actor NotificationCollector {
    private(set) var count = 0
    private(set) var hasFingerprintKey = false

    func record(hasFingerprintKey: Bool) {
        count += 1
        if hasFingerprintKey { self.hasFingerprintKey = true }
    }
}
