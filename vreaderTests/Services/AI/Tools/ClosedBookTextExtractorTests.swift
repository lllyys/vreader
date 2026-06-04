// Purpose: Feature #91 WI-8b — pin the off-actor closed-book text extractor's
// testable surface: TXT/MD extraction from a real on-device file (encoding-
// detected), the unsupported-format throw, and the imported-file sandbox-URL
// convention. EPUB/PDF extraction is file-fixture/device-verified (no synthetic
// fixture cheaply available in a CI unit test).
//
// @coordinates-with: ClosedBookTextExtractor.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-8)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #91 WI-8b — ClosedBookTextExtractor")
struct ClosedBookTextExtractorTests {

    @Test("extracts TXT/MD text from an on-device file (encoding-detected, CJK-safe)")
    func extractsPlainText() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let txtURL = dir.appendingPathComponent("book.txt")
        try "Hello, reader. 你好世界。".write(to: txtURL, atomically: true, encoding: .utf8)
        let extractor = ClosedBookTextExtractor()
        let txt = try await extractor.extract(url: txtURL, format: "txt")
        #expect(txt.contains("Hello, reader."))
        #expect(txt.contains("你好世界"))

        let mdURL = dir.appendingPathComponent("book.md")
        try "# Title\n\nthe body text".write(to: mdURL, atomically: true, encoding: .utf8)
        #expect(try await extractor.extract(url: mdURL, format: "md").contains("the body text"))
    }

    @Test("decodes a NON-UTF-8 file via the canonical TXTService decoder (UTF-16 BOM)")
    func decodesNonUTF8() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // A UTF-16 (BOM) file — the old detect-once + UTF-8-fallback path would
        // mis-decode this; the canonical decoder handles it.
        let url = dir.appendingPathComponent("u16.txt")
        try "经典文本 classic".write(to: url, atomically: true, encoding: .utf16)
        let text = try await ClosedBookTextExtractor().extract(url: url, format: "txt")
        // Exact content (no BOM / replacement-char garbage) — a `contains` check
        // would pass on mis-decode; assert the precise string (Gate-4 r2 Low).
        #expect(text.trimmingCharacters(in: .whitespacesAndNewlines) == "经典文本 classic")
        #expect(!text.contains("\u{FFFD}"))   // no replacement characters
    }

    @Test("resolveExisting finds a TXT book materialized under its .text original extension")
    func resolveExistingTriesCandidateExtensions() throws {
        // Simulate a lazy-download/restore that wrote the file as `.text`, not `.txt`.
        let sha = String(repeating: "a", count: 64)
        let key = "txt:\(sha):4096"
        let safeName = key.replacingOccurrences(of: ":", with: "_")
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let textURL = dir.appendingPathComponent(safeName).appendingPathExtension("text")
        try "body".write(to: textURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: textURL) }

        let resolved = ImportedBookFileURL.resolveExisting(fingerprintKey: key, format: "txt")
        #expect(resolved.lastPathComponent == "\(safeName).text")   // found the existing .text, not .txt
    }

    @Test("an unsupported format (azw3) throws, never returns empty")
    func unsupportedFormatThrows() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("x.azw3")
        await #expect(throws: (any Error).self) {
            _ = try await ClosedBookTextExtractor().extract(url: url, format: "azw3")
        }
    }

    @Test("a missing file throws (read failure surfaced, not a silent empty)")
    func missingFileThrows() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        await #expect(throws: (any Error).self) {
            _ = try await ClosedBookTextExtractor().extract(url: url, format: "txt")
        }
    }

    @Test("the shared ImportedBookFileURL resolves the sandbox convention")
    func importedURLConvention() {
        let sha = String(repeating: "a", count: 64)
        let url = ImportedBookFileURL.resolve(fingerprintKey: "epub:\(sha):4096", format: "epub")
        #expect(url.lastPathComponent == "epub_\(sha)_4096.epub")
        #expect(url.deletingLastPathComponent().lastPathComponent == "ImportedBooks")
    }
}
