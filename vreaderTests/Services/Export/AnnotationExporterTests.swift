// Purpose: Tests for AnnotationExporter — payload building, dispatch, shared edge
// cases (empty, Unicode, CJK, long text) — plus direct-payload suites for
// MarkdownExportFormatter (ordering, rendering, nil branches) and
// JSONExportFormatter (ISO-8601, determinism, round-trip).
//
// @coordinates-with: AnnotationExporter.swift, ExportedAnnotation.swift,
//   MarkdownExportFormatter.swift, JSONExportFormatter.swift, ExportTestFixtures.swift

import Testing
import Foundation
@testable import vreader

private typealias F = ExportTestFixtures

@Suite("AnnotationExporter")
struct AnnotationExporterTests {

    // MARK: - buildPayload

    @Test func buildPayload_mixedTypes_allPresent() {
        let h = F.makeHighlight(text: "hl")
        let b = F.makeBookmark(title: "bm")
        let n = F.makeAnnotation(content: "note")

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [b], notes: [n],
            bookTitle: "Mixed", bookAuthor: nil
        )

        #expect(payload.annotations.count == 3)
        let types = Set(payload.annotations.map(\.type))
        #expect(types.contains(.highlight))
        #expect(types.contains(.bookmark))
        #expect(types.contains(.note))
    }

    @Test func buildPayload_chapterMapping() {
        let h = F.makeHighlight(href: "chapter1.xhtml", text: "mapped")
        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [],
            bookTitle: "T", bookAuthor: nil,
            chapterMap: F.chapterMap
        )
        #expect(payload.annotations[0].chapter == "Chapter 1: Introduction")
    }

    @Test func buildPayload_noChapter_nilChapter() {
        let h = F.makeHighlight(href: nil, text: "no chapter")
        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [],
            bookTitle: "T", bookAuthor: nil
        )
        #expect(payload.annotations[0].chapter == nil)
    }

    // MARK: - Dispatch

    @Test func export_dispatchToCorrectFormatter() throws {
        let payload = AnnotationExporter.buildPayload(
            highlights: [F.makeHighlight()], bookmarks: [], notes: [],
            bookTitle: "Dispatch Test", bookAuthor: nil
        )

        let mdData = try AnnotationExporter.export(payload: payload, format: .markdown)
        let md = String(data: mdData, encoding: .utf8)!
        #expect(md.contains("# Dispatch Test"))

        let jsonData = try AnnotationExporter.export(payload: payload, format: .json)
        let json = String(data: jsonData, encoding: .utf8)!
        #expect(json.contains("\"bookTitle\""))
    }

    // MARK: - ExportFormat Codable

    @Test func exportFormat_enum_codable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for format in ExportFormat.allCases {
            let data = try encoder.encode(format)
            let decoded = try decoder.decode(ExportFormat.self, from: data)
            #expect(decoded == format)
        }
    }

    // MARK: - Empty Annotations

    @Test func emptyAnnotations_producesMinimalOutput() throws {
        let payload = AnnotationExporter.buildPayload(
            highlights: [], bookmarks: [], notes: [],
            bookTitle: "Empty Book", bookAuthor: nil
        )

        // Markdown: minimal
        let mdData = try MarkdownExportFormatter().format(payload)
        let md = String(data: mdData, encoding: .utf8)!
        #expect(md.contains("# Empty Book"))
        #expect(md.contains("*No annotations.*"))

        // JSON: empty array
        let jsonData = try JSONExportFormatter().format(payload)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(AnnotationExportPayload.self, from: jsonData)
        #expect(decoded.annotations.isEmpty)
    }

    // MARK: - Unicode

    @Test func unicodeContent_preserved() throws {
        let h = F.makeHighlight(text: "Caf\u{0301}e resum\u{0301}e na\u{00EF}ve")
        let n = F.makeAnnotation(content: "Notes with emoji: \u{1F4DA}\u{2728}")

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [n],
            bookTitle: "Unicode \u{1F30D} Book", bookAuthor: nil
        )

        // Markdown preserves
        let mdData = try MarkdownExportFormatter().format(payload)
        let md = String(data: mdData, encoding: .utf8)!
        #expect(md.contains("Caf\u{0301}e"))
        #expect(md.contains("\u{1F4DA}"))

        // JSON round-trip preserves
        let jsonData = try JSONExportFormatter().format(payload)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(AnnotationExportPayload.self, from: jsonData)
        let hl = decoded.annotations.first { $0.type == .highlight }
        #expect(hl?.selectedText == "Caf\u{0301}e resum\u{0301}e na\u{00EF}ve")
    }

    // MARK: - CJK

    @Test func cjkText_correct() throws {
        let h = F.makeHighlight(text: "\u{4E16}\u{754C}\u{4F60}\u{597D}")
        let n = F.makeAnnotation(content: "\u{65E5}\u{672C}\u{8A9E}\u{306E}\u{30CE}\u{30FC}\u{30C8}")

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [n],
            bookTitle: "\u{4E2D}\u{6587}\u{4E66}\u{7C4D}",
            bookAuthor: "\u{4F5C}\u{8005}\u{540D}"
        )

        let mdData = try MarkdownExportFormatter().format(payload)
        let md = String(data: mdData, encoding: .utf8)!
        #expect(md.contains("\u{4E16}\u{754C}\u{4F60}\u{597D}"))
        #expect(md.contains("# \u{4E2D}\u{6587}\u{4E66}\u{7C4D}"))

        let jsonData = try JSONExportFormatter().format(payload)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(AnnotationExportPayload.self, from: jsonData)
        #expect(decoded.bookTitle == "\u{4E2D}\u{6587}\u{4E66}\u{7C4D}")
        #expect(decoded.bookAuthor == "\u{4F5C}\u{8005}\u{540D}")
    }

    // MARK: - Long Text

    @Test func longNote_notTruncated() throws {
        let longText = String(repeating: "This is a very long sentence. ", count: 100)
        let h = F.makeHighlight(text: longText, note: longText)

        let payload = AnnotationExporter.buildPayload(
            highlights: [h], bookmarks: [], notes: [],
            bookTitle: "Long Note Book", bookAuthor: nil
        )

        let mdData = try MarkdownExportFormatter().format(payload)
        let md = String(data: mdData, encoding: .utf8)!
        #expect(md.contains(longText))

        let jsonData = try JSONExportFormatter().format(payload)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let decoded = try dec.decode(AnnotationExportPayload.self, from: jsonData)
        #expect(decoded.annotations[0].selectedText == longText)
        #expect(decoded.annotations[0].note == longText)
    }
}

