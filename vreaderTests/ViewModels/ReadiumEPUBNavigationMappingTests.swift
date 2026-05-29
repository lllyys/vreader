// Purpose: Feature #42 Phase 1 WI-9a — unit tests for the pure vreader-`Locator`
// → Readium-`Locator` navigation mapping that drives search/TOC/bookmark jumps
// in the Readium EPUB host. Pure mapping — no render — so it pins href
// resolution against the publication spine (reusing WI-8's `resolveHref`),
// progression + text-quote carry-through, CJK quotes, and the nil-href guard.
//
// The async nav DISPATCH (host `.onReceive` → commander → navigator
// `go(to:)`/`goForward`/`goBackward`) is exercised by device verification, not
// here — `EPUBNavigatorViewController` is concrete and has no protocol seam, so
// the nav call is verified end-to-end. This file pins the deterministic seam.
//
// @coordinates-with vreader/ViewModels/ReadiumEPUBReaderViewModel+Navigation.swift,
//   vreader/Services/Reader/ReadiumDecorationHighlightAdapter.swift,
//   vreader/Models/Locator.swift

import Testing
import Foundation
import ReadiumShared
@testable import vreader

@Suite("ReadiumEPUBReaderViewModel navigation mapping (WI-9a)")
struct ReadiumEPUBNavigationMappingTests {

    // MARK: - Fixtures

    private func fingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: String(repeating: "f", count: 64),
            fileByteCount: 4096,
            format: .epub
        )
    }

    private func vLocator(
        href: String? = "chapter1.xhtml",
        progression: Double? = 0.5,
        quote: String? = nil,
        before: String? = nil,
        after: String? = nil
    ) -> vreader.Locator {
        vreader.Locator(
            bookFingerprint: fingerprint(),
            href: href, progression: progression, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: nil, charRangeStartUTF16: nil,
            charRangeEndUTF16: nil,
            textQuote: quote, textContextBefore: before, textContextAfter: after
        )
    }

    // MARK: - Core mapping

    @Test func maps_href_progression_andExactSpineMatch() throws {
        let loc = vLocator(href: "OEBPS/chapter1.xhtml", progression: 0.42)
        let r = try #require(ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: loc, spineHrefs: ["OEBPS/chapter1.xhtml", "OEBPS/chapter2.xhtml"]
        ))
        #expect(r.href.string == "OEBPS/chapter1.xhtml")
        #expect(r.locations.progression == 0.42)
    }

    @Test func resolves_legacyHref_againstContainerRelativeSpine() throws {
        // Legacy OPF-relative href resolves to Readium's container-relative form
        // via the shared `resolveHref` (suffix-unique branch) — same migration
        // concern WI-8 handles for highlights.
        let loc = vLocator(href: "chapter1.xhtml", progression: 0.1)
        let r = try #require(ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: loc, spineHrefs: ["OEBPS/chapter1.xhtml", "OEBPS/chapter2.xhtml"]
        ))
        #expect(r.href.string == "OEBPS/chapter1.xhtml")
    }

    @Test func carriesTextQuote_andContext_forSearchResult() throws {
        let loc = vLocator(
            href: "ch3.xhtml", progression: 0.7,
            quote: "the matched phrase",
            before: "before ", after: " after"
        )
        let r = try #require(ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: loc, spineHrefs: ["ch3.xhtml"]
        ))
        #expect(r.text.highlight == "the matched phrase")
        #expect(r.text.before == "before ")
        #expect(r.text.after == " after")
    }

    @Test func cjkTextQuote_survivesMapping() throws {
        let loc = vLocator(href: "ch1.xhtml", progression: 0.3, quote: "被讨厌的勇气")
        let r = try #require(ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: loc, spineHrefs: ["ch1.xhtml"]
        ))
        #expect(r.text.highlight == "被讨厌的勇气")
    }

    @Test func nilProgression_mapsToNilLocations() throws {
        let loc = vLocator(href: "ch1.xhtml", progression: nil)
        let r = try #require(ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: loc, spineHrefs: ["ch1.xhtml"]
        ))
        #expect(r.locations.progression == nil)
    }

    @Test func nilHref_returnsNil() {
        let loc = vLocator(href: nil, progression: 0.5)
        #expect(ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: loc, spineHrefs: ["ch1.xhtml"]
        ) == nil)
    }

    @Test func emptyHref_returnsNil() {
        let loc = vLocator(href: "", progression: 0.5)
        #expect(ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: loc, spineHrefs: ["ch1.xhtml"]
        ) == nil)
    }

    @Test func unresolvableLegacyHref_fallsBackToRawHref() throws {
        // No spine match — fall back to the raw stored href (mirrors WI-8's
        // decoration fallback), so an EPUB whose stored href already matches
        // Readium's form, or a publication we couldn't resolve against, still
        // builds a usable locator rather than dropping the jump.
        let loc = vLocator(href: "unknown.xhtml", progression: 0.2)
        let r = try #require(ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: loc, spineHrefs: ["OEBPS/chapter1.xhtml"]
        ))
        #expect(r.href.string == "unknown.xhtml")
    }

    @Test func emptySpine_keepsRawHref() throws {
        let loc = vLocator(href: "chapter1.xhtml", progression: 0.9)
        let r = try #require(ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: loc, spineHrefs: []
        ))
        #expect(r.href.string == "chapter1.xhtml")
    }
}
