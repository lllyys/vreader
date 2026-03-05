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

    @Test func mdFormatThrows() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_\(UUID().uuidString).md")
        try "# Markdown".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        do {
            _ = try await importer.importFile(at: url, source: .filesApp)
            Issue.record("Expected unsupportedFormat error")
        } catch let error as ImportError {
            guard case .unsupportedFormat = error else {
                Issue.record("Expected unsupportedFormat, got \(error)")
                return
            }
        }
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

    // MARK: - Indexing Trigger

    @Test func indexingTriggerPosted() async throws {
        let fileURL = try makeTempTxtFile(content: "trigger test")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        // Use actor-isolated state to avoid data race
        let collector = NotificationCollector()
        let token = NotificationCenter.default.addObserver(
            forName: BookImporter.indexingNeededNotification,
            object: nil,
            queue: .main
        ) { notification in
            Task { await collector.record(notification) }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        _ = try await importer.importFile(at: fileURL, source: .filesApp)

        // Give main queue a chance to process the notification
        try await Task.sleep(for: .milliseconds(50))

        let received = await collector.notifications
        #expect(!received.isEmpty, "Expected indexing notification to be posted")
        #expect(received.first?.userInfo?["fingerprintKey"] != nil)
    }
}

// MARK: - Test Helpers

/// Actor-isolated notification collector for race-free notification capture in tests.
private actor NotificationCollector {
    var notifications: [Notification] = []

    func record(_ notification: Notification) {
        notifications.append(notification)
    }
}
