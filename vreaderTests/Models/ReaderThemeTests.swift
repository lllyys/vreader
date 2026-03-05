// Purpose: Tests for ReaderTheme — color values, Codable round-trip, all cases.

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

@Suite("ReaderTheme")
struct ReaderThemeTests {

    // MARK: - All Cases

    @Test func allCasesContainsThreeThemes() {
        #expect(ReaderTheme.allCases.count == 3)
        #expect(ReaderTheme.allCases.contains(.light))
        #expect(ReaderTheme.allCases.contains(.sepia))
        #expect(ReaderTheme.allCases.contains(.dark))
    }

    // MARK: - Raw Values

    @Test func rawValueRoundTrip() {
        for theme in ReaderTheme.allCases {
            let raw = theme.rawValue
            let restored = ReaderTheme(rawValue: raw)
            #expect(restored == theme)
        }
    }

    @Test func invalidRawValueReturnsNil() {
        #expect(ReaderTheme(rawValue: "blue") == nil)
        #expect(ReaderTheme(rawValue: "") == nil)
        #expect(ReaderTheme(rawValue: "LIGHT") == nil)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        for theme in ReaderTheme.allCases {
            let data = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(ReaderTheme.self, from: data)
            #expect(decoded == theme)
        }
    }

    // MARK: - Color Values

    #if canImport(UIKit)
    @Test func lightThemeHasWhiteBackground() {
        let theme = ReaderTheme.light
        let bg = theme.backgroundColor
        // Light theme background should be white or near-white
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(bg.getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(r > 0.9)
        #expect(g > 0.9)
        #expect(b > 0.9)
    }

    @Test func lightThemeHasDarkText() {
        let theme = ReaderTheme.light
        let text = theme.textColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(text.getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(r < 0.2)
        #expect(g < 0.2)
        #expect(b < 0.2)
    }

    @Test func sepiaThemeHasWarmBackground() {
        let theme = ReaderTheme.sepia
        let bg = theme.backgroundColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(bg.getRed(&r, green: &g, blue: &b, alpha: &a))
        // Sepia should be warm-toned: red > blue
        #expect(r > b)
        #expect(r > 0.8)
    }

    @Test func darkThemeHasDarkBackground() {
        let theme = ReaderTheme.dark
        let bg = theme.backgroundColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(bg.getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(r < 0.2)
        #expect(g < 0.2)
        #expect(b < 0.2)
    }

    @Test func darkThemeHasLightText() {
        let theme = ReaderTheme.dark
        let text = theme.textColor
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(text.getRed(&r, green: &g, blue: &b, alpha: &a))
        #expect(r > 0.8)
        #expect(g > 0.8)
        #expect(b > 0.8)
    }

    @Test func allThemesHaveSecondaryTextColor() {
        for theme in ReaderTheme.allCases {
            let secondary = theme.secondaryTextColor
            // Secondary text should exist and be non-nil
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #expect(secondary.getRed(&r, green: &g, blue: &b, alpha: &a))
            #expect(a > 0)
        }
    }
    #endif

    // MARK: - Default

    @Test func defaultThemeIsLight() {
        #expect(ReaderTheme.default == .light)
    }
}
