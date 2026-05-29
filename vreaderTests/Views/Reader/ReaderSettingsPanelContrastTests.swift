// Purpose: Contrast-regression tests for the Reader Settings (Display)
// panel chrome — Bug #285 / GH #1265. In the Paper and Sepia themes the
// panel surface is a fixed warm cream (`#fcf8f0`), but the native List
// chrome (Section headers, Toggle / Picker / plain-Text labels, footers)
// was never theme-tinted — it stayed on the system `label` /
// `secondaryLabel` colors, which wash out against cream and (worst case)
// read as near-invisible in Sepia.
//
// The fix routes the native chrome through the panel's `ReaderThemeV2`
// tokens, exactly as the committed design `vreader-panels.jsx` colours
// every label (`SectionLabel` → `t.sub`; primary control labels →
// `t.ink`). These tests pin the resolved chrome colours via the testable
// `ReaderSettingsPanel.ChromeLabelPalette` seam (the same composition-test
// pattern as `themePickerThemes` / `chineseConversionDisableReason`) and
// assert each clears the project's established two-bar WCAG convention
// (`WCAGContrastTests`): primary text >= 4.5:1, secondary text >= 3.0:1,
// computed over the actual panel surface.
//
// @coordinates-with: vreader/Views/Reader/ReaderSettingsPanel.swift,
//   vreader/Views/Reader/ReaderSheetChrome.swift,
//   vreader/Models/ReaderThemeV2.swift

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

#if canImport(UIKit)
@Suite("ReaderSettingsPanel chrome contrast (Bug #285)")
struct ReaderSettingsPanelContrastTests {

    // MARK: - WCAG helpers (mirror WCAGContrastTests)

