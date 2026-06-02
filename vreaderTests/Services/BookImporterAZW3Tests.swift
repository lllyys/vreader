// Purpose: Tests that Kindle format extensions (.mobi, .azw, .prc) are normalized
// to .azw3 at import time by BookImporter's resolveFormat logic.

import Testing
import Foundation
@testable import vreader

@Suite("BookImporter — AZW3 Format Normalization")
struct BookImporterAZW3Tests {

    // MARK: - Setup Helpers

    /// Creates a temporary file with the given extension and minimal content.
    private func makeTempFile(extension ext: String, content: Data = Data([0x00])) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("kindle_test_\(UUID().uuidString).\(ext)")
        try content.write(to: url)
        return url
    }

    private func makeSandboxDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox_azw3_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeImporter() async throws -> (BookImporter, MockPersistenceActor, URL) {
        let mock = MockPersistenceActor()
        let sandbox = try makeSandboxDir()
        // These tests exercise native Kindle format-normalization (.mobi/.azw/.prc →
        // canonical .azw3), independent of convert-on-import (now default ON, Phase-2
        // G2). Pin the override OFF so they test the native path deterministically,
        // not via the unconvertible-synthetic-fixture conversion fallback.
        let flags = FeatureFlags(environment: .prod)
        flags.setOverride(false, for: .kindleConvertOnImport)
        let importer = BookImporter(
            persistence: mock,
            sandboxBooksDirectory: sandbox,
            featureFlags: flags
        )
        return (importer, mock, sandbox)
    }

    // MARK: - Format Resolution via BookFormat

    @Test(".mobi extension maps to .azw3 format")
    func mobiExtensionResolvesToAZW3() {
        let extensions = BookFormat.azw3.fileExtensions
        #expect(extensions.contains("mobi"))
    }

    @Test(".azw extension maps to .azw3 format")
    func azwExtensionResolvesToAZW3() {
        let extensions = BookFormat.azw3.fileExtensions
        #expect(extensions.contains("azw"))
    }

    @Test(".prc extension maps to .azw3 format")
    func prcExtensionResolvesToAZW3() {
        let extensions = BookFormat.azw3.fileExtensions
        #expect(extensions.contains("prc"))
    }

    @Test(".azw3 extension maps to .azw3 format")
    func azw3ExtensionResolvesToAZW3() {
        let extensions = BookFormat.azw3.fileExtensions
        #expect(extensions.contains("azw3"))
    }

    @Test("azw3 format is importable")
    func azw3IsImportable() {
        #expect(BookFormat.azw3.isImportableV1 == true)
        #expect(BookFormat.importableFormats.contains(.azw3))
    }

    // MARK: - Import Pipeline: Kindle Extensions Resolve to .azw3

    @Test(
        "Kindle extensions all resolve to .azw3 format on import",
        arguments: ["mobi", "azw", "prc", "azw3"]
    )
    func kindleExtensionResolvesToAZW3OnImport(ext: String) async throws {
        let fileURL = try makeTempFile(extension: ext)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: fileURL, source: .filesApp)
        #expect(result.fingerprint.format == .azw3)
    }

    // MARK: - Sandbox Copy Uses .azw3 Extension

    @Test("Sandbox copy of .mobi file uses .azw3 extension")
    func sandboxCopyUsesAZW3Extension() async throws {
        let fileURL = try makeTempFile(extension: "mobi")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: fileURL, source: .filesApp)

        // The sandbox file should use .azw3 extension (first in fileExtensions)
        let safeName = result.fingerprintKey.replacingOccurrences(of: ":", with: "_")
        let expectedPath = sandbox
            .appendingPathComponent(safeName)
            .appendingPathExtension("azw3")
        #expect(FileManager.default.fileExists(atPath: expectedPath.path))
    }

    // MARK: - Case Insensitivity

    @Test("Uppercase .MOBI extension resolves correctly")
    func uppercaseMobiResolves() async throws {
        // resolveFormat lowercases the extension, so .MOBI should work
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("kindle_test_\(UUID().uuidString).MOBI")
        try Data([0x00]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: url, source: .filesApp)
        #expect(result.fingerprint.format == .azw3)
    }

    // MARK: - No Encoding Detection for AZW3

    @Test("AZW3 import does not run encoding detection")
    func azw3SkipsEncodingDetection() async throws {
        let fileURL = try makeTempFile(extension: "azw3")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let (importer, _, sandbox) = try await makeImporter()
        defer { try? FileManager.default.removeItem(at: sandbox) }

        let result = try await importer.importFile(at: fileURL, source: .filesApp)
        // Encoding detection is only for .txt and .md
        #expect(result.detectedEncoding == nil)
    }

    // MARK: - ReaderContainerView Dispatch Verification

    @Test("BookFormat.azw3 rawValue is 'azw3' for reader dispatch")
    func azw3RawValueMatchesReaderDispatch() {
        // ReaderContainerView dispatches on book.format.lowercased()
        // It should only need `case "azw3":` — not "mobi"/"azw"/"prc"
        // because BookImporter normalizes all Kindle extensions to .azw3 at import time.
        #expect(BookFormat.azw3.rawValue == "azw3")
    }
}
