// Purpose: WCAG AA contrast ratio validation for all reader themes.
// Ensures text/background color pairs meet 4.5:1 contrast ratio.

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

@Suite("WCAG Contrast")
struct WCAGContrastTests {

    // MARK: - Contrast Ratio Helper

    /// Calculates WCAG relative luminance for a color.
    /// https://www.w3.org/TR/WCAG20/#relativeluminancedef
    #if canImport(UIKit)
    private func relativeLuminance(_ color: UIColor) -> Double {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        precondition(color.getRed(&r, green: &g, blue: &b, alpha: &a), "Color conversion failed")

        func linearize(_ component: CGFloat) -> Double {
            let c = Double(component)
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(r) + 0.7152 * linearize(g) + 0.0722 * linearize(b)
    }

    /// Calculates WCAG contrast ratio between two colors.
    /// Returns a value >= 1.0. WCAG AA requires >= 4.5 for normal text.
    private func contrastRatio(_ color1: UIColor, _ color2: UIColor) -> Double {
        let l1 = relativeLuminance(color1)
        let l2 = relativeLuminance(color2)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
    #endif

    // MARK: - WCAG AA (4.5:1) Tests

    #if canImport(UIKit)
    @Test func lightThemeTextContrastMeetsWCAGAA() {
        let theme = ReaderTheme.light
        let ratio = contrastRatio(theme.textColor, theme.backgroundColor)
        #expect(ratio >= 4.5, "Light theme text/bg contrast ratio \(ratio) must be >= 4.5")
    }

    @Test func sepiaThemeTextContrastMeetsWCAGAA() {
        let theme = ReaderTheme.sepia
        let ratio = contrastRatio(theme.textColor, theme.backgroundColor)
        #expect(ratio >= 4.5, "Sepia theme text/bg contrast ratio \(ratio) must be >= 4.5")
    }

    @Test func darkThemeTextContrastMeetsWCAGAA() {
        let theme = ReaderTheme.dark
        let ratio = contrastRatio(theme.textColor, theme.backgroundColor)
        #expect(ratio >= 4.5, "Dark theme text/bg contrast ratio \(ratio) must be >= 4.5")
    }

    @Test func lightThemeSecondaryTextContrastMeetsWCAGAA() {
        let theme = ReaderTheme.light
        let ratio = contrastRatio(theme.secondaryTextColor, theme.backgroundColor)
        // Secondary text target: 3:1 minimum (WCAG AA large text / UI components threshold)
        #expect(ratio >= 3.0, "Light theme secondary text/bg contrast ratio \(ratio) must be >= 3.0")
    }

    @Test func sepiaThemeSecondaryTextContrastMeetsWCAGAA() {
        let theme = ReaderTheme.sepia
        let ratio = contrastRatio(theme.secondaryTextColor, theme.backgroundColor)
        #expect(ratio >= 3.0, "Sepia theme secondary text/bg contrast ratio \(ratio) must be >= 3.0")
    }

    @Test func darkThemeSecondaryTextContrastMeetsWCAGAA() {
        let theme = ReaderTheme.dark
        let ratio = contrastRatio(theme.secondaryTextColor, theme.backgroundColor)
        #expect(ratio >= 3.0, "Dark theme secondary text/bg contrast ratio \(ratio) must be >= 3.0")
    }

    // MARK: - All Themes Sweep

    @Test func allThemesPassContrastRequirements() {
        for theme in ReaderTheme.allCases {
            let textRatio = contrastRatio(theme.textColor, theme.backgroundColor)
            let secondaryRatio = contrastRatio(theme.secondaryTextColor, theme.backgroundColor)
            #expect(textRatio >= 4.5, "\(theme) primary text contrast \(textRatio) must be >= 4.5")
            #expect(secondaryRatio >= 3.0, "\(theme) secondary text contrast \(secondaryRatio) must be >= 3.0")
        }
    }
    #endif
}