/// Direct-payload helper for the formatter suites below.
private func makeExported(
    type: ExportedAnnotationType, chapter: String? = nil,
    selectedText: String? = nil, note: String? = nil, title: String? = nil
) -> ExportedAnnotation {
    ExportedAnnotation(id: UUID(), type: type, chapter: chapter, selectedText: selectedText,
                       note: note, color: nil, title: title,
                       createdAt: F.fixedDate, updatedAt: F.fixedDate)
}

@Suite("MarkdownExportFormatter direct")
struct MarkdownExportFormatterTests {

    private func md(
        _ annotations: [ExportedAnnotation], title: String = "T", author: String? = nil
    ) throws -> String {
        let payload = AnnotationExportPayload(bookTitle: title, bookAuthor: author,
                                              exportedAt: F.fixedDate, annotations: annotations)
        return String(data: try MarkdownExportFormatter().format(payload), encoding: .utf8)!
    }

    @Test func chapters_sortAlphabetically_cjkIncluded_ungroupedLast() throws {
        let out = try md([
            makeExported(type: .highlight, chapter: nil, selectedText: "orphan"),
            makeExported(type: .highlight, chapter: "\u{7B2C}\u{4E8C}\u{7AE0}", selectedText: "later"),
            makeExported(type: .highlight, chapter: "Alpha", selectedText: "first"),
            makeExported(type: .highlight, chapter: "\u{7B2C}\u{4E00}\u{7AE0}", selectedText: "mid"),
        ])
        let alpha = try #require(out.range(of: "## Alpha"))
        let cjk1 = try #require(out.range(of: "## \u{7B2C}\u{4E00}\u{7AE0}"))
        let cjk2 = try #require(out.range(of: "## \u{7B2C}\u{4E8C}\u{7AE0}"))
        let ungrouped = try #require(out.range(of: "## Ungrouped"))
        #expect(alpha.lowerBound < cjk1.lowerBound)
        #expect(cjk1.lowerBound < cjk2.lowerBound)
        #expect(cjk2.lowerBound < ungrouped.lowerBound)
    }