    /// WCAG relative luminance. https://www.w3.org/TR/WCAG20/#relativeluminancedef
    private func relativeLuminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        precondition(color.getRed(&r, green: &g, blue: &b, alpha: &a), "Color conversion failed")
        func linearize(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private func contrastRatio(_ c1: UIColor, _ c2: UIColor) -> Double {
        let l1 = relativeLuminance(c1)
        let l2 = relativeLuminance(c2)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Composites a possibly-translucent foreground colour over an opaque
    /// background, so an alpha-blended token (the `sub` ink@0.55) is
    /// scored as it actually renders on the cream panel — not as if it
    /// were opaque.
    private func composite(_ fg: UIColor, over bg: UIColor) -> UIColor {
        var fr: CGFloat = 0, fg2: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var br: CGFloat = 0, bg2: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        precondition(fg.getRed(&fr, green: &fg2, blue: &fb, alpha: &fa))
        precondition(bg.getRed(&br, green: &bg2, blue: &bb, alpha: &ba))
        return UIColor(
            red: fr * fa + br * (1 - fa),
            green: fg2 * fa + bg2 * (1 - fa),
            blue: fb * fa + bb * (1 - fa),
            alpha: 1
        )
    }

    // MARK: - Affected light-family themes

    /// Paper and Sepia are the `isDark == false` themes whose panel
    /// surface is the cream sheet — the only two affected by Bug #285.
    private static let lightThemes: [ReaderThemeV2] = [.paper, .sepia]

    // MARK: - Primary chrome labels clear 4.5:1

    /// Section bodies' primary labels (Toggle / Picker / plain-Text rows)
    /// resolve to the theme `ink` token; over the cream sheet that must
    /// clear the 4.5:1 primary-text bar in every affected theme.
    @Test func primaryChromeLabelClearsAA() {
        for theme in Self.lightThemes {
            let palette = ReaderSettingsPanel.ChromeLabelPalette(theme: theme)
            let surface = theme.sheetSurfaceColor
            let ratio = contrastRatio(composite(palette.primary, over: surface), surface)
            #expect(ratio >= 4.5, "\(theme) primary chrome label \(ratio) must be >= 4.5")
        }
    }

    // MARK: - Secondary chrome (section headers + footers) clear 3.0:1

    /// Section headers and footer captions resolve to the theme `sub`
    /// token (matching the design's `SectionLabel` = `t.sub`). Per the
    /// project's two-bar convention secondary text needs >= 3.0:1.
    @Test func secondaryChromeLabelClearsSecondaryBar() {
        for theme in Self.lightThemes {
            let palette = ReaderSettingsPanel.ChromeLabelPalette(theme: theme)
            let surface = theme.sheetSurfaceColor
            let ratio = contrastRatio(composite(palette.secondary, over: surface), surface)
            #expect(ratio >= 3.0, "\(theme) secondary chrome label \(ratio) must be >= 3.0")
        }
    }

    // MARK: - The palette is theme-tinted, not system-default

    /// The regression that defined Bug #285: the native chrome was NOT
    /// tinted — it used system `label` / `secondaryLabel`. The fix must
    /// resolve the panel chrome to the theme's own ink / sub tokens, so
    /// the resolved palette colours equal the theme tokens (and are NOT
    /// the system label colours).
    @Test func paletteResolvesThemeTokensNotSystemDefaults() {
        for theme in Self.lightThemes {
            let palette = ReaderSettingsPanel.ChromeLabelPalette(theme: theme)
            #expect(palette.primary == theme.inkColor,
                    "\(theme) primary chrome must be the theme ink token")
            #expect(palette.secondary == theme.subColor,
                    "\(theme) secondary chrome must be the theme sub token")
            #expect(palette.primary != UIColor.label,
                    "\(theme) primary chrome must not be the system label color")
            #expect(palette.secondary != UIColor.secondaryLabel,
                    "\(theme) secondary chrome must not be the system secondaryLabel color")
        }
    }

    // MARK: - Destructive action keeps its red (Gate-4 Medium)

    /// The list-wide `.foregroundStyle(primary)` (theme ink) would
    /// otherwise repaint the destructive "Remove Background" button in
    /// ink. The palette carries a distinct `destructive` colour (the
    /// design's `#c44`) so the button stays visibly destructive — it
    /// must NOT equal the primary ink token.
    @Test func destructiveActionStaysDistinctFromPrimaryInk() {
        for theme in ReaderThemeV2.allCases {
            let palette = ReaderSettingsPanel.ChromeLabelPalette(theme: theme)
            #expect(palette.destructive != palette.primary,
                    "\(theme) destructive colour must differ from the primary ink token")
        }
    }

    /// The destructive colour is the design's documented danger value
    /// `#c44` (== `#cc4444`) — a restore-to-design value, not invented —
    /// and is theme-independent (the design renders danger rows the same
    /// across themes).
    @Test func destructiveColorMatchesDesignDangerToken() {
        let expected = UIColor(red: 0xcc / 255, green: 0x44 / 255, blue: 0x44 / 255, alpha: 1)
        for theme in ReaderThemeV2.allCases {
            let palette = ReaderSettingsPanel.ChromeLabelPalette(theme: theme)
            #expect(palette.destructive == expected,
                    "\(theme) destructive colour must be the design's #c44 danger token")
        }
    }

    /// The destructive colour clears the AA text bar over the cream
    /// sheet in the affected light themes (design's `#c44` = 4.43:1,
    /// above the system red it replaces).
    @Test func destructiveColorClearsAAOverCream() {
        for theme in Self.lightThemes {
            let palette = ReaderSettingsPanel.ChromeLabelPalette(theme: theme)
            let surface = theme.sheetSurfaceColor
            let ratio = contrastRatio(composite(palette.destructive, over: surface), surface)
            #expect(ratio >= 4.4, "\(theme) destructive colour \(ratio) must be >= ~4.4 (design #c44)")
        }
    }

    // MARK: - Dark family is unchanged (no regression)

    /// The dark-family themes were never affected (light-on-dark keeps
    /// contrast) — the palette must still resolve their ink / sub tokens
    /// so the same routing applies uniformly without regressing them.
    @Test func darkFamilyPaletteStillResolvesTokens() {
        for theme in [ReaderThemeV2.dark, .oled, .photo] {
            let palette = ReaderSettingsPanel.ChromeLabelPalette(theme: theme)
            #expect(palette.primary == theme.inkColor)
            #expect(palette.secondary == theme.subColor)
        }
    }
}
#endif
