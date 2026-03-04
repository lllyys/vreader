// Purpose: Tests for BookFormat enum — importability, file extensions, Codable round-trip.

import Testing
import Foundation
@testable import vreader

@Suite("BookFormat")
struct BookFormatTests {

    // MARK: - Importability

    @Test func importableFormatsExcludesMarkdown() {
        let importable = BookFormat.importableFormats
        #expect(importable.contains(.epub))
        #expect(importable.contains(.pdf))
        #expect(importable.contains(.txt))
        #expect(!importable.contains(.md))
    }

    @Test func epubIsImportable() {
        #expect(BookFormat.epub.isImportableV1 == true)
    }

    @Test func pdfIsImportable() {
        #expect(BookFormat.pdf.isImportableV1 == true)
    }

    @Test func txtIsImportable() {
        #expect(BookFormat.txt.isImportableV1 == true)
    }

    @Test func mdIsNotImportable() {
        #expect(BookFormat.md.isImportableV1 == false)
    }

    // MARK: - File Extensions

    @Test func epubFileExtensions() {
        #expect(BookFormat.epub.fileExtensions == ["epub"])
    }

    @Test func pdfFileExtensions() {
        #expect(BookFormat.pdf.fileExtensions == ["pdf"])
    }

    @Test func txtFileExtensions() {
        #expect(BookFormat.txt.fileExtensions.contains("txt"))
        #expect(BookFormat.txt.fileExtensions.contains("text"))
    }

    @Test func mdFileExtensions() {
        #expect(BookFormat.md.fileExtensions.contains("md"))
        #expect(BookFormat.md.fileExtensions.contains("markdown"))
    }

    // MARK: - CaseIterable

    @Test func allCasesContainsFourFormats() {
        #expect(BookFormat.allCases.count == 4)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        for format in BookFormat.allCases {
            let data = try JSONEncoder().encode(format)
            let decoded = try JSONDecoder().decode(BookFormat.self, from: data)
            #expect(decoded == format)
        }
    }

    @Test func rawValueRoundTrip() {
        for format in BookFormat.allCases {
            let raw = format.rawValue
            let restored = BookFormat(rawValue: raw)
            #expect(restored == format)
        }
    }

    // MARK: - Edge Cases

    @Test func invalidRawValueReturnsNil() {
        #expect(BookFormat(rawValue: "docx") == nil)
        #expect(BookFormat(rawValue: "") == nil)
        #expect(BookFormat(rawValue: "EPUB") == nil)  // Case-sensitive
    }
}
