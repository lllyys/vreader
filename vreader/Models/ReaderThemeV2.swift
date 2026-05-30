// Purpose: Feature #60 visual-identity v2 — extended theme token set
// (Paper / Sepia / Dark / OLED / Photo) with a 10-accessor surface
// (7 color tokens — bg / paper / ink / sub / rule / accent / chrome —
// + 3 predicates — isDark / hasPaperPattern / usesBackgroundImage)
// consumed by the WI-4+ reader-engine theme injection paths
// (`EPUBReaderContainerView`, `TXTReaderContainerView`,
// `MDReaderContainerView`) and the WI-6+ chrome re-skin.
//
// Token values are pinned to the committed design bundle at
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-themes.jsx`.
//
// Key decisions:
// - **Strictly additive over `ReaderTheme`.** The existing 3-token
//   enum stays in place; this file extends with 10 accessors and 5
//   themes. WI-4+ migrates call sites one at a time.
// - **Codable migration alias** (custom decoder): existing per-book
//   persisted theme choices stored `ReaderTheme` rawValues
//   ("light" / "sepia" / "dark"). Decoding accepts those legacy
//   strings AND the new names ("paper" / "sepia" / "dark" / "oled"
//   / "photo"). Encoding always emits the NEW name. This preserves
//   read-paths so users don't lose per-book settings on the WI-4
//   cutover; subsequent writes carry the new name forward.
// - **No SwiftData schema bump.** The stored value is a `String`
//   carrying the rawValue; only the set of accepted values changes.
// - **Sub/rule alpha preserved.** Per design, `sub` and `rule` are
//   alpha-blended on top of `ink` — keeping the RGB ink-aligned
//   and using alpha for the dimming. Collapsing to a flat RGB would
//   make these tokens render incorrectly over paper backgrounds.
//
// @coordinates-with: ReaderTheme.swift (3-token predecessor),
//   ReaderSettingsStore.swift (future WI-4+ plumbing),
//   AccentColor.swift (oxblood family, three-stop),
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-themes.jsx`

import Foundation
#if canImport(UIKit)
import UIKit

enum ReaderThemeV2: String, CaseIterable, Sendable {
    case paper
    case sepia
    case dark
    case oled
    case photo

    /// Default for new users / unknown legacy values.
    static var `default`: ReaderThemeV2 { .paper }

    // MARK: - Color tokens (7 of the 10-accessor surface)

    /// Outer page-background tint. `body { background-color: ... }` in EPUB
    /// CSS injection; UIScrollView backgroundColor in TXT/MD.
    var backgroundColor: UIColor {
        switch self {
        case .paper: return Self.hex(0xf4, 0xee, 0xe0)
        case .sepia: return Self.hex(0xe6, 0xd6, 0xb6)
        case .dark:  return Self.hex(0x1a, 0x18, 0x15)
        case .oled:  return Self.hex(0x00, 0x00, 0x00)
        case .photo: return Self.hex(0x2a, 0x25, 0x20)
        }
    }

    /// Text-container surface — drawn over `backgroundColor` to give the
    /// text-block its own subtle tint (paper-stack effect). Photo theme
    /// uses an alpha-blended overlay over the background image.
    var paperColor: UIColor {
        switch self {
        case .paper: return Self.hex(0xfa, 0xf6, 0xea)
        case .sepia: return Self.hex(0xed, 0xdf, 0xc2)
        case .dark:  return Self.hex(0x21, 0x20, 0x1c)
        case .oled:  return Self.hex(0x05, 0x05, 0x05)
        case .photo: return Self.hex(0x14, 0x10, 0x0c, alpha: 0.55)
        }
    }

    /// Primary body text.
    var inkColor: UIColor {
        switch self {
        case .paper: return Self.hex(0x1d, 0x1a, 0x14)
        case .sepia: return Self.hex(0x3a, 0x29, 0x13)
        case .dark:  return Self.hex(0xd8, 0xd2, 0xc5)
        case .oled:  return Self.hex(0xb9, 0xb6, 0xb0)
        case .photo: return Self.hex(0xe8, 0xe0, 0xd0)
        }
    }

    /// Secondary text (timestamps, captions, page indicators). Per design
    /// this is `ink` with a per-theme alpha — kept as alpha rather than
    /// pre-blended so it renders correctly over varying paper tints.
    var subColor: UIColor {
        switch self {
        case .paper: return Self.hex(0x1d, 0x1a, 0x14, alpha: 0.55)
        case .sepia: return Self.hex(0x3a, 0x29, 0x13, alpha: 0.55)
        case .dark:  return Self.hex(0xd8, 0xd2, 0xc5, alpha: 0.5)
        case .oled:  return Self.hex(0xb9, 0xb6, 0xb0, alpha: 0.5)
        case .photo: return Self.hex(0xe8, 0xe0, 0xd0, alpha: 0.55)
        }
    }

    /// Hairline dividers (0.5pt). Same RGB-as-ink-plus-alpha pattern as sub.
    var ruleColor: UIColor {
        switch self {
        case .paper: return Self.hex(0x1d, 0x1a, 0x14, alpha: 0.12)
        case .sepia: return Self.hex(0x3a, 0x29, 0x13, alpha: 0.15)
        case .dark:  return Self.hex(0xd8, 0xd2, 0xc5, alpha: 0.12)
        case .oled:  return Self.hex(0xb9, 0xb6, 0xb0, alpha: 0.12)
        case .photo: return Self.hex(0xe8, 0xe0, 0xd0, alpha: 0.18)
        }
    }

