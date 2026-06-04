// Purpose: Feature #91 WI-6c — exhaustively pin the locality + format SAFETY GATE,
// the risk core of get_book_content. Pure decision over (isReadable, format):
// not-local → notLocal; local unsupported (azw3) → unsupportedFormat; local
// EPUB/TXT/MD/PDF → extractable. Locality is checked first (a remote azw3 reports
// notLocal, not unsupportedFormat).
//
// @coordinates-with: GetBookContentGate.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-6c)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #91 WI-6c — GetBookContentGate")
struct GetBookContentGateTests {

    @Test("a local book in a supported format is extractable", arguments: ["epub", "txt", "md", "pdf"])
    func localSupportedExtractable(format: String) {
        #expect(GetBookContentGate.evaluate(isReadable: true, format: format) == .extractable)
    }

    @Test("a local native azw3 book is unsupported (no closed-book text path)")
    func localAzw3Unsupported() {
        #expect(GetBookContentGate.evaluate(isReadable: true, format: "azw3") == .unsupportedFormat)
    }

    @Test("a non-local book is notLocal regardless of format", arguments: ["epub", "txt", "md", "pdf", "azw3"])
    func nonLocalIsNotLocal(format: String) {
        #expect(GetBookContentGate.evaluate(isReadable: false, format: format) == .notLocal)
    }

    @Test("locality is checked FIRST: a remote azw3 reports notLocal, not unsupportedFormat")
    func localityBeforeFormat() {
        #expect(GetBookContentGate.evaluate(isReadable: false, format: "azw3") == .notLocal)
    }

    @Test("supported-format predicate covers exactly epub/txt/md/pdf")
    func supportedFormats() {
        for f in ["epub", "txt", "md", "pdf"] { #expect(GetBookContentGate.isSupportedFormat(f)) }
        for f in ["azw3", "mobi", "prc", "cbz", ""] { #expect(!GetBookContentGate.isSupportedFormat(f)) }
    }
}
