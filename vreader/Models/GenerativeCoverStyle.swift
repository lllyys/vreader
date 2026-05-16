// Purpose: Feature #60 visual-identity v2 (WI-10) — the generative
// book-cover style model. A book with no embedded / custom cover image
// is shown a generative typographic cover instead of the old plain
// placeholder; this file pins the 5 style families, the 12 design
// cover palettes, and the deterministic style/palette assignment policy.
//
// Style families, per-style typography, and the 12 cover palettes are
// pinned to the committed design bundle:
//   - `vreader-cover.jsx` (`CoverArt`'s 5 branches — classic / modern /
//     animal / editorial / minimal).
//   - `vreader-data.jsx` (`COVER_PALETTES` — 12 `{bg, ink, accent,
//     style}` quadruples).
//
// Key decisions:
// - **Exhaustive enum, not a free string.** Adding a sixth family is a
//   compiler-enforced churn — every switch over `GenerativeCoverStyle`
//   must be updated. Mirrors `AccentColor` / `NamedHighlightColor`.
// - **Deterministic assignment from `fingerprintKey`.** A given book
//   always gets the same cover. The policy hashes the book's stable
//   `fingerprintKey` (FNV-1a over UTF-8 bytes — a well-distributed,
//   non-seeded hash, so the result is identical across processes,
//   unlike `Swift.Hasher` which is per-process seeded) and reduces it
//   modulo the 12-palette count. Because each design palette carries
//   its own `style`, style and palette co-vary deterministically —
//   exactly the design's `COVER_PALETTES` data shape.
// - **Foundation-only.** No SwiftUI import, so the type compiles in the
//   test target without pulling UI just to assert the family set; the
//   palette stores raw `RGBTriple`s and the view resolves them to
//   `Color`.
//
// @coordinates-with: GenerativeCoverView.swift, BookCoverArtView.swift,
//   TypographySettings.swift (ReaderFontFamily),
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-cover.jsx`,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-data.jsx`

import Foundation

/// One of the 5 generative book-cover style families from the design
/// bundle's `CoverArt` component.
enum GenerativeCoverStyle: String, CaseIterable, Sendable {
    /// Italic serif title, centered hairline rule, uppercase author —
    /// the design's "classic" branch.
    case classic
    /// Heavy Inter title top-left, accent tick + author bottom-left —
    /// the design's "modern" branch.
    case modern
    /// O'Reilly-style — serif title, abstract block, author — the
    /// design's "animal" branch.
    case animal
    /// Uppercase accent author label, large serif title centered on a
    /// 40% baseline, year footer — the design's "editorial" branch.
    case editorial
    /// Centered mark glyph, serif title, sans author — the design's
    /// "minimal" branch.
    case minimal

    /// The title typeface for this style, per `vreader-cover.jsx`:
    /// the design uses `"Inter"` for `modern`, `"Source Serif 4"` for
    /// the other four families.
    var titleFontFamily: ReaderFontFamily {
        switch self {
        case .modern:
            return .inter
        case .classic, .animal, .editorial, .minimal:
            return .sourceSerif4
        }
    }

    /// Deterministically maps a book's `fingerprintKey` to a style
    /// family — the `style` of the palette the key resolves to. The
    /// same key always yields the same style, across processes and
    /// launches. An empty key maps to a fixed family (no crash).
    static func style(forFingerprintKey key: String) -> GenerativeCoverStyle {
        GenerativeCoverPalette.palette(forFingerprintKey: key).style
    }
}

// MARK: - RGB triple

/// An 8-bit-per-channel RGB colour. Foundation-only so the palette
/// type compiles without SwiftUI; `GenerativeCoverView` resolves it to
/// a SwiftUI `Color`.
struct RGBTriple: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int

    /// Parses a `#RRGGBB` or `RRGGBB` hex string. Returns a fixed
    /// fallback (mid-grey) for malformed input so a cover always
    /// renders rather than crashing.
    init(hex: String) {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        // Expand 3-digit shorthand (#abc → #aabbcc) for completeness.
        if trimmed.count == 3 {
            trimmed = trimmed.map { "\($0)\($0)" }.joined()
        }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else {
            self.red = 0x80
            self.green = 0x80
            self.blue = 0x80
            return
        }
        self.red = Int((value >> 16) & 0xff)
        self.green = Int((value >> 8) & 0xff)
        self.blue = Int(value & 0xff)
    }
}

// MARK: - Cover palette

/// A generative-cover colour palette: a `(background, ink, accent)`
/// triple plus the `style` family it pairs with. The 12 instances in
/// `Self.all` are the design bundle's `COVER_PALETTES`.
struct GenerativeCoverPalette: Equatable, Sendable {
    let background: RGBTriple
    let ink: RGBTriple
    let accent: RGBTriple
    let style: GenerativeCoverStyle

