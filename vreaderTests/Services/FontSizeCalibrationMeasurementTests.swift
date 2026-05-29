// Purpose: Bug #280 — empirically MEASURE the cross-format cap-height
// multipliers that FontSizeCalibrationProfile.standard claims, instead of
// trusting the 1.12 "conservative estimate" that was never device-verified.
//
// The calibration model (see FontSizeCalibratorTests.swift header):
//   multiplier(T) = capHeight(txt) / capHeight(T)
// at unified size 24, default content-size category (.large), iPhone 17 Pro
// Sim. txt is the anchor (1.0 by construction).
//
// How each cap-height is measured here, mirroring the PRODUCTION render path:
//   - TXT: UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize:))
//     — exactly what TXTAttributedStringBuilder.build constructs. At the
//     default content-size category the UIFontMetrics wrap is the identity.
//     Cap-height = the scaled font's .capHeight.
//   - EPUB: a live WKWebView loaded with the SAME body CSS
//     ReaderThemeV2.epubOverrideCSS emits (font-size: <px>px; font-family:
//     -apple-system, system-ui, sans-serif). Cap-height read via Canvas
//     measureText(...).actualBoundingBoxAscent on a capital glyph — the true
//     rendered cap-height in CSS px, directly comparable to UIKit's .capHeight
//     (NOT getBoundingClientRect, which yields the line-box height, a
//     font-metric-dependent value that is not the cap-height).
//   - Foliate: identical WKWebView measurement with the SAME body CSS
//     FoliateStyleMapper.themeCSS emits (font-size: <px>px; no body
//     font-family, so the WebKit UA default font applies). NOTE: this UA
//     default does NOT resolve to the same face as EPUB's
//     `-apple-system` stack — the measured cap-heights differ (EPUB ~16.91
//     vs Foliate ~15.89 at 24px), which is exactly why the two targets get
//     different multipliers (epub 1.0 vs foliate 1.06).
//
// These are SYNCHRONOUS layout reads once the document's first paint settles
// (Canvas measureText needs no rAF; it is a synchronous text-shaping call), so
// they work in the unit-test host without a virtual-display rAF dependency.
//
// @coordinates-with: FontSizeCalibration.swift (the literals under test),
//   FontSizeCalibrator.swift, ReaderThemeV2+EPUBCSS.swift, FoliateStyleMapper.swift

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
import WebKit
@testable import vreader

@MainActor
@Suite("FontSizeCalibration measurement (bug #280)")
struct FontSizeCalibrationMeasurementTests {

    /// The reference unified size the documented derivation uses.
    private static let referenceUnified: CGFloat = 24

    /// A capital glyph with no descender and a clean flat cap — gives a stable
    /// cap-height read in both UIKit and Canvas.
    private static let measureGlyph = "H"

    // MARK: - UIKit (TXT anchor) cap-height

    /// Cap-height of the TXT anchor font at point size `pt`, constructed
    /// EXACTLY as TXTAttributedStringBuilder.build does: system font wrapped by
    /// UIFontMetrics.default.scaledFont. At the default content-size category
    /// the wrap is the identity, so this is the on-screen TXT cap-height.
    private func txtCapHeight(pt: CGFloat) -> CGFloat {
        let base = UIFont.systemFont(ofSize: pt)
        let scaled = UIFontMetrics.default.scaledFont(for: base)
        return scaled.capHeight
    }

    // MARK: - WKWebView cap-height (EPUB / Foliate)

