// Purpose: Feature #56 WI-9 — registry of the 9 bilingual target
// languages the setup sheet, pill, and `PerBookSettings`
// (`bilingualTargetLanguage`) all key off. Pinned to the design
// bundle's `BILINGUAL_LANGS` so visual + persisted artifacts stay in
// lockstep with `vreader-bilingual.jsx`.
//
// Key decisions:
// - **Value type, not enum.** A `case` per language would require the
//   raw `String` form persisted by `PerBookSettings` to map back to
//   the enum on every read; carrying the canonical string is the
//   simpler shape and matches the design's `{ k, glyph, script }`
//   record. `find(key:)` / `findOrDefault(key:)` give the lookup
//   surface — the rest of the app already treats target language as
//   a `String` (BilingualReadingViewModel, ChapterTranslation cache).
// - **`Script` is a nested enum** — small, finite, lets the setup
//   sheet pick the right font family (CJK fonts are different from
//   Latin, RTL languages need direction handling) without baking the
//   font choice into the model.
// - **`findOrDefault` falls back to the first entry** matching the
//   design's `BILINGUAL_LANGS[0]` fallback — a per-book file from an
//   older release that carries a removed-language key still renders.
//
// Design source:
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx`
//   — `BILINGUAL_LANGS` (9 entries, in this order).
//
// @coordinates-with: BilingualSetupSheet.swift, BilingualPill.swift,
//   PerBookSettings.swift (`bilingualTargetLanguage`),
//   BilingualReadingViewModel.swift

import Foundation

/// One target language the user can pick for bilingual reading.
struct BilingualLanguage: Equatable, Sendable, Hashable {

    /// Canonical key persisted in `PerBookSettings.bilingualTargetLanguage`
    /// and read by the translation service. Pinned to the design's
    /// `BILINGUAL_LANGS[].k` values.
    let key: String

    /// Single-character (or two-letter) glyph drawn inside the picker
    /// chip and the reader-chrome pill. Mirrors the design's
    /// `BILINGUAL_LANGS[].glyph`.
    let glyph: String

    /// Script family — drives the picker's font-family choice and the
    /// pill's RTL flag.
    let script: Script

    /// Script family — a finite small set, kept locally.
    enum Script: String, Sendable, Hashable {
        case cjk      // Chinese / Japanese / Korean — Songti SC / Source Han Serif.
        case latin    // Spanish / French / German / Italian — body serif.
        case rtl      // Arabic — right-to-left.
        case cyrillic // Russian — body serif.
    }

    /// The 9 supported target languages, in design order.
    ///
    /// Pinned by `BilingualLanguageTests`; a reorder or a removed
    /// case fails that suite before this file's consumers compile.
    static let all: [BilingualLanguage] = [
        BilingualLanguage(key: "Chinese",  glyph: "中", script: .cjk),
        BilingualLanguage(key: "Japanese", glyph: "日", script: .cjk),
        BilingualLanguage(key: "Korean",   glyph: "한", script: .cjk),
        BilingualLanguage(key: "Spanish",  glyph: "Es", script: .latin),
        BilingualLanguage(key: "French",   glyph: "Fr", script: .latin),
        BilingualLanguage(key: "German",   glyph: "De", script: .latin),
        BilingualLanguage(key: "Italian",  glyph: "It", script: .latin),
        BilingualLanguage(key: "Arabic",   glyph: "ع",  script: .rtl),
        BilingualLanguage(key: "Russian",  glyph: "Ru", script: .cyrillic),
    ]

    /// Returns the language for the canonical key, or `nil` if the key
    /// is not in the registry.
    static func find(key: String) -> BilingualLanguage? {
        all.first { $0.key == key }
    }

    /// Returns the language for the canonical key, falling back to the
    /// first registered language (`Chinese`) when the key is unknown.
    /// The design's `BILINGUAL_LANGS.find(...) || BILINGUAL_LANGS[0]`
    /// pattern — a stale persisted key from an older release still
    /// renders something instead of a blank slot.
    static func findOrDefault(key: String) -> BilingualLanguage {
        find(key: key) ?? all[0]
    }
}
