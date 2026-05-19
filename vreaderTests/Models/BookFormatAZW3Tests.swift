// Purpose: Tests for BookFormat.azw3 — raw value, file extensions, importability,
// FormatCapabilities, and integration with importableFormats / CaseIterable.

import Testing
import Foundation
@testable import vreader

@Suite("BookFormat.azw3")
struct BookFormatAZW3Tests {

    // MARK: - Raw Value

    @Test("azw3 raw value is 'azw3'")
    func rawValueIsAZW3() {
        #expect(BookFormat.azw3.rawValue == "azw3")
    }

    // MARK: - File Extensions

    @Test("fileExtensions contains 'azw3'")
    func fileExtensionsContainsAZW3() {
        #expect(BookFormat.azw3.fileExtensions.contains("azw3"))
    }

    @Test("fileExtensions contains 'azw'")
    func fileExtensionsContainsAZW() {
        #expect(BookFormat.azw3.fileExtensions.contains("azw"))
    }

    @Test("fileExtensions contains 'mobi'")
    func fileExtensionsContainsMOBI() {
        #expect(BookFormat.azw3.fileExtensions.contains("mobi"))
    }

    @Test("fileExtensions contains 'prc'")
    func fileExtensionsContainsPRC() {
        #expect(BookFormat.azw3.fileExtensions.contains("prc"))
    }

    @Test("fileExtensions does not contain unrelated extensions")
    func fileExtensionsExcludesUnrelated() {
        let exts = BookFormat.azw3.fileExtensions
        #expect(!exts.contains("epub"))
        #expect(!exts.contains("pdf"))
        #expect(!exts.contains("txt"))
    }

    // MARK: - Importability

    @Test("azw3 is importable")
    func isImportableV1() {
        #expect(BookFormat.azw3.isImportableV1 == true)
    }

    @Test("importableFormats contains azw3")
    func importableFormatsContainsAZW3() {
        #expect(BookFormat.importableFormats.contains(.azw3))
    }

    // MARK: - CaseIterable

    @Test("allCases includes azw3")
    func allCasesIncludesAZW3() {
        #expect(BookFormat.allCases.contains(.azw3))
    }

    @Test("allCases count increases to 5 with azw3")
    func allCasesCountIsFive() {
        #expect(BookFormat.allCases.count == 5)
    }

    // MARK: - Codable Round-Trip

    @Test("azw3 survives JSON encode/decode round-trip")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(BookFormat.azw3)
        let decoded = try JSONDecoder().decode(BookFormat.self, from: data)
        #expect(decoded == .azw3)
    }

    @Test("azw3 raw value round-trip")
    func rawValueRoundTrip() {
        let raw = BookFormat.azw3.rawValue
        let restored = BookFormat(rawValue: raw)
        #expect(restored == .azw3)
    }

    // MARK: - FormatCapabilities

    @Test("azw3 supports textSelection")
    func capabilitiesTextSelection() {
        let caps = FormatCapabilities.capabilities(for: .azw3)
        #expect(caps.contains(.textSelection))
    }

    @Test("azw3 supports highlights")
    func capabilitiesHighlights() {
        let caps = FormatCapabilities.capabilities(for: .azw3)
        #expect(caps.contains(.highlights))
    }

    @Test("azw3 supports tts (Foliate-webview TTS wiring shipped — feature #57)")
    func capabilitiesSupportTTS() {
        // Feature #57 wired the AZW3/MOBI TTS path (whole-book
        // plain-text extraction from the Foliate WKWebView →
        // AVSpeechSynthesizer), so `.tts` is back in
        // `FormatCapabilities.azw3` — reversing the bug #176 / GH #602
        // (PR #644) cap-gate. This BookFormatAZW3Tests assertion
        // exercises the `BookFormat.azw3.capabilities` convenience
        // property — the path through which production view-models
        // and host dispatchers resolve capabilities — so a regression
        // in the convenience wrapper would surface here even if the
        // underlying FormatCapabilities call returned the right set.
        // (History: PR #644 removed `.tts`; bug #200 / GH #737 fixed
        // a stale assertion to match; feature #57 re-adds it.)
        let caps = BookFormat.azw3.capabilities
        #expect(caps.contains(.tts))
    }

    @Test("azw3 supports nativePagination")
    func capabilitiesNativePagination() {
        let caps = FormatCapabilities.capabilities(for: .azw3)
        #expect(caps.contains(.nativePagination))
    }

    @Test("azw3 supports toc")
    func capabilitiesTOC() {
        let caps = FormatCapabilities.capabilities(for: .azw3)
        #expect(caps.contains(.toc))
    }

    @Test("azw3 supports search")
    func capabilitiesSearch() {
        let caps = FormatCapabilities.capabilities(for: .azw3)
        #expect(caps.contains(.search))
    }

    @Test("azw3 supports bookmarks")
    func capabilitiesBookmarks() {
        let caps = FormatCapabilities.capabilities(for: .azw3)
        #expect(caps.contains(.bookmarks))
    }

    @Test("azw3 supports annotations")
    func capabilitiesAnnotations() {
        let caps = FormatCapabilities.capabilities(for: .azw3)
        #expect(caps.contains(.annotations))
    }

    // MARK: - FormatCapabilities Boundary / Negative

    @Test("azw3 capabilities match EPUB simple capabilities")
    func capabilitiesMatchSimpleEPUB() {
        // Feature #57: with `.tts` re-added to AZW3 (the bug #176 /
        // GH #602 cap-gate reversed once the Foliate-webview TTS path
        // was wired), AZW3's capability set now equals EPUB-simple's
        // directly — both support `.tts` because both have a wired
        // TTS path. (Pre-#57 the documented diff was exactly `.tts`,
        // per bug #200 / GH #737; feature #57 closes that diff.)
        let azw3Caps = FormatCapabilities.capabilities(for: .azw3)
        let epubCaps = FormatCapabilities.capabilities(for: .epub, isComplexEPUB: false)
        #expect(azw3Caps == epubCaps,
                "azw3 capability set must equal EPUB-simple's set (both include .tts post-#57)")
        #expect(azw3Caps.contains(.tts),
                "azw3 includes .tts — feature #57 wired the Foliate-webview TTS path")
    }

    @Test("isComplexEPUB parameter is ignored for azw3")
    func isComplexEPUBIgnoredForAZW3() {
        let normal = FormatCapabilities.capabilities(for: .azw3, isComplexEPUB: false)
        let complex = FormatCapabilities.capabilities(for: .azw3, isComplexEPUB: true)
        #expect(normal == complex)
    }

    @Test("azw3 convenience property matches direct factory call")
    func conveniencePropertyMatchesFactory() {
        let convenience = BookFormat.azw3.capabilities
        let direct = FormatCapabilities.capabilities(for: .azw3)
        #expect(convenience == direct)
    }

    // MARK: - Universal capabilities still hold with azw3 added

    @Test("all formats (including azw3) support search")
    func allFormatsSupportSearch() {
        for format in BookFormat.allCases {
            let caps = FormatCapabilities.capabilities(for: format)
            #expect(caps.contains(.search), "Expected \(format) to support search")
        }
    }

    @Test("all formats (including azw3) support bookmarks")
    func allFormatsSupportBookmarks() {
        for format in BookFormat.allCases {
            let caps = FormatCapabilities.capabilities(for: format)
            #expect(caps.contains(.bookmarks), "Expected \(format) to support bookmarks")
        }
    }
}
