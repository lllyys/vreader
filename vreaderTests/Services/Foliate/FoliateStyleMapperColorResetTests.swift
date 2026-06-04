// Purpose: Feature #93 — `FoliateStyleMapper.themeCSS` must, when a text color
// is applied (AZW3/MOBI theme-color parity), ALSO emit a descendant
// `color: inherit !important` reset (mirroring EPUB's `epubOverrideCSS`) so a
// publisher's per-element ink (`<span style>`, legacy `<font color>`, container
// colors) yields to the theme ink instead of staying dark on a dark theme.
// The reset is emitted ONLY when `textColor` is non-nil, so the font-size-only
// path (feature #70, `textColor: nil`) is unchanged.
//
// @coordinates-with: FoliateStyleMapper.swift, ReaderThemeV2+EPUBCSS.swift,
//   dev-docs/plans/20260605-feature-93-azw3-theme-color-parity.md (WI-1)

import Testing
@testable import vreader

@Suite("FoliateStyleMapper — feature #93 descendant color reset")
struct FoliateStyleMapperColorResetTests {

    /// With a text color applied, the mapper emits the body color rule.
    @Test func emitsBodyColorRuleWhenTextColorSet() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.4,
            fontFamily: nil, textColor: "rgb(216,210,197)", backgroundColor: nil
        )
        #expect(css.contains("body { color: rgb(216,210,197) !important; }"))
    }

    /// The descendant color reset is emitted when a text color is applied, so
    /// publisher per-element ink resolves to the inherited body ink.
    @Test func emitsDescendantColorInheritWhenTextColorSet() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.4,
            fontFamily: nil, textColor: "rgb(216,210,197)", backgroundColor: nil
        )
        #expect(
            css.contains("color: inherit !important"),
            "A themed text color must also flatten descendant publisher ink"
        )
    }

    /// Legacy Kindle/MOBI `<font color>` is common, so the descendant reset
    /// selector set must include `font` (beyond EPUB's container list).
    @Test func descendantColorResetIncludesFontElement() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.4,
            fontFamily: nil, textColor: "rgb(216,210,197)", backgroundColor: nil
        )
        // The color-reset rule's selector list ends with `font {`.
        #expect(
            css.contains("font { color: inherit !important; }"),
            "Descendant color reset must cover legacy <font color>"
        )
    }

    /// Gate-4 finding: headings carry their own publisher color, so the reset
    /// must include `h1`-`h6` (matching EPUB) — else a book-level heading
    /// color survives `body { color }` and chapter titles mis-render on
    /// dark/sepia.
    @Test func descendantColorResetIncludesHeadings() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.4,
            fontFamily: nil, textColor: "rgb(216,210,197)", backgroundColor: nil
        )
        // The single color-reset rule's selector list begins with the headings.
        #expect(css.contains("h1, h2, h3, h4, h5, h6"))
        #expect(css.contains("h6, p, div"), "Headings must be in the color-reset selector list")
    }

    /// The font-size-only path (no text color — previews / nil store / Photo
    /// theme) must NOT emit any `color: inherit` reset — feature #70 behavior
    /// is unchanged.
    @Test func noDescendantColorResetWhenTextColorNil() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.4,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(!css.contains("color: inherit"))
        #expect(!css.contains("body { color:"))
    }

    /// The existing font-size cascade-flatten rule (`font-size: inherit`) is
    /// independent of and unaffected by the new color reset — both can coexist.
    @Test func fontSizeFlattenStillEmittedAlongsideColorReset() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.4,
            fontFamily: nil, textColor: "rgb(216,210,197)", backgroundColor: nil
        )
        #expect(css.contains("font-size: inherit !important"))
        #expect(css.contains("color: inherit !important"))
    }
}
