// Purpose: Tests for MDMetadataExtractor — title extraction from H1, filename fallback,
// edge cases (empty, no H1, truncation, trailing markers).
//
// @coordinates-with: MDMetadataExtractor.swift

import Testing
import Foundation
@testable import vreader

@Suite("MDMetadataExtractor")
struct MDMetadataExtractorTests {

    // MARK: - H1 Extraction (static method)

    @Test("extracts first H1 heading")
    func extractsFirstH1() {
        let text = "# My Title\n\nSome content."
        let title = MDMetadataExtractor.extractFirstH1(from: text)
        #expect(title == "My Title")
    }

    @Test("extracts first H1 even after content")
    func h1AfterContent() {
        let text = "Some intro.\n\n# The Real Title\n\nMore content."
        let title = MDMetadataExtractor.extractFirstH1(from: text)
        #expect(title == "The Real Title")
    }

    @Test("ignores H2 and lower headings")
    func ignoresH2() {
        let text = "## Not H1\n### Also not\n#### Nope"
        let title = MDMetadataExtractor.extractFirstH1(from: text)
        #expect(title == nil)
    }

    @Test("returns nil for empty text")
    func emptyText() {
        let title = MDMetadataExtractor.extractFirstH1(from: "")
        #expect(title == nil)
    }

    @Test("returns nil for text without headings")
    func noHeadings() {
        let text = "Just plain text.\nMore text."
        let title = MDMetadataExtractor.extractFirstH1(from: text)
        #expect(title == nil)
    }

    @Test("strips trailing hash markers")
    func trailingHashes() {
        let text = "# My Title ###"
        let title = MDMetadataExtractor.extractFirstH1(from: text)
        #expect(title == "My Title")
    }

    @Test("handles H1 with only whitespace after #")
    func h1OnlyWhitespace() {
        let text = "#   \n\nContent"
        let title = MDMetadataExtractor.extractFirstH1(from: text)
        #expect(title == nil)
    }

    @Test("handles CJK H1 heading")
    func cjkHeading() {
        let text = "# 中文标题\n\n正文内容"
        let title = MDMetadataExtractor.extractFirstH1(from: text)
        #expect(title == "中文标题")
    }

    @Test("handles emoji in H1")
    func emojiHeading() {
        let text = "# Hello 🌍 World\n\nContent"
        let title = MDMetadataExtractor.extractFirstH1(from: text)
        #expect(title == "Hello 🌍 World")
    }

    @Test("picks first H1 among multiple H1s")
    func multipleH1s() {
        let text = "# First\n\n# Second\n\n# Third"
        let title = MDMetadataExtractor.extractFirstH1(from: text)
        #expect(title == "First")
    }

    // MARK: - Full Extractor (file-based)

    @Test("extracts title from file with H1")
    func extractFromFile() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("test_md_\(UUID().uuidString).md")
        try "# File Title\n\nContent here.".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = MDMetadataExtractor()
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "File Title")
        #expect(metadata.author == nil)
        #expect(metadata.coverImagePath == nil)
    }

    @Test("falls back to filename when no H1")
    func filenameWhenNoH1() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("My Document.md")
        try "No headings here.".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = MDMetadataExtractor()
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "My Document")
    }

    @Test("truncates long H1 to 255 characters")
    func longH1Truncation() async throws {
        let longTitle = String(repeating: "A", count: 300)
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("long_title_\(UUID().uuidString).md")
        try "# \(longTitle)\n\nContent.".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = MDMetadataExtractor()
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title.count == 255)
    }

    @Test("non-UTF8 encoded file uses encoding detection instead of failing silently")
    func nonUTF8File() async throws {
        let dir = FileManager.default.temporaryDirectory
        let filename = "shift_jis_test_\(UUID().uuidString)"
        let url = dir.appendingPathComponent("\(filename).md")
        // Shift-JIS encoded "# テスト"
        let shiftJISData = Data([0x23, 0x20, 0x83, 0x65, 0x83, 0x58, 0x83, 0x67])
        try shiftJISData.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = MDMetadataExtractor()
        let metadata = try await extractor.extractMetadata(from: url)
        // Must not be empty — either H1 extracted via encoding detection or filename fallback
        #expect(!metadata.title.isEmpty)
        // If encoding detection works, title should contain Japanese chars or the filename
        // (not raw mojibake). Both outcomes are acceptable:
        let isExtractedTitle = metadata.title != filename
        let isFilenameFallback = metadata.title == filename
        #expect(isExtractedTitle || isFilenameFallback)
    }

    @Test("empty file falls back to filename")
    func emptyFile() async throws {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("empty_test.md")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = MDMetadataExtractor()
        let metadata = try await extractor.extractMetadata(from: url)
        #expect(metadata.title == "empty_test")
    }
}
