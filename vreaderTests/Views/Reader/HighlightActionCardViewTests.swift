// Purpose: Feature #64 WI-4 — tests for the testable pure logic of the
// unified highlight-action popover views: `HighlightPopoverSwatch.color`,
// the stored-color-name → swatch mapper.
//
// The SwiftUI view bodies (`HighlightActionCardView` + its subviews) are
// purely presentational and exercised end-to-end in the Gate-5 slice
// verification (WI-6..10); the unit-testable surface is the swatch mapper,
// which must cover the real stored palette plus legacy / unknown fallback.

#if canImport(UIKit)
import Testing
import SwiftUI
import UIKit
@testable import vreader

@Suite("HighlightActionCardView — swatch mapper")
struct HighlightActionCardViewTests {

    /// The 4 named picker colors map to `NamedHighlightColor.hex` exactly.
    @Test(arguments: [
        ("yellow", NamedHighlightColor.yellow),
        ("pink",   NamedHighlightColor.pink),
        ("green",  NamedHighlightColor.green),
        ("blue",   NamedHighlightColor.blue),
    ])
    func swatch_namedColors_mapToHex(_ stored: String, _ expected: NamedHighlightColor) {
        let resolved = HighlightPopoverSwatch.color(for: stored)
        let expectedColor = Color(readerHexString: expected.hex)
        #expect(expectedColor != nil)
        #expect(resolved == expectedColor)
    }

    /// A legacy / unknown stored value (older hex, empty, a future custom
    /// color) falls back to yellow — mirroring `HighlightPaintColor` /
    /// `FoliateHighlightRenderer.foliateColor`.
    @Test(arguments: ["#ff00ff", "", "purple", "orange", "  ", "YELLOW"])
    func swatch_unknownStoredValue_fallsBackToYellow(_ stored: String) {
        // "YELLOW" is also unknown — `NamedHighlightColor.from` is
        // case-sensitive (the storage schema is always lowercased).
        let resolved = HighlightPopoverSwatch.color(for: stored)
        #expect(resolved == Color(readerHexString: NamedHighlightColor.yellow.hex))
    }
}
#endif
