// Purpose: Tests for HighlightPaintColor (stored-color-name → UIColor
// resolver) and PaintedHighlight (the range + color-name value the TXT/MD
// highlight painter threads). Bug #208 / GH #776.

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("HighlightPaintColor")
struct HighlightPaintColorTests {

    /// Extracts RGBA components for tolerant comparison — `UIColor ==` is
    /// exact, and round-tripping a hex string through CGFloat division can
    /// leave sub-ULP drift.
    private func rgba(_ color: UIColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    /// Asserts `color`'s channels match the `#RRGGBB` swatch at `alpha`.
    private func expectColor(_ color: UIColor, matchesHex hex: String, alpha: CGFloat) {
        var trimmed = hex
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        let value = UInt32(trimmed, radix: 16)!
        let expR = CGFloat((value >> 16) & 0xff) / 255.0
        let expG = CGFloat((value >> 8) & 0xff) / 255.0
        let expB = CGFloat(value & 0xff) / 255.0
        let got = rgba(color)
        let tol: CGFloat = 0.001
        #expect(abs(got.r - expR) < tol)
        #expect(abs(got.g - expG) < tol)
        #expect(abs(got.b - expB) < tol)
        #expect(abs(got.a - alpha) < tol)
    }

    @Test("each named color resolves to its design swatch at fill alpha")
    func namedColorsResolveToDesignSwatch() {
        for named in NamedHighlightColor.allCases {
            let resolved = HighlightPaintColor.fill(for: named.rawValue)
            expectColor(resolved, matchesHex: named.hex, alpha: HighlightPaintColor.fillAlpha)
        }
    }

    @Test("pink resolves to a non-yellow color (the Bug #208 symptom)")
    func pinkDoesNotResolveToYellow() {
        let pink = HighlightPaintColor.fill(for: "pink")
        let yellow = HighlightPaintColor.fill(for: "yellow")
        #expect(rgba(pink) != rgba(yellow),
                "a pink highlight must not paint with the yellow fill")
        expectColor(pink, matchesHex: NamedHighlightColor.pink.hex,
                    alpha: HighlightPaintColor.fillAlpha)
    }

    @Test("unknown or legacy color values fall back to yellow",
          arguments: ["", "orange", "#f0d25a", "YELLOW", " yellow ", "rgb(1,2,3)"])
    func unknownOrLegacyValuesFallBackToYellow(_ stored: String) {
        let resolved = HighlightPaintColor.fill(for: stored)
        expectColor(resolved, matchesHex: NamedHighlightColor.yellow.hex,
                    alpha: HighlightPaintColor.fillAlpha)
    }

    @Test("search highlight stays systemYellow at fill alpha (unchanged by Bug #208)")
    func searchHighlightStaysSystemYellow() {
        let expected = UIColor.systemYellow.withAlphaComponent(HighlightPaintColor.fillAlpha)
        #expect(rgba(HighlightPaintColor.searchHighlight) == rgba(expected))
    }
}

@Suite("PaintedHighlight")
struct PaintedHighlightTests {

    @Test("carries range and color name")
    func carriesRangeAndColor() {
        let h = PaintedHighlight(range: NSRange(location: 3, length: 7), colorName: "pink")
        #expect(h.range == NSRange(location: 3, length: 7))
        #expect(h.colorName == "pink")
    }

    @Test("equality compares both range and color name")
    func equality() {
        let base = PaintedHighlight(range: NSRange(location: 0, length: 5), colorName: "green")
        #expect(base == PaintedHighlight(range: NSRange(location: 0, length: 5), colorName: "green"))
        #expect(base != PaintedHighlight(range: NSRange(location: 0, length: 5), colorName: "blue"))
        #expect(base != PaintedHighlight(range: NSRange(location: 1, length: 5), colorName: "green"))
    }
}
#endif