    @Test func fullDocument_exactShape() throws {
        let out = try md([makeExported(type: .highlight, chapter: "C", selectedText: "x", note: "n")],
                         title: "T", author: "A")
        #expect(out == "# T\n*by A*\n\n## C\n\n> x\n\n*Note: n*\n")
    }

    @Test func mixedTypes_renderInPayloadOrderWithinChapter() throws {
        let out = try md([
            makeExported(type: .highlight, chapter: "C", selectedText: "hl-text"),
            makeExported(type: .bookmark, chapter: "C", title: "bm-title"),
            makeExported(type: .note, chapter: "C", note: "note-text"),
        ])
        let h = try #require(out.range(of: "> hl-text"))
        let b = try #require(out.range(of: "- bm-title"))
        let n = try #require(out.range(of: "*Note: note-text*"))
        #expect(h.lowerBound < b.lowerBound)
        #expect(b.lowerBound < n.lowerBound)
    }

    // A highlight with nil selectedText/note and a note with nil note emit no lines.
    @Test func nilContentItems_renderNothing() throws {
        let out = try md([
            makeExported(type: .highlight, chapter: "C"),
            makeExported(type: .note, chapter: "C"),
        ])
        #expect(out.contains("## C"))
        #expect(!out.contains(">"))
        #expect(!out.contains("*Note:"))
    }

    @Test func markdownSpecialCharacters_inSelectedText_passThroughUnescaped() throws {
        let tricky = "**bold** _it_ `code` # heading [x](y) > quote"
        let out = try md([makeExported(type: .highlight, chapter: "C", selectedText: tricky)])
        #expect(out.contains("> \(tricky)"))
    }
}

@Suite("JSONExportFormatter direct")
struct JSONExportFormatterTests {

    private static let epoch = Date(timeIntervalSince1970: 0)

    private func makePayload() -> AnnotationExportPayload {
        AnnotationExportPayload(bookTitle: "T", bookAuthor: "A", exportedAt: Self.epoch,
                                annotations: [makeExported(type: .highlight, chapter: "C",
                                                           selectedText: "x")])
    }

    @Test func allDateFields_encodeAsISO8601() throws {
        let json = String(data: try JSONExportFormatter().format(makePayload()), encoding: .utf8)!
        #expect(json.contains("1970-01-01T00:00:00Z"))  // exportedAt
        #expect(json.contains("2023-11-14T22:13:20Z"))  // createdAt/updatedAt (fixedDate)
    }

    @Test func output_deterministic_sortedKeys_prettyPrinted() throws {
        let payload = makePayload()
        let first = try JSONExportFormatter().format(payload)
        #expect(first == (try JSONExportFormatter().format(payload)))
        let json = String(data: first, encoding: .utf8)!
        #expect(json.contains("\n"))  // pretty-printed
        let annotations = try #require(json.range(of: "\"annotations\""))
        let author = try #require(json.range(of: "\"bookAuthor\""))
        let title = try #require(json.range(of: "\"bookTitle\""))
        let exported = try #require(json.range(of: "\"exportedAt\""))
        #expect(annotations.lowerBound < author.lowerBound)
        #expect(author.lowerBound < title.lowerBound)
        #expect(title.lowerBound < exported.lowerBound)
    }

    @Test func nilOptionalFields_roundTripToEqualPayload() throws {
        let sparse = AnnotationExportPayload(
            bookTitle: "T", bookAuthor: nil, exportedAt: Self.epoch,
            annotations: [makeExported(type: .bookmark)]  // every optional nil
        )
        let data = try JSONExportFormatter().format(sparse)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AnnotationExportPayload.self, from: data)
        #expect(decoded == sparse)
    }
}
