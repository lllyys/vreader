// Purpose: Tests for `ReaderThemeV2` — Feature #60 WI-2 foundational theme
// tokens (paper / sepia / dark / oled / photo) with a 10-accessor
// surface: 7 color tokens (`backgroundColor` / `paperColor` /
// `inkColor` / `subColor` / `ruleColor` / `accentColor` /
// `chromeColor`) + 3 predicates (`isDark` / `hasPaperPattern` /
// `usesBackgroundImage`).
//
// Token values are pinned to the committed design bundle at
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-themes.jsx`.
// Drift in any one of those values breaks the visual contract against
// the design — these tests catch it at unit-test time, before the
// behavioral WIs (4/5/6) start reading the tokens.
//
// This is strictly additive infrastructure (Codex Gate 2 audited; no
// view consumes ReaderThemeV2 yet — that's WI-4+).

#if canImport(UIKit)
import Testing
import UIKit
import Foundation
@testable import vreader

@Suite("ReaderThemeV2 — Feature #60 WI-2")
struct ReaderThemeV2Tests {

    // MARK: - Cases and default

    @Test
    func allCases_containsExactlyFiveThemes() {
        let cases = ReaderThemeV2.allCases
        #expect(cases.count == 5)
        #expect(Set(cases) == [.paper, .sepia, .dark, .oled, .photo])
    }

    @Test
    func defaultTheme_isPaper() {
        #expect(ReaderThemeV2.default == .paper)
    }

    @Test
    func rawValue_isSemanticName_forEachCase() {
        #expect(ReaderThemeV2.paper.rawValue == "paper")
        #expect(ReaderThemeV2.sepia.rawValue == "sepia")
        #expect(ReaderThemeV2.dark.rawValue == "dark")
        #expect(ReaderThemeV2.oled.rawValue == "oled")
        #expect(ReaderThemeV2.photo.rawValue == "photo")
    }

    // MARK: - Color tokens (pinned to vreader-themes.jsx)

    /// Pins the design-bundle hex values via UIColor RGB component checks.
    /// `dev-docs/designs/vreader-fidelity-v1/project/vreader-themes.jsx`.
    @Test
    func paper_backgroundColor_matchesDesign() {
        let (r, g, b, a) = rgba(ReaderThemeV2.paper.backgroundColor)
        #expect(approxEqual(r, 244.0 / 255.0))
        #expect(approxEqual(g, 238.0 / 255.0))
        #expect(approxEqual(b, 224.0 / 255.0))
        #expect(approxEqual(a, 1.0))
    }

    @Test
    func paper_paperColor_matchesDesign() {
        let (r, g, b, a) = rgba(ReaderThemeV2.paper.paperColor)
        #expect(approxEqual(r, 250.0 / 255.0))
        #expect(approxEqual(g, 246.0 / 255.0))
        #expect(approxEqual(b, 234.0 / 255.0))
        #expect(approxEqual(a, 1.0))
    }

    @Test
    func paper_inkColor_matchesDesign() {
        let (r, g, b, a) = rgba(ReaderThemeV2.paper.inkColor)
        #expect(approxEqual(r, 29.0 / 255.0))
        #expect(approxEqual(g, 26.0 / 255.0))
        #expect(approxEqual(b, 20.0 / 255.0))
        #expect(approxEqual(a, 1.0))
    }

    @Test
    func paper_accentColor_matchesDesignOxblood() {
        let (r, g, b, _) = rgba(ReaderThemeV2.paper.accentColor)
        #expect(approxEqual(r, 140.0 / 255.0))
        #expect(approxEqual(g, 47.0 / 255.0))
        #expect(approxEqual(b, 47.0 / 255.0))
    }

    @Test
    func sepia_accentColor_matchesDesign() {
        let (r, g, b, _) = rgba(ReaderThemeV2.sepia.accentColor)
        #expect(approxEqual(r, 122.0 / 255.0))
        #expect(approxEqual(g, 58.0 / 255.0))
        #expect(approxEqual(b, 31.0 / 255.0))
    }

    @Test
    func dark_accentColor_matchesDesignWarmRose() {
        let (r, g, b, _) = rgba(ReaderThemeV2.dark.accentColor)
        #expect(approxEqual(r, 214.0 / 255.0))
        #expect(approxEqual(g, 136.0 / 255.0))
        #expect(approxEqual(b, 90.0 / 255.0))
    }

    @Test
    func oled_backgroundColor_isPureBlack() {
        let (r, g, b, _) = rgba(ReaderThemeV2.oled.backgroundColor)
        #expect(approxEqual(r, 0.0))
        #expect(approxEqual(g, 0.0))
        #expect(approxEqual(b, 0.0))
    }

    @Test
    func photo_accentColor_matchesDesignGold() {
        let (r, g, b, _) = rgba(ReaderThemeV2.photo.accentColor)
        #expect(approxEqual(r, 232.0 / 255.0))
        #expect(approxEqual(g, 180.0 / 255.0))
        #expect(approxEqual(b, 101.0 / 255.0))
    }

    /// `sub` and `rule` are alpha-blended on top of the theme's `ink` color
    /// per the design bundle. We pin (a) the RGB matches ink's RGB, and
    /// (b) the alpha matches the design's specified alpha. This protects
    /// against a future drift where someone "simplifies" by collapsing the
    /// alpha into a flat RGB — which would change how the token renders
    /// over varying paper backgrounds.
    @Test
    func paper_subColor_isInkWithDesignAlpha() {
        let (r, g, b, a) = rgba(ReaderThemeV2.paper.subColor)
        #expect(approxEqual(r, 29.0 / 255.0))
        #expect(approxEqual(g, 26.0 / 255.0))
        #expect(approxEqual(b, 20.0 / 255.0))
        // Feature #84: light-family sub bumped ink@0.55 → ink@0.68 for WCAG AA
        // (landed design secondary-text-sub-token.md).
        #expect(approxEqual(a, 0.68))
    }

    @Test
    func paper_ruleColor_isInkWithDesignAlpha() {
        let (_, _, _, a) = rgba(ReaderThemeV2.paper.ruleColor)
        #expect(approxEqual(a, 0.12))
    }

    @Test
    func dark_subColor_isInkWithDesignAlpha() {
        let (r, g, b, a) = rgba(ReaderThemeV2.dark.subColor)
        #expect(approxEqual(r, 216.0 / 255.0))
        #expect(approxEqual(g, 210.0 / 255.0))
        #expect(approxEqual(b, 197.0 / 255.0))
        #expect(approxEqual(a, 0.5))
    }

    // MARK: - Boolean predicates

    @Test
    func isDark_matchesDesign() {
        #expect(ReaderThemeV2.paper.isDark == false)
        #expect(ReaderThemeV2.sepia.isDark == false)
        #expect(ReaderThemeV2.dark.isDark == true)
        #expect(ReaderThemeV2.oled.isDark == true)
        #expect(ReaderThemeV2.photo.isDark == true)
    }

    /// `paperPattern` is the texture overlay rendered on top of the page
    /// surface. Per the design bundle it's true for Paper + Sepia only —
    /// dark themes get a flat surface. If a future theme gains a pattern
    /// without intent, this catches the drift.
    @Test
    func hasPaperPattern_isTrueOnlyForPaperAndSepia() {
        #expect(ReaderThemeV2.paper.hasPaperPattern == true)
        #expect(ReaderThemeV2.sepia.hasPaperPattern == true)
        #expect(ReaderThemeV2.dark.hasPaperPattern == false)
        #expect(ReaderThemeV2.oled.hasPaperPattern == false)
        #expect(ReaderThemeV2.photo.hasPaperPattern == false)
    }

    /// `usesBackgroundImage` toggles WI-4's CSS `body { background-image:
    /// url(...) }` rule. Photo theme only. If another theme accidentally
    /// claims to use a background image, the EPUB CSS injection at WI-4
    /// would try to load a non-existent asset.
    @Test
    func usesBackgroundImage_isTrueOnlyForPhoto() {
        #expect(ReaderThemeV2.paper.usesBackgroundImage == false)
        #expect(ReaderThemeV2.sepia.usesBackgroundImage == false)
        #expect(ReaderThemeV2.dark.usesBackgroundImage == false)
        #expect(ReaderThemeV2.oled.usesBackgroundImage == false)
        #expect(ReaderThemeV2.photo.usesBackgroundImage == true)
    }

    // MARK: - Sendable (compile-time)

    @Test
    func sendable_conformance_isAvailable() {
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        let echoed = requireSendable(ReaderThemeV2.paper)
        #expect(echoed == .paper)
    }

    // MARK: - Complete per-theme/per-token coverage matrix

    /// Per Codex Gate 4 round 1 (Low): the hand-picked assertions above
    /// only cover a subset of the per-theme/per-token grid (Paper +
    /// selected accents). A typo in an unexercised arm — e.g., Sepia's
    /// `chromeColor` or OLED's `paperColor` — would ship unnoticed.
    /// This matrix walks every theme × every color token and pins each
    /// to the committed design bundle values from
    /// `dev-docs/designs/vreader-fidelity-v1/project/vreader-themes.jsx` —
    /// EXCEPT the light-family `sub` alpha (Paper/Sepia ink@0.68), governed by
    /// the later `design-notes/secondary-text-sub-token.md` (Feature #84 / #1292,
    /// WCAG-AA bump from the bundle's 0.55).
    /// Each row's (r, g, b, a) is byte-exact except where the design
    /// specifies alpha (sub / rule / photo paper+chrome).
    @Test
    func tokenMatrix_everyThemeEveryToken_matchesDesignBundle() {
        struct Row { let theme: ReaderThemeV2; let token: TokenName; let r, g, b: Int; let alpha: CGFloat }
        let rows: [Row] = [
            // Paper
            Row(theme: .paper, token: .bg,     r: 0xf4, g: 0xee, b: 0xe0, alpha: 1.00),
            Row(theme: .paper, token: .paper,  r: 0xfa, g: 0xf6, b: 0xea, alpha: 1.00),
            Row(theme: .paper, token: .ink,    r: 0x1d, g: 0x1a, b: 0x14, alpha: 1.00),
            Row(theme: .paper, token: .sub,    r: 0x1d, g: 0x1a, b: 0x14, alpha: 0.68),
            Row(theme: .paper, token: .rule,   r: 0x1d, g: 0x1a, b: 0x14, alpha: 0.12),
            Row(theme: .paper, token: .accent, r: 0x8c, g: 0x2f, b: 0x2f, alpha: 1.00),
            Row(theme: .paper, token: .chrome, r: 0xf7, g: 0xf1, b: 0xe3, alpha: 1.00),
            // Sepia
            Row(theme: .sepia, token: .bg,     r: 0xe6, g: 0xd6, b: 0xb6, alpha: 1.00),
            Row(theme: .sepia, token: .paper,  r: 0xed, g: 0xdf, b: 0xc2, alpha: 1.00),
            Row(theme: .sepia, token: .ink,    r: 0x3a, g: 0x29, b: 0x13, alpha: 1.00),
            Row(theme: .sepia, token: .sub,    r: 0x3a, g: 0x29, b: 0x13, alpha: 0.68),
            Row(theme: .sepia, token: .rule,   r: 0x3a, g: 0x29, b: 0x13, alpha: 0.15),
            Row(theme: .sepia, token: .accent, r: 0x7a, g: 0x3a, b: 0x1f, alpha: 1.00),
            Row(theme: .sepia, token: .chrome, r: 0xe8, g: 0xd9, b: 0xbd, alpha: 1.00),
            // Dark
            Row(theme: .dark, token: .bg,      r: 0x1a, g: 0x18, b: 0x15, alpha: 1.00),
            Row(theme: .dark, token: .paper,   r: 0x21, g: 0x20, b: 0x1c, alpha: 1.00),
            Row(theme: .dark, token: .ink,     r: 0xd8, g: 0xd2, b: 0xc5, alpha: 1.00),
            Row(theme: .dark, token: .sub,     r: 0xd8, g: 0xd2, b: 0xc5, alpha: 0.50),
            Row(theme: .dark, token: .rule,    r: 0xd8, g: 0xd2, b: 0xc5, alpha: 0.12),
            Row(theme: .dark, token: .accent,  r: 0xd6, g: 0x88, b: 0x5a, alpha: 1.00),
            Row(theme: .dark, token: .chrome,  r: 0x1d, g: 0x1b, b: 0x18, alpha: 1.00),
            // OLED
            Row(theme: .oled, token: .bg,      r: 0x00, g: 0x00, b: 0x00, alpha: 1.00),
            Row(theme: .oled, token: .paper,   r: 0x05, g: 0x05, b: 0x05, alpha: 1.00),
            Row(theme: .oled, token: .ink,     r: 0xb9, g: 0xb6, b: 0xb0, alpha: 1.00),
            Row(theme: .oled, token: .sub,     r: 0xb9, g: 0xb6, b: 0xb0, alpha: 0.50),
            Row(theme: .oled, token: .rule,    r: 0xb9, g: 0xb6, b: 0xb0, alpha: 0.12),
            Row(theme: .oled, token: .accent,  r: 0xd6, g: 0x88, b: 0x5a, alpha: 1.00),
            Row(theme: .oled, token: .chrome,  r: 0x05, g: 0x05, b: 0x05, alpha: 1.00),
            // Photo — alpha-bearing on paper + chrome
            Row(theme: .photo, token: .bg,     r: 0x2a, g: 0x25, b: 0x20, alpha: 1.00),
            Row(theme: .photo, token: .paper,  r: 0x14, g: 0x10, b: 0x0c, alpha: 0.55),
            Row(theme: .photo, token: .ink,    r: 0xe8, g: 0xe0, b: 0xd0, alpha: 1.00),
            Row(theme: .photo, token: .sub,    r: 0xe8, g: 0xe0, b: 0xd0, alpha: 0.55),
            Row(theme: .photo, token: .rule,   r: 0xe8, g: 0xe0, b: 0xd0, alpha: 0.18),
            Row(theme: .photo, token: .accent, r: 0xe8, g: 0xb4, b: 0x65, alpha: 1.00),
            Row(theme: .photo, token: .chrome, r: 0x14, g: 0x10, b: 0x0c, alpha: 0.70),
        ]
        // 5 themes × 7 color tokens = 35 rows; sanity-check the matrix
        // shape so a future cut-and-paste typo can't quietly drop a row.
        #expect(rows.count == 35)
        for row in rows {
            let color = colorFor(theme: row.theme, token: row.token)
            let (r, g, b, a) = rgba(color)
            let label = "\(row.theme.rawValue).\(row.token.rawValue)"
            #expect(approxEqual(r, CGFloat(row.r) / 255.0),
                    "\(label) red drift: expected \(row.r)/255 got \(r * 255)")
            #expect(approxEqual(g, CGFloat(row.g) / 255.0),
                    "\(label) green drift: expected \(row.g)/255 got \(g * 255)")
            #expect(approxEqual(b, CGFloat(row.b) / 255.0),
                    "\(label) blue drift: expected \(row.b)/255 got \(b * 255)")
            #expect(approxEqual(a, row.alpha),
                    "\(label) alpha drift: expected \(row.alpha) got \(a)")
        }
    }

    // MARK: - Token isolation across themes

    /// Every theme produces a distinct backgroundColor — otherwise two
    /// themes would render identically and the picker would be confusing.
    @Test
    func backgroundColors_areDistinctAcrossThemes() {
        let bgs = ReaderThemeV2.allCases.map { rgba($0.backgroundColor) }
        // Compare RGB tuples ignoring alpha; alpha for solid theme bgs is 1.0.
        let rgbs = bgs.map { ($0.0, $0.1, $0.2) }
        for i in 0..<rgbs.count {
            for j in (i + 1)..<rgbs.count {
                let (a, b, c) = rgbs[i]
                let (x, y, z) = rgbs[j]
                let same = approxEqual(a, x) && approxEqual(b, y) && approxEqual(c, z)
                #expect(!same, "Two themes share a background color: \(rgbs[i]) vs \(rgbs[j])")
            }
        }
    }

    // MARK: - Helpers

    private enum TokenName: String {
        case bg, paper, ink, sub, rule, accent, chrome
    }

    private func colorFor(theme: ReaderThemeV2, token: TokenName) -> UIColor {
        switch token {
        case .bg:     return theme.backgroundColor
        case .paper:  return theme.paperColor
        case .ink:    return theme.inkColor
        case .sub:    return theme.subColor
        case .rule:   return theme.ruleColor
        case .accent: return theme.accentColor
        case .chrome: return theme.chromeColor
        }
    }

    private func rgba(_ color: UIColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    /// 1/255 tolerance — pins to integer 8-bit RGB values without false
    /// failures from CGFloat round-trip noise.
    private func approxEqual(_ a: CGFloat, _ b: CGFloat, epsilon: CGFloat = 0.005) -> Bool {
        abs(a - b) < epsilon
    }
}
#endif