    /// The Display panel slider's UNFILLED rail. Bug #285 / #1273: the old
    /// inline `isDark ? white@0.1 : black@0.1` computed to ~1.25:1 over the cream
    /// panel (a cold pure-black smudge that "reads as no rail"). Per the landed
    /// design (`dev-docs/designs/.../design-notes/slider-track-rail.md`): light
    /// family = each theme's own `ink` at 22% (inherits the theme's warmth, lifts
    /// the rail to ~1.6:1); dark family keeps its 12% weight (the white-on-dark
    /// rail already reads). Exact design-specified values — not a hand-picked tint.
    var sliderTrack: UIColor {
        switch self {
        case .paper: return Self.hex(0x1d, 0x1a, 0x14, alpha: 0.22)
        case .sepia: return Self.hex(0x3a, 0x29, 0x13, alpha: 0.22)
        case .dark:  return Self.hex(0xd8, 0xd2, 0xc5, alpha: 0.12)
        case .oled:  return Self.hex(0xb9, 0xb6, 0xb0, alpha: 0.12)
        case .photo: return Self.hex(0xe8, 0xe0, 0xd0, alpha: 0.12)
        }
    }

    /// Single restrained accent for chrome (selected pickers, primary
    /// actions, selection emphasis). Three-stop oxblood family per
    /// `AccentColor.swift` — but each theme picks its own stop because
    /// the warm-dark tone needed for OLED differs from the bright
    /// oxblood that reads well over Paper.
    var accentColor: UIColor {
        switch self {
        case .paper: return Self.hex(0x8c, 0x2f, 0x2f)
        case .sepia: return Self.hex(0x7a, 0x3a, 0x1f)
        case .dark:  return Self.hex(0xd6, 0x88, 0x5a)
        case .oled:  return Self.hex(0xd6, 0x88, 0x5a)
        case .photo: return Self.hex(0xe8, 0xb4, 0x65)
        }
    }

    /// Toolbar / chrome surface tint — distinct from `backgroundColor`
    /// because chrome floats above the page and needs its own elevation.
    /// Photo theme uses an alpha-blended dark overlay over the background
    /// image so the chrome stays legible without obscuring the photo.
    var chromeColor: UIColor {
        switch self {
        case .paper: return Self.hex(0xf7, 0xf1, 0xe3)
        case .sepia: return Self.hex(0xe8, 0xd9, 0xbd)
        case .dark:  return Self.hex(0x1d, 0x1b, 0x18)
        case .oled:  return Self.hex(0x05, 0x05, 0x05)
        case .photo: return Self.hex(0x14, 0x10, 0x0c, alpha: 0.7)
        }
    }

    // MARK: - Boolean predicates

    /// Drives `preferredColorScheme` for status-bar tinting and any
    /// system-chrome decisions (e.g., NavigationBar default appearance).
    var isDark: Bool {
        switch self {
        case .paper, .sepia: return false
        case .dark, .oled, .photo: return true
        }
    }

    /// True when WI-6+'s chrome composition should overlay a subtle
    /// paper-texture pattern on `paperColor`. Per design, only Paper and
    /// Sepia carry the texture — dark themes use a flat surface.
    var hasPaperPattern: Bool {
        switch self {
        case .paper, .sepia: return true
        case .dark, .oled, .photo: return false
        }
    }

    /// True when WI-4 CSS injection should emit a `body { background-image:
    /// url(...) }` rule and WI-6 chrome composition should treat the
    /// background as a user-picked photo (via the WI-4 extension of
    /// `ThemeBackgroundStore`). Photo theme only.
    var usesBackgroundImage: Bool {
        switch self {
        case .photo: return true
        case .paper, .sepia, .dark, .oled: return false
        }
    }

    // MARK: - UIColor convenience builder

    /// Builds a UIColor from 8-bit RGB integer triples plus optional alpha.
    /// Keeps the design hex values readable in the switch arms above
    /// without per-color CGFloat division noise.
    private static func hex(
        _ r: Int, _ g: Int, _ b: Int, alpha: CGFloat = 1.0
    ) -> UIColor {
        UIColor(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: alpha
        )
    }
}

// MARK: - Codable with legacy-name migration alias

extension ReaderThemeV2: Codable {
    /// Decodes both the new rawValues ("paper" / "sepia" / "dark" / "oled"
    /// / "photo") AND the legacy `ReaderTheme` rawValues ("light" /
    /// "sepia" / "dark") that exist in per-book persisted JSON. The
    /// legacy `"light"` maps to `.paper`; `"sepia"` and `"dark"` are
    /// preserved as-is. Unknown values throw `DecodingError` so callers
    /// can apply their own fallback policy (typically `ReaderThemeV2.default`).
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        // New names.
        case "paper": self = .paper
        case "sepia": self = .sepia
        case "dark":  self = .dark
        case "oled":  self = .oled
        case "photo": self = .photo
        // Legacy alias — preserves per-book ReaderTheme persistence.
        case "light": self = .paper
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown ReaderThemeV2 rawValue: \"\(raw)\""
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.rawValue)
    }
}

#endif
