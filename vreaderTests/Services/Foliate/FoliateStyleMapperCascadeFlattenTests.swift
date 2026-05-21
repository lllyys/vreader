// Purpose: Bug #261 regression pin — `FoliateStyleMapper.themeCSS` must emit a
// cascade-flatten rule (mirroring EPUB's `ReaderThemeV2+EPUBCSS`) so a Kindle
// book's own `em`/`%`-based font-size CSS cannot compound against the injected
// `body` base. Before the fix, FoliateStyleMapper pinned ONLY `body` font-size,
// leaving the book's `p{font-size:1.15em}` etc. to compound (device-measured
// 31px body → 35.65px paragraphs at unified 28). The flatten rule forces text
// containers to `font-size: inherit` and headings to `font-size: revert`, so
// AZW3/MOBI body text renders at the same flat per-format size EPUB already
// delivers via bug #57 / feature #70.
//
// @coordinates-with: FoliateStyleMapper.swift, ReaderThemeV2+EPUBCSS.swift

import Testing
@testable import vreader

@Suite("FoliateStyleMapper — em-compounding cascade flatten (bug #261)")
struct FoliateStyleMapperCascadeFlattenTests {

    /// The text-container reset rule: every common text element is forced to
    /// `font-size: inherit !important`, so a book's `p{font-size:1.15em}`
    /// resolves to the inherited `body` px instead of compounding off it.
    /// This is the exact selector list EPUB uses
    /// (`ReaderThemeV2+EPUBCSS.swift`), so AZW3/MOBI gains identical
    /// compounding immunity.
    @Test func emitsTextContainerInheritRule() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 31, lineHeight: 1.4,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(
            css.contains("p, div, span, li, td, th, dd, dt, blockquote, figcaption"),
            "Must emit the EPUB-parity text-container selector list"
        )
        #expect(
            css.contains("font-size: inherit !important"),
            "Text containers must reset font-size to inherit so book em/% units cannot compound"
        )
    }

    /// Headings revert to the UA-default proportional scale (`font-size:
    /// revert`) — matching EPUB. They still scale WITH the body size but do
    /// not compound off the book's arbitrary base.
    @Test func emitsHeadingRevertRule() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 31, lineHeight: 1.4,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(
            css.contains("h1,h2,h3,h4,h5,h6"),
            "Must emit a heading selector"
        )
        #expect(
            css.contains("font-size: revert !important"),
            "Headings must revert to proportional UA scale, matching EPUB"
        )
    }

    /// `html` must be pinned to the same px as `body` so a book's `rem`-based
    /// CSS resolves against the calibrated size, not the 16px UA root default.
    /// Device measurement showed AZW3 `html` was stuck at 16px while EPUB
    /// pinned both `html` and `body`.
    @Test func pinsHTMLRootFontSize() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 31, lineHeight: 1.4,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        // The font-size base rule targets both html and body.
        #expect(
            css.contains("html, body") || css.contains("html,body"),
            "The font-size base rule must pin html as well as body"
        )
        #expect(
            css.contains("font-size: 31px !important"),
            "html/body base font-size must still carry the calibrated px with !important"
        )
    }

    /// The flatten rule must NOT introduce any color declaration — the Foliate
    /// style mapper deliberately does not theme colors (the spike never did,
    /// AZW3/MOBI theme-color parity is a separate gap). The EPUB rule includes
    /// `color: inherit`; we deliberately omit it so the no-color contract holds.
    @Test func flattenRuleAddsNoColorDeclaration() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(!css.contains("color:"), "Flatten rule must not theme color")
        #expect(!css.contains("background:"), "Flatten rule must not theme background")
    }

    /// The body font-size value still rides through unchanged across the band
    /// — the flatten rule is additive, it does not alter the calibrated size
    /// that already passed feature #70's verification.
    @Test(arguments: [8, 12, 18, 24, 31, 64, 72])
    func bodyFontSizeStillEmittedAcrossBand(_ size: Int) {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: size, lineHeight: 1.4,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(
            css.contains("font-size: \(size)px !important"),
            "Calibrated body size \(size)px must still be emitted unchanged"
        )
    }

    /// Line height continues to ride with the font size — the flatten rule
    /// inherits line-height too, so descendant line-height does not fight the
    /// body value. The body line-height declaration is still present.
    @Test func bodyLineHeightStillEmitted() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 31, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("line-height: 1.6 !important"))
    }
}
