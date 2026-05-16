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

    @Test("azw3 does NOT support tts until Foliate-webview wiring ships")
    func capabilitiesDoesNotSupportTTSUntilFoliateWiringShips() {
        // Bug #176 / GH #602: PR #644 intentionally removed `.tts`
        // from `FormatCapabilities.azw3` because
        // `ReaderAICoordinator.loadBookTextContent` has no AZW3/MOBI
        // case → silent TTS failure. The canonical regression guard
        // is `azw3_doesNotSupportTTS` in `FormatCapabilitiesTests`,
        // which calls `FormatCapabilities.capabilities(for: .azw3)`
        // directly. This BookFormatAZW3Tests assertion exercises the
        // `BookFormat.azw3.capabilities` convenience property — the
        // path through which production view-models and host
        // dispatchers resolve capabilities — so a regression in the
        // convenience wrapper (e.g., someone re-routing it through a
        // stale default) would surface here even if the underlying
        // FormatCapabilities call still returned the right set.
        // Bug #200 / GH #737 inverted the previous stale assertion
        // (which still expected `.tts` after the PR #644 cap-gate).
        let caps = BookFormat.azw3.capabilities
        #expect(!caps.contains(.tts))
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

    @Test("azw3 capabilities match EPUB simple capabilities except .tts")
    func capabilitiesMatchSimpleEPUBExceptTTS() {
        // Bug #200 / GH #737: PR #644 cap-gated `.tts` off AZW3 only
        // (Bug #176 / GH #602). EPUB still supports `.tts` because
        // its TTS path is wired end-to-end. So the documented diff
        // between the two capability sets is exactly `.tts`. This
        // test asserts that diff explicitly instead of demanding
        // equality, which is the contract that survived PR #644.
        let azw3Caps = FormatCapabilities.capabilities(for: .azw3)
        let epubCaps = FormatCapabilities.capabilities(for: .epub, isComplexEPUB: false)
        #expect(azw3Caps.union(.tts) == epubCaps,
                "azw3 capability set + .tts must equal EPUB-simple's set")
        #expect(!azw3Caps.contains(.tts),
                "azw3 must not include .tts until Foliate-webview wiring ships")
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
