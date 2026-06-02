// Purpose: Contrast-regression test for the AI Chat empty-state + input
// placeholder (Bug #310 / GH #1414). Both previously used the system
// `.secondary` ShapeStyle, which over the cream AI sheet (`#fcf8f0`) resolves
// to ~1.07:1 (near-white) in Dark Mode — barely visible. The fix routes them to
// the designed `ReaderThemeV2.sub` token (cream-aware, fixed, not appearance-
// driven) via the testable `AIChatView.secondaryContentColor(for:)` seam — the
// same restore-to-designed-token fix as the sibling Bug #285/#297/#300.
//
// @coordinates-with: vreader/Views/AI/AIChatView.swift,
//   vreader/Views/Reader/ReaderSheetChrome.swift, vreader/Models/ReaderThemeV2.swift

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

#if canImport(UIKit)
@Suite("AIChatView secondary-content contrast (Bug #310)")
struct AIChatViewContrastTests {

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
        let l1 = relativeLuminance(c1), l2 = relativeLuminance(c2)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }

    /// Composite a translucent fg over an opaque bg so the alpha-blended `sub`
    /// token is scored as it actually renders.
    private func composite(_ fg: UIColor, over bg: UIColor) -> UIColor {
        var fr: CGFloat = 0, fg2: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var br: CGFloat = 0, bg2: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        precondition(fg.getRed(&fr, green: &fg2, blue: &fb, alpha: &fa))
        precondition(bg.getRed(&br, green: &bg2, blue: &bb, alpha: &ba))
        return UIColor(
            red: fr * fa + br * (1 - fa), green: fg2 * fa + bg2 * (1 - fa),
            blue: fb * fa + bb * (1 - fa), alpha: 1)
    }

    private static let lightThemes: [ReaderThemeV2] = [.paper, .sepia]

    /// The empty-state (icon + headline) and input placeholder resolve to the
    /// theme `sub` token — NOT the system appearance-aware `.secondary` that
    /// rendered near-invisible over cream in Dark Mode (the bug).
    @Test func secondaryContentResolvesSubToken_notSystemSecondary() {
        for theme in ReaderThemeV2.allCases {
            let color = AIChatView.secondaryContentColor(for: theme)
            #expect(color == theme.subColor, "\(theme) AI-chat secondary must be the theme sub token")
            #expect(color != UIColor.secondaryLabel,
                    "\(theme) AI-chat secondary must not be the system secondaryLabel")
        }
    }

    /// Over the cream AI sheet the secondary content clears WCAG AA in the light
    /// family (the `sub` token is ink@0.68 after Feature #84) — fixing the
    /// Dark-Mode ~1.07:1 near-invisible regression.
    @Test func secondaryContentReadsOverCreamSheet() {
        for theme in Self.lightThemes {
            let surface = theme.sheetSurfaceColor
            let ratio = contrastRatio(
                composite(AIChatView.secondaryContentColor(for: theme), over: surface), surface)
            #expect(ratio >= 4.5,
                    "\(theme) AI-chat secondary \(ratio) must clear AA over the cream sheet")
        }
    }

    /// Bug #310 follow-up (Codex Gate-4 Low): the general (no-book) Library chat
    /// host must pin a LIGHT-family theme so its sheet renders cream — else the
    /// dark `sub`-token empty-state falls onto a system-dark sheet in Dark Mode
    /// (dark-on-dark, invisible — the device-caught regression). Pin the
    /// presenter's theme choice so a host that lets it drift to a dark family
    /// fails here, not silently in Dark Mode.
    @Test func libraryGeneralChat_pinsLightFamilyCreamSurface() {
        let theme = LibraryViewSheets.generalChatTheme
        #expect(theme == .paper, "general chat must pin the Paper identity")
        #expect(theme.isDark == false, "general chat surface must be light-family (cream), not system-dark")
        // and the empty-state/placeholder secondary content clears AA on it
        let surface = theme.sheetSurfaceColor
        let ratio = contrastRatio(
            composite(AIChatView.secondaryContentColor(for: theme), over: surface), surface)
        #expect(ratio >= 4.5,
                "general-chat secondary \(ratio) must clear AA over the pinned cream sheet")
    }
}
#endif
