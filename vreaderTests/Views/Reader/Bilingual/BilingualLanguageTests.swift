// Purpose: Feature #56 WI-9 — pin the `BilingualLanguage` registry. The
// setup sheet's target-language picker, the pill's glyph lookup, and
// the persisted `bilingualTargetLanguage` field in `PerBookSettings`
// all key off this list, so any drift (case removed, glyph swapped,
// script flipped) breaks the design contract before it reaches the
// SwiftUI render path.
//
// Design source:
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx`
//   — `BILINGUAL_LANGS` (9 entries).
//
// @coordinates-with: BilingualLanguage.swift, BilingualPill.swift,
//   BilingualSetupSheet.swift

import Testing
@testable import vreader

@Suite("Feature #56 WI-9 — BilingualLanguage registry")
struct BilingualLanguageTests {

    @Test("Registry has exactly 9 entries")
    func registryCount() {
        #expect(BilingualLanguage.all.count == 9)
    }

    @Test("Registry order matches design bundle")
    func registryOrder() {
        // `vreader-bilingual.jsx:BILINGUAL_LANGS` order:
        // Chinese · Japanese · Korean · Spanish · French · German ·
        // Italian · Arabic · Russian.
        #expect(BilingualLanguage.all.map(\.key) == [
            "Chinese", "Japanese", "Korean",
            "Spanish", "French", "German", "Italian",
            "Arabic", "Russian",
        ])
    }

    @Test("Each language carries the designed glyph")
    func designGlyphs() {
        // Pinned from `vreader-bilingual.jsx:BILINGUAL_LANGS`.
        let map: [(key: String, glyph: String)] = [
            ("Chinese",  "中"),
            ("Japanese", "日"),
            ("Korean",   "한"),
            ("Spanish",  "Es"),
            ("French",   "Fr"),
            ("German",   "De"),
            ("Italian",  "It"),
            ("Arabic",   "ع"),
            ("Russian",  "Ru"),
        ]
        for entry in map {
            let lang = BilingualLanguage.find(key: entry.key)
            #expect(lang?.glyph == entry.glyph, "glyph mismatch for \(entry.key)")
        }
    }

    @Test("CJK and RTL scripts are correctly tagged")
    func scriptTagging() {
        #expect(BilingualLanguage.find(key: "Chinese")?.script == .cjk)
        #expect(BilingualLanguage.find(key: "Japanese")?.script == .cjk)
        #expect(BilingualLanguage.find(key: "Korean")?.script == .cjk)
        #expect(BilingualLanguage.find(key: "Spanish")?.script == .latin)
        #expect(BilingualLanguage.find(key: "Arabic")?.script == .rtl)
        #expect(BilingualLanguage.find(key: "Russian")?.script == .cyrillic)
    }

    @Test("find(key:) returns nil for an unknown language")
    func unknownLanguageReturnsNil() {
        #expect(BilingualLanguage.find(key: "Klingon") == nil)
        #expect(BilingualLanguage.find(key: "") == nil)
    }

    @Test("findOrDefault returns the first entry when the key is unknown")
    func findOrDefaultFallsBackToFirst() {
        // The pill needs to render *something* for stale / unknown
        // language strings stored from older releases — the design
        // does this by `(.find(...) || BILINGUAL_LANGS[0]).glyph`.
        let fallback = BilingualLanguage.findOrDefault(key: "Klingon")
        #expect(fallback.key == "Chinese")
        #expect(fallback.glyph == "中")
    }

    @Test("findOrDefault returns the matching entry when the key is known")
    func findOrDefaultMatchesKnownKey() {
        let entry = BilingualLanguage.findOrDefault(key: "Russian")
        #expect(entry.key == "Russian")
        #expect(entry.glyph == "Ru")
    }
}
