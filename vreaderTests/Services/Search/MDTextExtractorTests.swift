// Purpose: Tests for MDTextExtractor — markdown syntax stripping,
// segment generation, offset tracking, edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("MDTextExtractor")
struct MDTextExtractorTests {

    // MARK: - Markdown Stripping

    @Test func stripsHeadings() {
        let md = "# Heading One\n\nSome text"
        let result = MDTextExtractor.stripMarkdown(md)
        #expect(result.contains("Heading One"))
        #expect(!result.contains("#"))
    }

    @Test func stripsBoldAndItalic() {
        let md = "This is **bold** and *italic* and ***both***"
        let result = MDTextExtractor.stripMarkdown(md)
        #expect(result.contains("bold"))
        #expect(result.contains("italic"))
        #expect(result.contains("both"))
        #expect(!result.contains("**"))
        #expect(!result.contains("*"))
    }

    @Test func stripsLinks() {
        let md = "Click [here](https://example.com) for more"
        let result = MDTextExtractor.stripMarkdown(md)
        #expect(result.contains("Click here for more"))
        #expect(!result.contains("https://"))
        #expect(!result.contains("["))
        #expect(!result.contains("("))
    }

    @Test func stripsImages() {
        let md = "See ![alt text](image.png) below"
        let result = MDTextExtractor.stripMarkdown(md)
        #expect(result.contains("See"))
        #expect(result.contains("below"))
        #expect(!result.contains("image.png"))
    }

    @Test func stripsInlineCode() {
        let md = "Use `println` to print"
        let result = MDTextExtractor.stripMarkdown(md)
        #expect(result.contains("println"))
        #expect(!result.contains("`"))
    }

    @Test func stripsCodeBlocks() {
        let md = "Before\n\n```swift\nlet x = 1\n```\n\nAfter"
        let result = MDTextExtractor.stripMarkdown(md)
        #expect(result.contains("Before"))
        #expect(result.contains("After"))
        // Code block content may or may not be included, but fences should be gone
        #expect(!result.contains("```"))
    }

    @Test func stripsBlockquotes() {
        let md = "> This is a quote\n> continued"
        let result = MDTextExtractor.stripMarkdown(md)
        #expect(result.contains("This is a quote"))
        #expect(!result.hasPrefix(">"))
    }

    @Test func stripsListMarkers() {
        let md = "- Item one\n- Item two\n1. Numbered"
        let result = MDTextExtractor.stripMarkdown(md)
        #expect(result.contains("Item one"))
        #expect(result.contains("Item two"))
        #expect(result.contains("Numbered"))
    }

    @Test func stripsHorizontalRules() {
        let md = "Above\n\n---\n\nBelow"
        let result = MDTextExtractor.stripMarkdown(md)
        #expect(result.contains("Above"))
        #expect(result.contains("Below"))
        #expect(!result.contains("---"))
    }

    @Test func handlesEmptyInput() {
        let result = MDTextExtractor.stripMarkdown("")
        #expect(result.isEmpty)
    }

    @Test func handlesPlainText() {
        let result = MDTextExtractor.stripMarkdown("No markdown here")
        #expect(result == "No markdown here")
    }

    // MARK: - TextUnit Generation (via SearchTextExtractor protocol)

    @Test func extractTextUnitsFromFile() async throws {
        let md = "# Title\n\nFirst paragraph.\n\nSecond paragraph."
        let tmpDir = FileManager.default.temporaryDirectory
        let fileURL = tmpDir.appendingPathComponent("test-\(UUID().uuidString).md")
        try md.write(to: fileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let extractor = MDTextExtractor()
        let fp = DocumentFingerprint(
            contentSHA256: "a" + String(repeating: "0", count: 63),
            fileByteCount: Int64(md.utf8.count),
            format: .md
        )
        let units = try await extractor.extractTextUnits(from: fileURL, fingerprint: fp)

        #expect(!units.isEmpty)
        // Should have segments from paragraph splitting
        #expect(units.allSatisfy { $0.sourceUnitId.hasPrefix("md:segment:") })
    }

    @Test func extractWithOffsetsProducesValidOffsets() {
        let md = "# Title\n\nFirst paragraph.\n\nSecond paragraph."
        let extractor = MDTextExtractor()
        let result = extractor.extractWithOffsets(from: md)

        #expect(!result.textUnits.isEmpty)
        #expect(!result.segmentBaseOffsets.isEmpty)
        // First segment should start at offset 0
        #expect(result.segmentBaseOffsets[0] == 0)
    }

    @Test func extractCJKMarkdown() {
        let md = "# 标题\n\n这是**粗体**和*斜体*文本"
        let result = MDTextExtractor.stripMarkdown(md)
        #expect(result.contains("标题"))
        #expect(result.contains("粗体"))
        #expect(result.contains("斜体"))
        #expect(!result.contains("**"))
    }

    // MARK: - URL-based extraction with encoding detection

    @Test func extractWithOffsetsFromUTF16File() async throws {
        let md = "# Title\n\nSome **bold** text."
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).md")
        var data = Data([0xFF, 0xFE]) // UTF-16LE BOM
        if let encoded = md.data(using: .utf16LittleEndian) {
            data.append(encoded)
        }
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let extractor = MDTextExtractor()
        let result = try await extractor.extractWithOffsets(from: url)

        #expect(!result.textUnits.isEmpty)
    }
}