    /// The 12 cover palettes from `vreader-data.jsx` `COVER_PALETTES`,
    /// in declaration order. Each pairs a colour triple with its style.
    static let all: [GenerativeCoverPalette] = [
        // prideAndPrejudice
        GenerativeCoverPalette(hexBackground: "#5a3a3a", hexInk: "#f4e9d4", hexAccent: "#c7a45a", style: .classic),
        // beginningInfinity
        GenerativeCoverPalette(hexBackground: "#0e1a2b", hexInk: "#e8e3d4", hexAccent: "#d97b3a", style: .modern),
        // ddia
        GenerativeCoverPalette(hexBackground: "#d6a429", hexInk: "#1a1a1a", hexAccent: "#a76b00", style: .animal),
        // sapiens
        GenerativeCoverPalette(hexBackground: "#e9dccb", hexInk: "#1a1a1a", hexAccent: "#9c2b1f", style: .editorial),
        // meditations
        GenerativeCoverPalette(hexBackground: "#1a1a18", hexInk: "#d8c98a", hexAccent: "#7a6a3c", style: .classic),
        // threeBody
        GenerativeCoverPalette(hexBackground: "#0a0e1c", hexInk: "#d8d2c5", hexAccent: "#7a3a3a", style: .modern),
        // pragmatic
        GenerativeCoverPalette(hexBackground: "#1c3a5f", hexInk: "#f4e9d4", hexAccent: "#d97b3a", style: .editorial),
        // atomicHabits
        GenerativeCoverPalette(hexBackground: "#f4e9d4", hexInk: "#1a1a1a", hexAccent: "#3a6a5a", style: .minimal),
        // selfishGene
        GenerativeCoverPalette(hexBackground: "#2a2a28", hexInk: "#e8e3d4", hexAccent: "#a8804a", style: .minimal),
        // thinkingFastSlow
        GenerativeCoverPalette(hexBackground: "#e6d6b6", hexInk: "#1a1a1a", hexAccent: "#5a3a3a", style: .editorial),
        // walden
        GenerativeCoverPalette(hexBackground: "#2a3a2a", hexInk: "#e8e3d4", hexAccent: "#a8804a", style: .classic),
        // brokenEarth
        GenerativeCoverPalette(hexBackground: "#3a1818", hexInk: "#f4e9d4", hexAccent: "#d97b3a", style: .modern),
    ]

    private init(
        hexBackground: String,
        hexInk: String,
        hexAccent: String,
        style: GenerativeCoverStyle
    ) {
        self.background = RGBTriple(hex: hexBackground)
        self.ink = RGBTriple(hex: hexInk)
        self.accent = RGBTriple(hex: hexAccent)
        self.style = style
    }

    /// Deterministically picks one of the 12 design palettes for a
    /// book's `fingerprintKey`. The same key always resolves to the
    /// same palette — across processes and launches.
    static func paletteIndex(forFingerprintKey key: String) -> Int {
        Int(GenerativeCoverHash.fnv1a(key) % UInt64(all.count))
    }

    /// The design palette this `fingerprintKey` deterministically maps
    /// to. An empty key resolves to a fixed palette (no crash).
    static func palette(forFingerprintKey key: String) -> GenerativeCoverPalette {
        all[paletteIndex(forFingerprintKey: key)]
    }

    /// Picks a palette whose `style` matches `style`, keyed by `seed`
    /// for deterministic test construction. Used by tests + previews
    /// that want a specific style's palette. Falls back to the first
    /// palette if (defensively) no palette carries the style.
    static func palette(
        for style: GenerativeCoverStyle, seed: Int
    ) -> GenerativeCoverPalette {
        let matching = all.filter { $0.style == style }
        guard !matching.isEmpty else { return all[0] }
        let index = ((seed % matching.count) + matching.count) % matching.count
        return matching[index]
    }
}

// MARK: - Deterministic hash

/// FNV-1a 64-bit hash over a string's UTF-8 bytes. Used for the
/// cover-assignment policy because it is *stable* — `Swift.Hasher` is
/// seeded per process so two launches would assign different covers to
/// the same book. FNV-1a is not cryptographic; that is fine here —
/// the only requirement is deterministic, well-spread bucketing.
enum GenerativeCoverHash {
    /// FNV-1a 64-bit offset basis.
    private static let offsetBasis: UInt64 = 0xcbf2_9ce4_8422_2325
    /// FNV-1a 64-bit prime.
    private static let prime: UInt64 = 0x0000_0100_0000_01b3

    /// Computes the FNV-1a hash of `value`'s UTF-8 bytes.
    static func fnv1a(_ value: String) -> UInt64 {
        var hash = offsetBasis
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* prime
        }
        return hash
    }
}
