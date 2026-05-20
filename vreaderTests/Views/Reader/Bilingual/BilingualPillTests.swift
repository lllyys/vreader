// Purpose: Feature #56 WI-9 — pin `BilingualPill`'s public surface
// (lang → glyph mapping + accessibility identifier). The pill is a
// pure SwiftUI view; its render path stays untested here (no pixel
// snapshotting), but the inputs it consumes and the identifier it
// exposes are part of the contract the chrome layout test +
// XCUITest harnesses bind to.
//
// Design source:
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx`
//   — `BilingualPill`.
//
// @coordinates-with: BilingualPill.swift, BilingualLanguage.swift,
//   ReaderTopChrome.swift, ReaderChromeButton.swift

import Testing
@testable import vreader

@Suite("Feature #56 WI-9 — BilingualPill")
struct BilingualPillTests {

    @Test("Pill exposes the readerBilingualPill accessibility identifier")
    func accessibilityIdentifier() {
        #expect(BilingualPill.accessibilityIdentifier == "readerBilingualPill")
    }

    @Test("Pill resolves a known language to its glyph")
    func knownLanguageGlyph() {
        let pill = BilingualPill(theme: .paper, language: "Chinese")
        #expect(pill.resolvedGlyph == "中")
        #expect(pill.resolvedLanguageKey == "Chinese")
    }

    @Test("Pill falls back to the first language for an unknown key")
    func unknownLanguageFallsBack() {
        // A per-book file from an older release could carry a deleted
        // language; the pill must still render — design's
        // `(BILINGUAL_LANGS.find(...) || BILINGUAL_LANGS[0]).glyph`.
        let pill = BilingualPill(theme: .paper, language: "Klingon")
        #expect(pill.resolvedGlyph == "中")
        #expect(pill.resolvedLanguageKey == "Chinese")
    }

    @Test("Pill source language is always EN per design")
    func sourceLanguageGlyph() {
        // The design pins the source side to `EN` regardless of the
        // book's source language — translation direction is always
        // English → target in the current scope.
        #expect(BilingualPill.sourceLanguageGlyph == "EN")
    }
}
