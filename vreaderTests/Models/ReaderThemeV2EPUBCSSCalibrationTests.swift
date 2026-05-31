// Purpose: Tests for feature #70 WI-3 — the EPUB path feeds the calibrated
// `.epub` font-size value into `ReaderThemeV2.epubOverrideCSS`. Verifies the
// calibrated value reaches the injected CSS AND that Bug #57's cascade-
// neutralization selectors are NOT regressed (the literal "no regression in
// bug #57" acceptance item).

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

@Suite("ReaderThemeV2EPUBCSSCalibration")
struct ReaderThemeV2EPUBCSSCalibrationTests {

    #if canImport(UIKit)

    private let calibrator = FontSizeCalibrator()

    // MARK: - Calibrated value reaches the injected CSS

    /// `epubOverrideCSS` emits `font-size: <value>px` for the value it is
    /// given — and when fed the calibrator's `.epub` mapping, that calibrated
    /// value (not the raw unified value) is what lands in the CSS.
    @Test func epubOverrideCSSEmitsCalibratedFontSize() {
        let unified: CGFloat = 24
        let calibrated = calibrator.calibratedSize(forUnified: unified, target: .epub)
        let css = ReaderThemeV2.paper.epubOverrideCSS(fontSize: calibrated)
        // epubOverrideCSS formats the size as "%.1f".
        let expected = "font-size: \(String(format: "%.1f", calibrated))px"
        #expect(css.contains(expected))
    }

    /// The injected `html, body` font-size is the calibrator's `.epub`
    /// mapping of the unified value — the routing seam, not a raw passthrough
    /// of `typography.fontSize` by some other path.
    ///
    /// Bug #280: the shipped `.epub` multiplier is now `1.0` (sim-measured
    /// cap-height parity with TXT — see `FontSizeCalibration.swift`), so the
    /// calibrated EPUB value *equals* the raw unified value by design. This
    /// test therefore asserts the value MATCHES the calibrator output (the
    /// real invariant), not that it differs from raw (an assumption that only
    /// held under the un-verified 1.12 estimate).
    @Test func injectedFontSizeIsCalibratorEpubMapping() {
        let unified: CGFloat = 24
        let calibrated = calibrator.calibratedSize(forUnified: unified, target: .epub)
        let css = ReaderThemeV2.paper.epubOverrideCSS(fontSize: calibrated)
        let calibratedString = "font-size: \(String(format: "%.1f", calibrated))px"
        #expect(css.contains(calibratedString))
    }

    // MARK: - Bug #57 no-regression (the real selectors)

    /// Bug #57's cascade neutralization for the enumerated text elements must
    /// still be present — `font-size: inherit !important` inside the
    /// `p, div, span, li, td, th, dd, dt, blockquote, figcaption` rule.
    @Test func bug57TextElementInheritRuleStillPresent() {
        let css = ReaderThemeV2.paper.epubOverrideCSS(fontSize: 24)
        #expect(css.contains("p, div, span, li, td, th, dd, dt, blockquote, figcaption"))
        // The enumerated-text-element rule flattens font-size.
        #expect(css.contains("font-size: inherit !important"))
    }

