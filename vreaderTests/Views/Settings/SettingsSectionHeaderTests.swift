// Bug #300: the app Settings section headers ("Cloud & Sync" / "AI" / "Reading"
// / "About") rendered faint in system Dark Mode because plain `Section("…")`
// headers resolve the system `secondaryLabel` (~1.07:1 over the pinned cream
// sheet). The fix paints them with the designed `sub` token via
// `SettingsSectionHeader`. These pin that the header (a) resolves the theme `sub`
// token, NOT the system default, and (b) clears the secondary-text legibility
// bar over the sheet surface — regardless of system appearance.
//
// Mirrors the contrast-test pattern of ReaderSettingsPanelContrastTests (#285).
//
// @coordinates-with vreader/Views/Settings/SettingsSectionHeader.swift

#if canImport(UIKit)
import Testing
import UIKit
@testable import vreader

@Suite("SettingsSectionHeader — Dark-Mode legibility (Bug #300)")
struct SettingsSectionHeaderTests {

    // MARK: - WCAG helpers (mirrors ReaderSettingsPanelContrastTests)

    private func relativeLuminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        precondition(color.getRed(&r, green: &g, blue: &b, alpha: &a), "color conversion failed")
        func linearize(_ c: CGFloat) -> Double {
            let v = Double(c)
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    private func contrastRatio(_ c1: UIColor, _ c2: UIColor) -> Double {
        let l1 = relativeLuminance(c1), l2 = relativeLuminance(c2)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Composite the translucent `sub` ink over the opaque sheet so it is scored
    /// as it actually renders.
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

    // MARK: - Tests

    @Test("header resolves the theme `sub` token, NOT the system secondaryLabel")
    func resolvesSubTokenNotSystemDefault() {
        let color = SettingsSectionHeader.color(for: .paper)
        #expect(color == ReaderThemeV2.paper.subColor)
        #expect(color != UIColor.secondaryLabel)
    }

    @Test("header clears WCAG AA (>=4.5) over the cream sheet surface")
    func clearsSecondaryBarOverSheet() {
        // Feature #84 bumped the light-family `sub` token to ink@68%, so the
        // header (which reads `paper.subColor`) now clears full AA, not just
        // the project's 3.0 secondary self-bar.
        let surface = ReaderThemeV2.paper.sheetSurfaceColor
        let composited = composite(SettingsSectionHeader.color(for: .paper), over: surface)
        let ratio = contrastRatio(composited, surface)
        #expect(ratio >= 4.5, "Settings header sub token \(ratio) must clear WCAG AA 4.5 over the sheet")
    }

    @Test("the faint system secondaryLabel the bug used would NOT have cleared the bar")
    func systemSecondaryLabelWasTheRegression() {
        // The pinned-cream sheet over which a Dark-Mode `secondaryLabel` (light
        // gray) renders ~1.07:1 — far below the bar. This documents WHY the plain
        // Section header was illegible, and that the sub token is a real fix.
        let surface = ReaderThemeV2.paper.sheetSurfaceColor
        let darkSecondary = UIColor.secondaryLabel.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: .dark)
        )
        let ratio = contrastRatio(composite(darkSecondary, over: surface), surface)
        #expect(ratio < 2.0, "system secondaryLabel in Dark Mode is faint on cream (\(ratio))")
    }
}
#endif
