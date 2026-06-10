// Purpose: Feature #67 — design data pinning each Settings-sheet row's
// brand color + SF Symbol, so the per-row colors live in one home
// (the same pattern as `SheetSectionContract` / `LibraryCardTokens`).
//
// Values are pinned to the committed design bundle at
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`
// (`SettingsSheet`'s `Row` — the 30pt colored-icon row).
//
// Key decisions:
// - **Foundation-only** — `RGBComponents` is a plain `(r,g,b)` byte
//   triple, so this file compiles in the test target without SwiftUI
//   and `SettingsRowPaletteTests` can pin the design hex without a
//   render path (the `SheetSectionContract` precedent).
// - **Scoped to exactly the rows this sheet renders.** WI-2 declares
//   the six core-group rows (Cloud & Sync / Reading / About); WI-5
//   adds the AI Provider row; WI-6 adds the two AI toggle rows
//   (AI Assistant master gate + Allow AI data sharing consent) now
//   that design #1068 (`vreader-ai-toggles.jsx`) supplies their
//   colored-tile treatment. The design's OPDS-catalogs /
//   translation-languages / Chinese-conversion rows are deliberately
//   absent — OPDS routes through the Library nav (not this sheet),
//   and the translation / Chinese-conversion rows are aspirational in
//   the design but not present on the shipped `SettingsView`.
// - **`RGBComponents` clamps to `0...255`** — an out-of-range channel
//   can never produce a fractional color value outside `0...1`.
//
// @coordinates-with: SettingsRowStyle.swift, SettingsView.swift,
//   SettingsRowPaletteTests.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

import Foundation

/// A Foundation-only 8-bit-per-channel RGB color value. Channels are
/// clamped into `0...255` at construction.
struct RGBComponents: Equatable, Sendable {
    let r: Int
    let g: Int
    let b: Int

    init(r: Int, g: Int, b: Int) {
        self.r = Self.clampByte(r)
        self.g = Self.clampByte(g)
        self.b = Self.clampByte(b)
    }

    private static func clampByte(_ value: Int) -> Int {
        min(255, max(0, value))
    }
}

/// One Settings-sheet row's design data — its SF Symbol name + the
/// brand color filling its 30pt icon tile.
struct SettingsRowSpec: Equatable, Sendable {
    /// A stable identifier for the row — used by the `SettingsView`
    /// `rowPaletteKeysForTesting` composition seam (WI-4).
    let paletteKey: String

    /// The SF Symbol token rendered inside the icon tile.
    let symbolName: String

    /// The icon tile's fill color, as a design-bundle RGB triple.
    let background: RGBComponents
}

/// The design's per-row symbol + color data for the Settings sheet.
/// Pure namespace — static members only, no instances.
enum SettingsRowPalette {

    // MARK: - Cloud & Sync group

    /// WebDAV backup — the design's `Icons.Cloud` glyph, `#3a8ac8`.
    static let webDAVBackup = SettingsRowSpec(
        paletteKey: "webDAVBackup",
        symbolName: "cloud",
        background: RGBComponents(r: 0x3a, g: 0x8a, b: 0xc8)
    )

    /// Book sources — the design's `Icons.Library` stack-of-books
    /// glyph, `#3a6a5a`.
    static let bookSources = SettingsRowSpec(
        paletteKey: "bookSources",
        symbolName: "books.vertical",
        background: RGBComponents(r: 0x3a, g: 0x6a, b: 0x5a)
    )

    // MARK: - Reading group

    /// Replacement rules — the design's `Icons.Note` glyph, `#a8804a`.
    static let replacementRules = SettingsRowSpec(
        paletteKey: "replacementRules",
        symbolName: "note.text",
        background: RGBComponents(r: 0xa8, g: 0x80, b: 0x4a)
    )

    /// HTTP TTS — the design's `Icons.Volume` glyph (the
    /// `Text-to-speech` row), `#3a3a8c`.
    static let httpTTS = SettingsRowSpec(
        paletteKey: "httpTTS",
        symbolName: "speaker.wave.2",
        background: RGBComponents(r: 0x3a, g: 0x3a, b: 0x8c)
    )

    // MARK: - About group

    /// Help & feedback — the design's literal "?" glyph row, `#5a5a5a`.
    /// The design renders a bare serif "?"; `questionmark` is the
    /// faithful SF Symbol for that glyph (no circle, matching the
    /// design's circle-less tile).
    static let helpFeedback = SettingsRowSpec(
        paletteKey: "helpFeedback",
        symbolName: "questionmark",
        background: RGBComponents(r: 0x5a, g: 0x5a, b: 0x5a)
    )

    /// Version — the design's `Icons.Note` glyph, `#999` → `#999999`.
    static let version = SettingsRowSpec(
        paletteKey: "version",
        symbolName: "note.text",
        background: RGBComponents(r: 0x99, g: 0x99, b: 0x99)
    )

    // MARK: - Support group (feature #96 WI-2)

    /// Diagnostics — the design's steel tile `#5b6770` with the `DiagPulseIcon`
    /// waveform glyph (`vreader-diagnostics.jsx`). `waveform.path.ecg` is the
    /// faithful SF Symbol for the design's single-pulse line.
    static let diagnostics = SettingsRowSpec(
        paletteKey: "diagnostics",
        symbolName: "waveform.path.ecg",
        background: RGBComponents(r: 0x5b, g: 0x67, b: 0x70)
    )

    // MARK: - AI group (WI-5 provider + WI-6 toggle rows)

    /// AI Provider — the design's `Icons.Sparkle` glyph + `#8c2f2f`
    /// (`vreader-panels.jsx` line 869, also `vreader-ai-toggles.jsx`
    /// line 104-105). The AI energy color.
    static let aiProvider = SettingsRowSpec(
        paletteKey: "aiProvider",
        symbolName: "sparkles",
        background: RGBComponents(r: 0x8c, g: 0x2f, b: 0x2f)
    )

    /// AI Assistant master toggle — the design's `Icons.Sparkle` glyph
    /// + `#8c2f2f` (`vreader-ai-toggles.jsx` line 95-96, Variant A). Same
    /// chroma as the AI Provider row (the AI energy color); a distinct
    /// row identity via its own `paletteKey`. WI-6 (design #1068).
    static let aiAssistant = SettingsRowSpec(
        paletteKey: "aiAssistant",
        symbolName: "sparkles",
        background: RGBComponents(r: 0x8c, g: 0x2f, b: 0x2f)
    )

    /// Allow AI data sharing (consent) — the design's `ShieldIcon`
    /// (a shield with an inner checkmark → SF Symbol `checkmark.shield`)
    /// + `#4a6a8a` (`vreader-ai-toggles.jsx` line 109-110, Variant A).
    /// The cool-blue "system / safety" family, sitting next to Cloud
    /// (`#3a8ac8`) and Folder (`#7c6ad6`). WI-6 (design #1068).
    static let aiDataSharing = SettingsRowSpec(
        paletteKey: "aiDataSharing",
        symbolName: "checkmark.shield",
        background: RGBComponents(r: 0x4a, g: 0x6a, b: 0x8a)
    )
}
