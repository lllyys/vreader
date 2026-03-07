// Purpose: Tests for EPUBTextExtractor — HTML stripping, spine iteration,
// edge cases (empty content, script/style removal, nested tags).

import Testing
import Foundation
@testable import vreader

@Suite("EPUBTextExtractor")
struct EPUBTextExtractorTests {

    // MARK: - HTML Stripping

    @Test func stripsSimpleHTMLTags() {
        let html = "<p>Hello <b>world</b></p>"
        let result = EPUBTextExtractor.stripHTML(html)
        #expect(result == "Hello world")
    }

    @Test func stripsNestedTags() {
        let html = "<div><p>First <em>paragraph</em></p><p>Second paragraph</p></div>"
        let result = EPUBTextExtractor.stripHTML(html)
        #expect(result.contains("First paragraph"))
        #expect(result.contains("Second paragraph"))
    }

    @Test func removesScriptAndStyleContent() {
        let html = """
        <html><head><style>body { color: red; }</style></head>
        <body><p>Visible text</p><script>alert('hi')</script></body></html>
        """
        let result = EPUBTextExtractor.stripHTML(html)
        #expect(result.contains("Visible text"))
        #expect(!result.contains("color"))
        #expect(!result.contains("alert"))
    }

    @Test func decodesHTMLEntities() {
        let html = "<p>Tom &amp; Jerry &lt;3&gt; &quot;friends&quot;</p>"
        let result = EPUBTextExtractor.stripHTML(html)
        #expect(result.contains("Tom & Jerry"))
        #expect(result.contains("<3>"))
        #expect(result.contains("\"friends\""))
    }

    @Test func handlesEmptyHTML() {
        let result = EPUBTextExtractor.stripHTML("")
        #expect(result.isEmpty)
    }

    @Test func handlesPlainTextInput() {
        let result = EPUBTextExtractor.stripHTML("No tags here")
        #expect(result == "No tags here")
    }

    @Test func collapsesWhitespace() {
        let html = "<p>  Multiple   spaces   and\n\nnewlines  </p>"
        let result = EPUBTextExtractor.stripHTML(html)
        // Should not have runs of multiple spaces
        #expect(!result.contains("  "))
    }

    @Test func handlesCJKContent() {
        let html = "<p>这是<ruby>汉字<rt>hànzì</rt></ruby>测试</p>"
        let result = EPUBTextExtractor.stripHTML(html)
        #expect(result.contains("这是"))
        #expect(result.contains("测试"))
    }

    // MARK: - TextUnit Generation

    @Test func extractFromSpineItems() async throws {
        let parser = MockEPUBParserForExtractor(spineContent: [
            "chapter1.xhtml": "<p>Chapter one content</p>",
            "chapter2.xhtml": "<p>Chapter two content</p>",
        ], spineOrder: ["chapter1.xhtml", "chapter2.xhtml"])

        let metadata = try await parser.open(url: URL(fileURLWithPath: "/tmp/test.epub"))
        let extractor = EPUBTextExtractor()
        let units = try await extractor.extractFromParser(parser, metadata: metadata)

        #expect(units.count == 2)
        #expect(units[0].sourceUnitId == "epub:chapter1.xhtml")
        #expect(units[0].text.contains("Chapter one content"))
        #expect(units[1].sourceUnitId == "epub:chapter2.xhtml")
        #expect(units[1].text.contains("Chapter two content"))
    }

    @Test func skipsEmptySpineItems() async throws {
        let parser = MockEPUBParserForExtractor(spineContent: [
            "chapter1.xhtml": "<p>Has content</p>",
            "chapter2.xhtml": "<html><body></body></html>",
            "chapter3.xhtml": "<p>Also has content</p>",
        ], spineOrder: ["chapter1.xhtml", "chapter2.xhtml", "chapter3.xhtml"])

        let metadata = try await parser.open(url: URL(fileURLWithPath: "/tmp/test.epub"))
        let extractor = EPUBTextExtractor()
        let units = try await extractor.extractFromParser(parser, metadata: metadata)

        // Empty spine items should be skipped
        #expect(units.count == 2)
        #expect(units[0].sourceUnitId == "epub:chapter1.xhtml")
        #expect(units[1].sourceUnitId == "epub:chapter3.xhtml")
    }

    @Test func handlesParserError() async throws {
        let parser = MockEPUBParserForExtractor(
            spineContent: [:],
            spineOrder: ["missing.xhtml"],
            shouldThrow: true
        )

        let metadata = try await parser.open(url: URL(fileURLWithPath: "/tmp/test.epub"))
        let extractor = EPUBTextExtractor()
        let units = try await extractor.extractFromParser(parser, metadata: metadata)

        // Should skip errored items gracefully
        #expect(units.isEmpty)
    }
}

// MARK: - Mock Parser

/// Minimal mock for testing text extraction without real EPUB files.
actor MockEPUBParserForExtractor: EPUBParserProtocol {
    let spineContent: [String: String]
    let spineOrder: [String]
    let shouldThrow: Bool
    private var _isOpen = false

    var isOpen: Bool { _isOpen }

    init(spineContent: [String: String], spineOrder: [String], shouldThrow: Bool = false) {
        self.spineContent = spineContent
        self.spineOrder = spineOrder
        self.shouldThrow = shouldThrow
    }

    func open(url: URL) async throws -> EPUBMetadata {
        _isOpen = true
        let items = spineOrder.enumerated().map { index, href in
            EPUBSpineItem(id: "item\(index)", href: href, title: nil, index: index)
        }
        return EPUBMetadata(
            title: "Test Book",
            author: nil,
            language: "en",
            readingDirection: .ltr,
            layout: .reflowable,
            spineItems: items
        )
    }

    func close() async { _isOpen = false }

    func contentForSpineItem(href: String) async throws -> String {
        if shouldThrow { throw EPUBParserError.resourceNotFound(href) }
        return spineContent[href] ?? ""
    }

    func resourceBaseURL() async throws -> URL {
        URL(fileURLWithPath: "/tmp/test-epub")
    }

    func extractedRootURL() async throws -> URL {
        URL(fileURLWithPath: "/tmp/test-epub")
    }
}