    /// Loads a minimal document, applies `bodyFontCSS` to <body>, then measures
    /// the rendered cap-height of `measureGlyph` in CSS px via a Canvas
    /// TextMetrics read. `bodyFontCSS` is the `font-size`/`font-family` pair the
    /// production engine injects on `html, body`.
    private func webCapHeight(bodyFontCSS: String) async throws -> CGFloat {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let delegate = MeasureLoadWaiter()
        webView.navigationDelegate = delegate
        let html = """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html, body { \(bodyFontCSS) margin:0; padding:0; }</style>
        </head><body><span id="m">\(Self.measureGlyph)</span></body></html>
        """
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            delegate.onFinish = { cont.resume() }
            webView.loadHTMLString(html, baseURL: nil)
        }
        // Read the computed font of the measured element and shape the glyph in
        // a canvas; actualBoundingBoxAscent of a capital letter is its rendered
        // cap-height in CSS px. This is what the user perceives as glyph size.
        let js = """
        (function(){
          var el = document.getElementById('m');
          var cs = getComputedStyle(el);
          var c = document.createElement('canvas');
          var ctx = c.getContext('2d');
          ctx.font = cs.font || (cs.fontSize + ' ' + cs.fontFamily);
          var tm = ctx.measureText('\(Self.measureGlyph)');
          return tm.actualBoundingBoxAscent;
        })()
        """
        guard let raw = try await webView.measureString(js), let value = Double(raw) else {
            throw MeasurementError.noResult
        }
        return CGFloat(value)
    }

    private enum MeasurementError: Error { case noResult }

    // MARK: - The measurement (RED on the un-tuned 1.12 literals)

    /// MEASURE the EPUB + Foliate cap-height multipliers at the reference
    /// unified size and assert FontSizeCalibrationProfile.standard matches the
    /// measured ratio within a tight tolerance.
    ///
    /// MEASURE the EPUB + Foliate cap-height multipliers DIRECTLY per the
    /// documented derivation: render each target at the SAME numeric size as the
    /// TXT anchor (the unified value) and compute
    ///   multiplier(T) = capHeight(txt) / capHeight(T at the unified size).
    /// This is independent of whatever literal the profile currently ships, so
    /// the measured number is a clean target value, not a value contaminated by
    /// the current 1.12 size already applied.
    ///
    /// Render path mirrored exactly:
    ///   - txt: UIFont.systemFont(ofSize: unified) via UIFontMetrics wrap.
    ///   - epub: WKWebView body CSS `font-size: <unified>px; font-family:
    ///     -apple-system, system-ui, sans-serif` (the .system stack
    ///     ReaderThemeV2.epubOverrideCSS injects).
    ///   - foliate: WKWebView body CSS `font-size: <unified>px;` with the
    ///     default UA font-family (FoliateStyleMapper emits no body font-family
    ///     for .system).
    @Test func measuredMultipliersMatchTheStandardProfile() async throws {
        let unified = Self.referenceUnified

        // Anchor: TXT cap-height at the unified size (the .txt multiplier is 1.0
        // so the calibrated .txt size equals the unified value).
        let txtCap = txtCapHeight(pt: unified)

        // EPUB: cap-height of the .system stack rendered at the unified px.
        let epubStack = ReaderTypography.cssFontStack(for: .system)
        let epubCap = try await webCapHeight(
            bodyFontCSS: "font-size: \(unified)px; font-family: \(epubStack);"
        )

        // Foliate: default UA font-family rendered at the unified px.
        let foliateCap = try await webCapHeight(
            bodyFontCSS: "font-size: \(unified)px;"
        )

        // CONTROL: the same .system stack at a totally different size (40px)
        // must yield the SAME multiplier — proves the ratio is size-invariant
        // (linear) and the canvas read isn't producing a size-dependent
        // artefact. If the control disagrees with the reference, the
        // methodology is unsound and we must NOT re-tune off it.
        let controlSize: CGFloat = 40
        let txtCapControl = txtCapHeight(pt: controlSize)
        let epubCapControl = try await webCapHeight(
            bodyFontCSS: "font-size: \(controlSize)px; font-family: \(epubStack);"
        )

        // multiplier(T) = capHeight(txt) / capHeight(T) at the unified size.
        let epubMeasured = txtCap / epubCap
        let foliateMeasured = txtCap / foliateCap
        let epubControlMultiplier = txtCapControl / epubCapControl

        // Print the raw measurements for the verification record.
        print("BUG280-MEASURE referenceUnified=\(unified)")
        print("BUG280-MEASURE txtCap=\(txtCap) epubCap=\(epubCap) foliateCap=\(foliateCap)")
        print("BUG280-MEASURE epubMeasuredMultiplier=\(epubMeasured) foliateMeasuredMultiplier=\(foliateMeasured)")
        print("BUG280-MEASURE controlSize=\(controlSize) txtCapControl=\(txtCapControl) epubCapControl=\(epubCapControl) epubControlMultiplier=\(epubControlMultiplier)")

        // Methodology self-check: the multiplier must be size-invariant.
        #expect(abs(epubMeasured - epubControlMultiplier) <= 0.02,
                "EPUB multiplier must be size-invariant: ref \(epubMeasured) vs control \(epubControlMultiplier)")

        // The shipped literals must equal the freshly-measured ratio within a
        // tight tolerance. RED on 1.12 if the measurement says otherwise.
        let tolerance = 0.03
        #expect(abs(FontSizeCalibrationProfile.standard.epub - epubMeasured) <= tolerance,
                "standard.epub (\(FontSizeCalibrationProfile.standard.epub)) must match measured \(epubMeasured)")
        #expect(abs(FontSizeCalibrationProfile.standard.foliate - foliateMeasured) <= tolerance,
                "standard.foliate (\(FontSizeCalibrationProfile.standard.foliate)) must match measured \(foliateMeasured)")
    }
}

/// Navigation delegate that fires once the measurement document finishes
/// loading (or fails), so the cap-height read happens after first layout and
/// a load failure resolves the await instead of hanging the test host. On
/// failure the continuation still resumes; the subsequent JS read then throws
/// `MeasurementError.noResult` (the element won't exist), surfacing a clean
/// test failure rather than a CI hang.
@MainActor
private final class MeasureLoadWaiter: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resolve()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resolve()
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resolve()
    }
    private func resolve() {
        onFinish?()
        onFinish = nil
    }
}

private extension WKWebView {
    /// Async wrapper that coerces the JS result to a Sendable String so the
    /// continuation resume is free of Swift 6 data-race diagnostics.
    func measureString(_ js: String) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            evaluateJavaScript("String(\(js))") { value, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: value as? String) }
            }
        }
    }
}
#endif