    /// Bug #294: the flatten list must include the HTML5 semantic wrappers
    /// (`section`/`article`/`aside`/`main`/`header`/`footer`/`figure`) and the
    /// legacy `<font>` element — CJK EPUBs commonly wrap prose in such a
    /// container carrying its own em/% size, which compounds past the 16px base
    /// otherwise. Mirrors the FIXED Foliate #261 widening
    /// (`FoliateStyleMapper`).
    @Test func bug294CJKWrapperElementsFlattened() {
        let css = ReaderThemeV2.paper.epubOverrideCSS(fontSize: 16)
        // Assert the exact widened selector tail so a bare substring like
        // "font" (which appears throughout the CSS as font-size/font-family)
        // can't accidentally pass — the wrappers must be in the flatten rule.
        #expect(
            css.contains(
                "blockquote, figcaption, section, article, aside, main, header, footer, figure, font"
            ),
            "EPUB flatten list must widen to the HTML5 wrappers + <font> (Foliate #261 parity)"
        )
    }

    /// Bug #57: headings keep the book's own relative sizing via
    /// `font-size: revert !important` inside the `h1..h6` rule.
    @Test func bug57HeadingRevertRuleStillPresent() {
        let css = ReaderThemeV2.paper.epubOverrideCSS(fontSize: 24)
        #expect(css.contains("h1,h2,h3,h4,h5,h6"))
        #expect(css.contains("font-size: revert !important"))
    }

    /// Bug #57: the `body *` universal selector applies to `font-family`
    /// ONLY — it must NOT carry a `font-size` declaration. This guards
    /// against the v1-plan mis-statement (`body * { font-size: inherit }`).
    @Test func bug57BodyUniversalSelectorIsFontFamilyOnly() {
        let css = ReaderThemeV2.paper.epubOverrideCSS(fontSize: 24)
        #expect(css.contains("body * { "))
        #expect(css.contains("font-family: inherit !important"))
        // Extract the `body * { ... }` rule and assert it has no font-size.
        if let range = css.range(of: "body * { ") {
            let afterSelector = css[range.upperBound...]
            if let endBrace = afterSelector.range(of: "}") {
                let ruleBody = afterSelector[..<endBrace.lowerBound]
                #expect(!ruleBody.contains("font-size"))
            } else {
                Issue.record("body * rule has no closing brace")
            }
        } else {
            Issue.record("body * selector not found")
        }
    }

    // MARK: - Boundary calibrated values

    /// A calibrated value at the clamp edges still produces valid CSS with a
    /// `font-size: <n>px` declaration.
    @Test func boundaryCalibratedValuesProduceValidCSS() {
        for unified in [CGFloat(12), 64] {
            let calibrated = calibrator.calibratedSize(forUnified: unified, target: .epub)
            let css = ReaderThemeV2.paper.epubOverrideCSS(fontSize: calibrated)
            #expect(css.contains("font-size: \(String(format: "%.1f", calibrated))px"))
            // Calibrated EPUB value stays within the text band 12...64.
            #expect(calibrated >= 12 && calibrated <= 64)
        }
    }

    /// The calibrated EPUB value at the maximum unified size (64) is clamped
    /// to the text band — it never exceeds 64, so the injected CSS never
    /// requests an out-of-band size.
    @Test func calibratedEPUBValueAtMaxIsClampedToTextBand() {
        let calibrated = calibrator.calibratedSize(forUnified: 64, target: .epub)
        #expect(calibrated == 64)
        let css = ReaderThemeV2.paper.epubOverrideCSS(fontSize: calibrated)
        #expect(css.contains("font-size: 64.0px"))
    }

    /// The EPUB target's calibrated mapping is consistent across themes —
    /// `epubOverrideCSS` font-size does not depend on the theme.
    @Test func calibratedFontSizeIsThemeIndependent() {
        let calibrated = calibrator.calibratedSize(forUnified: 30, target: .epub)
        let sizeString = "font-size: \(String(format: "%.1f", calibrated))px"
        for theme in [ReaderThemeV2.paper, .sepia, .dark, .oled, .photo] {
            #expect(theme.epubOverrideCSS(fontSize: calibrated).contains(sizeString))
        }
    }

    // MARK: - WI-3 routing seam (the actual EPUBReaderContainerView wiring)

    /// `EPUBReaderContainerView.calibratedEPUBFontSize(for:)` is the pure
    /// helper the container's `epubOverrideCSS` call site uses. It MUST
    /// return the calibrator's `.epub` mapping of the store's unified font
    /// size — a regression to the raw `typography.fontSize` is caught here.
    @Test @MainActor func containerHelperRoutesThroughCalibratorEpubTarget() {
        let store = ReaderSettingsStore(
            defaults: UserDefaults(suiteName: "EPUBCSSCalibTests-\(UUID().uuidString)")!
        )
        for unified in [CGFloat(12), 18, 24, 40, 64] {
            store.typography.fontSize = unified
            let helperValue = EPUBReaderContainerView.calibratedEPUBFontSize(for: store)
            let expected = store.calibrator.calibratedSize(forUnified: unified, target: .epub)
            #expect(helperValue == expected)
        }
    }

    /// The container helper's value is the calibrator's `.epub` mapping of the
    /// store's unified `typography.fontSize` — the routing invariant.
    ///
    /// Bug #280: the `.epub` multiplier is now `1.0` (sim-measured cap-height
    /// parity with TXT), so at unified 24 the helper correctly returns 24 —
    /// equal to raw by design, not by a missing-calibration bug. The assertion
    /// is against the calibrator output (the source of truth), which catches a
    /// regression to a hard-coded constant or the wrong target just as a
    /// `!= raw` check would have under a `> 1.0` multiplier.
    @Test @MainActor func containerHelperMatchesCalibratorEpubMapping() {
        let store = ReaderSettingsStore(
            defaults: UserDefaults(suiteName: "EPUBCSSCalibTests-\(UUID().uuidString)")!
        )
        store.typography.fontSize = 24
        let helperValue = EPUBReaderContainerView.calibratedEPUBFontSize(for: store)
        #expect(helperValue == store.calibrator.calibratedSize(forUnified: 24, target: .epub))
    }

    #endif
}
