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

    // MARK: - Bug #285 / #1273: slider rail reads on the cream panel

    /// The Display slider's unfilled rail (`sliderTrack`) over the cream panel
    /// must clear the design's ~1.6:1 target (up from the old `black@0.1` ≈
    /// 1.25:1 "no rail" smudge). The rail is decorative extent — WCAG 1.4.11 is
    /// met by the fill+thumb — so the bar here is the design's legibility lift,
    /// not 3:1.
    @Test func sliderRailReadsOverCreamPanel() {
        for theme in Self.lightThemes {
            let surface = theme.sheetSurfaceColor
            let ratio = contrastRatio(composite(theme.sliderTrack, over: surface), surface)
            #expect(ratio >= 1.5, "\(theme) slider rail \(ratio) must clear the design ~1.6:1 lift")
            // and it must be a real lift over the old black@0.1 rail.
            let oldRail = contrastRatio(composite(UIColor.black.withAlphaComponent(0.1), over: surface), surface)
            #expect(ratio > oldRail, "\(theme) sliderTrack (\(ratio)) must exceed the old rail (\(oldRail))")
        }
    }

    /// Light family = each theme's own `ink` at 22% (design); dark family keeps
    /// its 12% weight. Pins the design-specified token derivation.
    @Test func sliderTrackMatchesDesignDerivation() {
        #expect(ReaderThemeV2.paper.sliderTrack == ReaderThemeV2.paper.inkColor.withAlphaComponent(0.22))
        #expect(ReaderThemeV2.sepia.sliderTrack == ReaderThemeV2.sepia.inkColor.withAlphaComponent(0.22))
        #expect(ReaderThemeV2.dark.sliderTrack == ReaderThemeV2.dark.inkColor.withAlphaComponent(0.12))
        #expect(ReaderThemeV2.oled.sliderTrack == ReaderThemeV2.oled.inkColor.withAlphaComponent(0.12))
    }

    // MARK: - Control-track token (Bug #298 / GH #1329)

    /// Per the landed design (`control-track-token.md`): light family = each
    /// theme's own `ink` at 30%; dark family = pure white at 16%
    /// (`rgba(255,255,255,0.16)`). Photo follows the dark-family value (its
    /// sheet is dark; `isDark == true`). One ink-derived rule for the light
    /// family, mirroring `sliderTrack` (22%) and `sub` (55%).
    @Test func controlTrackMatchesDesignDerivation() {
        #expect(ReaderThemeV2.paper.controlTrack == ReaderThemeV2.paper.inkColor.withAlphaComponent(0.30))
        #expect(ReaderThemeV2.sepia.controlTrack == ReaderThemeV2.sepia.inkColor.withAlphaComponent(0.30))
        #expect(ReaderThemeV2.dark.controlTrack == UIColor(white: 1, alpha: 0.16))
        #expect(ReaderThemeV2.oled.controlTrack == UIColor(white: 1, alpha: 0.16))
        #expect(ReaderThemeV2.photo.controlTrack == UIColor(white: 1, alpha: 0.16))
    }

    /// The OFF toggle / segmented trough (`controlTrack`) over the cream panel
    /// must read unmistakably as an inactive control — the design's ~1.9:1
    /// target, far above the rejected `.systemFill` ≈ 1.19:1 "invisible" track.
    /// The bar here is the design's legibility lift (the track is a visible
    /// surface, deliberately below 3:1 per WCAG 1.4.11 rationale), not 3:1.
    @Test func controlTrackReadsOverCreamPanel() {
        for theme in Self.lightThemes {
            let surface = theme.sheetSurfaceColor
            let ratio = contrastRatio(composite(theme.controlTrack, over: surface), surface)
            #expect(ratio >= 1.8, "\(theme) controlTrack \(ratio) must clear the design ~1.9:1 lift")
            // and it must beat the rejected systemFill-class track (~1.19:1).
            let systemFillish = contrastRatio(composite(UIColor.black.withAlphaComponent(0.10), over: surface), surface)
            #expect(ratio > systemFillish, "\(theme) controlTrack (\(ratio)) must exceed the systemFill-class track (\(systemFillish))")
        }
    }

    /// OFF track ≠ accent ON-track: the inactive surface must stay visually
    /// distinct from the accent-filled ON state so on/off read apart
    /// (design: Δ ≥ 2.5:1).
    @Test func controlTrackStaysDistinctFromAccentOnTrack() {
        for theme in Self.lightThemes {
            let surface = theme.sheetSurfaceColor
            let off = composite(theme.controlTrack, over: surface)
            let on = theme.accentColor
            let delta = contrastRatio(off, on)
            #expect(delta >= 2.5, "\(theme) OFF track vs accent ON-track Δ \(delta) must be ≥ 2.5:1")
        }
    }
}
#endif
