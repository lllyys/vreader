// Purpose: Tests for BookImporter persisting the source URL's pathExtension into
// the new Book.originalExtension field. Feature #46 WI-0a — required so that
// when a backup ZIP later restores a book, the materializer can write the blob
// to a temp file with the correct extension (e.g. ".mobi" for MOBI books that
// import as canonical .azw3 format).
//
// @coordinates-with: vreader/Services/BookImporter.swift,
//   vreader/Models/Book.swift, vreader/Services/PersistenceActor.swift

import Testing
import Foundation
@testable import vreader

@Suite("BookImporter — originalExtension (feature #46 WI-0a)")
struct BookImporterOriginalExtensionTests {

    // MARK: - Helpers

    private func makeTempFile(suffix: String, content: Data = Data([0x50, 0x4B, 0x03, 0x04])) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_\(UUID().uuidString)\(suffix)")
        try content.write(to: url)
        return url
    }

    private func makeSandboxDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeImporter() async throws -> (BookImporter, MockPersistenceActor, URL) {
        let mock = MockPersistenceActor()
        let sandbox = try makeSandboxDir()
        return (
            BookImporter(persistence: mock, sandboxBooksDirectory: sandbox),
            mock,
            sandbox
        )
    }

    // MARK: - Standard formats — extension matches canonical

    @Test func importEpub_persistsEpubExtension() async throws {
        let fileURL = try makeTempFile(suffix: ".epub")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, mock, _) = try await makeImporter()
        let result = try await importer.importFile(at: fileURL, source: .filesApp)

        let stored = await mock.book(forKey: result.fingerprintKey)
        #expect(stored?.originalExtension == "epub")
    }

    @Test func importPdf_persistsPdfExtension() async throws {
        let fileURL = try makeTempFile(suffix: ".pdf", content: Data("%PDF-1.4 fake".utf8))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, mock, _) = try await makeImporter()
        let result = try await importer.importFile(at: fileURL, source: .filesApp)

        let stored = await mock.book(forKey: result.fingerprintKey)
        #expect(stored?.originalExtension == "pdf")
    }

    // MARK: - MOBI under canonical .azw3 — extension preservation is the WHOLE point

    @Test func importMobi_persistsMobiExtension_evenThoughCanonicalIsAzw3() async throws {
        // MOBI/PRC/AZW are all imported as canonical BookFormat.azw3.
        // Without originalExtension preservation, restore loses the .mobi extension
        // and the materializer would write the temp blob as .azw3 — which works
        // but loses information about the original file the user imported.
        let fileURL = try makeTempFile(suffix: ".mobi", content: Data([0x00, 0x00, 0x42, 0x4F, 0x4F, 0x4B, 0x4D, 0x4F, 0x42, 0x49]))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, mock, _) = try await makeImporter()
        let result = try await importer.importFile(at: fileURL, source: .filesApp)

        let stored = await mock.book(forKey: result.fingerprintKey)
        // Canonical format collapses to azw3 (BookFormat.azw3.fileExtensions == ["azw3","azw","mobi","prc"]).
        #expect(stored?.fingerprint.format == .azw3)
        // But the original source extension is preserved so restore can reconstruct the .mobi filename.
        #expect(stored?.originalExtension == "mobi")
    }

    // MARK: - Case normalization

    @Test func importUppercaseExtension_lowercasesIt() async throws {
        // Filesystems may surface uppercase extensions. The blob path layout is
        // case-sensitive on most servers, so we normalize to lowercase here so
        // dedupe-by-fingerprint at upload time is deterministic.
        let fileURL = try makeTempFile(suffix: ".EPUB")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, mock, _) = try await makeImporter()
        let result = try await importer.importFile(at: fileURL, source: .filesApp)

        let stored = await mock.book(forKey: result.fingerprintKey)
        #expect(stored?.originalExtension == "epub")
    }

    // MARK: - Re-import preserves first observed extension

    @Test func reimportSameContent_preservesOriginalExtension() async throws {
        // Codex audit (Gate 4) flagged: when a user re-imports the same content
        // with a different source extension (e.g., first imported as .mobi, then
        // again as .azw3), the first import's extension is the user's first
        // observed truth and must not be overwritten. Production
        // PersistenceActor.replaceProvenance only mutates provenance — verify
        // the mock matches that semantic.
        let mobiURL = try makeTempFile(suffix: ".mobi", content: Data([0x00, 0x00, 0x42, 0x4F, 0x4F, 0x4B, 0x4D, 0x4F, 0x42, 0x49]))
        defer { try? FileManager.default.removeItem(at: mobiURL) }

        let (importer, mock, _) = try await makeImporter()
        let firstResult = try await importer.importFile(at: mobiURL, source: .filesApp)
        #expect(firstResult.isDuplicate == false)

        // Copy the same bytes into a different file with .azw3 extension.
        let azw3URL = mobiURL.deletingPathExtension().appendingPathExtension("azw3")
        try FileManager.default.copyItem(at: mobiURL, to: azw3URL)
        defer { try? FileManager.default.removeItem(at: azw3URL) }

        let secondResult = try await importer.importFile(at: azw3URL, source: .shareSheet)
        #expect(secondResult.isDuplicate == true)

        // Stored extension should still be the first import's extension.
        let stored = await mock.book(forKey: secondResult.fingerprintKey)
        #expect(stored?.originalExtension == "mobi")
    }

    // MARK: - Multi-dot filename takes only last extension

    @Test func multiDotFilename_takesOnlyLastExtension() async throws {
        // Path("book.v1.EPUB").pathExtension == "EPUB" (only the last segment).
        // After lowercasing → "epub". Confirms standard URL behavior.
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("book.v1.EPUB")
        try Data([0x50, 0x4B, 0x03, 0x04]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let (importer, mock, _) = try await makeImporter()
        let result = try await importer.importFile(at: url, source: .filesApp)

        let stored = await mock.book(forKey: result.fingerprintKey)
        #expect(stored?.originalExtension == "epub")
    }
}
