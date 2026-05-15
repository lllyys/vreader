// Purpose: Tests for BookFormat.isSupportedExtension (Feature #59 WI-2).
// Verifies the case-insensitive extension matching used by FileURLImportRouter
// to decide whether an incoming `file://` URL corresponds to an importable
// book format.

import Testing
import Foundation
@testable import vreader

@Suite("Feature #59 — BookFormat.isSupportedExtension")
struct BookFormatIsSupportedExtensionTests {

    @Test(arguments: ["epub", "pdf", "txt", "text", "md", "markdown", "azw3", "azw", "mobi", "prc"])
    func returnsTrueForKnownExtensions(_ ext: String) {
        #expect(BookFormat.isSupportedExtension(ext) == true,
                "'\(ext)' should be reported as supported")
    }

    @Test(arguments: ["EPUB", "PDF", "Txt", "MD", "AZW3", "Mobi"])
    func isCaseInsensitive(_ ext: String) {
        #expect(BookFormat.isSupportedExtension(ext) == true,
                "Case-insensitive match expected for '\(ext)'")
    }

    @Test(arguments: [".epub", ".pdf", ".azw3", "...epub"])
    func stripsLeadingDots(_ ext: String) {
        #expect(BookFormat.isSupportedExtension(ext) == true,
                "Leading dots should be stripped — '\(ext)' should match")
    }

    @Test(arguments: ["zip", "docx", "rtf", "html", "xml", "json", "exe", "epub2", "txtx"])
    func returnsFalseForUnknownExtensions(_ ext: String) {
        #expect(BookFormat.isSupportedExtension(ext) == false,
                "'\(ext)' should NOT be reported as supported")
    }

    @Test func returnsFalseForEmptyString() {
        #expect(BookFormat.isSupportedExtension("") == false)
    }

    @Test func returnsFalseForJustDots() {
        #expect(BookFormat.isSupportedExtension(".") == false)
        #expect(BookFormat.isSupportedExtension("...") == false)
    }
}
