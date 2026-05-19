// Purpose: Tests for feature #70 WI-4 — first-time AZW3/MOBI font-size wiring.
// `FoliateSpikeView` builds a calibrated `themeCSS` (font-size + line-height)
// routed through the calibrator's `.foliate` target and pushes it via
// `readerAPI.setStyles`. Tests exercise the pure CSS-construction seam
// (`FoliateSpikeView.themeCSS(for:)`), not the WKWebView.

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("FoliateSpikeThemeCSS")
@MainActor
struct FoliateSpikeThemeCSSTests {

    private func makeStore(fontSize: CGFloat, lineSpacing: CGFloat = 1.4) -> ReaderSettingsStore {
        let s = ReaderSettingsStore(
            defaults: UserDefaults(suiteName: "FoliateSpikeThemeCSSTests-\(UUID().uuidString)")!
        )
        s.typography.fontSize = fontSize
        s.typography.lineSpacing = lineSpacing
        return s
    }

    // MARK: - The helper builds calibrated CSS

    /// `FoliateSpikeView.themeCSS(for:)` builds a `body { font-size: <n>px }`
    /// rule whose size is the *calibrated Foliate* value for the store's
    /// unified font size — NOT the raw unified value.
    @Test func themeCSSUsesCalibratedFoliateFontSize() {
        let store = makeStore(fontSize: 24)
        let css = FoliateSpikeView.themeCSS(for: store)
        #expect(css != nil)
        let calibratedFoliate = store.calibrator.calibratedFoliateSize(forUnified: 24)
        #expect(css!.contains("font-size: \(calibratedFoliate)px"))
    }

    /// For the shipped `.foliate` multiplier (`> 1.0`), the calibrated value
    /// differs from the raw unified value — the CSS carries the calibrated
    /// one, not `24px`.
    @Test func themeCSSCalibratedValueDiffersFromRawUnified() {
        let store = makeStore(fontSize: 24)
        let calibrated = store.calibrator.calibratedFoliateSize(forUnified: 24)
        #expect(calibrated != 24)
        let css = FoliateSpikeView.themeCSS(for: store)!
        #expect(css.contains("font-size: \(calibrated)px"))
        #expect(!css.contains("font-size: 24px"))
    }

    /// The helper emits the line-height from `typography.lineSpacing`.
    @Test func themeCSSEmitsLineHeight() {
        let store = makeStore(fontSize: 20, lineSpacing: 1.6)
        let css = FoliateSpikeView.themeCSS(for: store)!
        // FoliateStyleMapper formats line-height to one decimal place.
        #expect(css.contains("line-height: 1.6"))
    }

    // MARK: - FoliateStyleMapper emits the calibrated value

    /// `FoliateStyleMapper.themeCSS(fontSize: calibratedFoliateValue, …)`
    /// emits `body { font-size: <calibratedValue>px … }`.
    @Test func styleMapperEmitsCalibratedFoliateValue() {
        let calibrator = FontSizeCalibrator()
        let calibrated = calibrator.calibratedFoliateSize(forUnified: 30)
        let css = FoliateStyleMapper.themeCSS(
            fontSize: calibrated,
            lineHeight: 1.4,
            fontFamily: nil,
            textColor: nil,
            backgroundColor: nil
        )
        #expect(css.contains("font-size: \(calibrated)px !important"))
    }

    // MARK: - clampFontSize is a verified no-op

    /// The calibrated Foliate value is already inside `8...72`, so
    /// `FoliateJSEscaper.clampFontSize` leaves it unchanged for every unified
    /// value across the full `12...64` range — the "verified no-op" claim.
    @Test func clampFontSizeIsNoOpForCalibratedFoliateValues() {
        let calibrator = FontSizeCalibrator()
        for unified in stride(from: CGFloat(12), through: 64, by: 1) {
            let calibrated = calibrator.calibratedFoliateSize(forUnified: unified)
            #expect(FoliateJSEscaper.clampFontSize(calibrated) == calibrated)
        }
    }

    // MARK: - Bridge-safety: the setStyles payload is escaped

    /// The `setStyles` JS payload must be escaped via
    /// `FoliateJSEscaper.escapeForJSString` (rule 50 bridge safety). A CSS
    /// string containing a single-quote / backslash is escaped so it cannot
    /// break out of the `setStyles('...')` JS string literal.
    @Test func setStylesPayloadIsEscapedForJS() {
        // The calibrated CSS itself has no quotes, but the escaper is the
        // contract — verify it neutralizes the JS-string-breaking chars.
        let hostile = "body { content: 'x'; }\\injected"
        let escaped = FoliateJSEscaper.escapeForJSString(hostile)
        #expect(!escaped.contains("'") || escaped.contains("\\'"))
        #expect(escaped.contains("\\\\"))
    }

    // MARK: - nil store fallback

    /// A `nil` `settingsStore` must not crash — the helper falls back to the
    /// documented default unified size (18) and still produces valid CSS.
    @Test func themeCSSWithNilStoreFallsBackToDefault() {
        let css = FoliateSpikeView.themeCSS(for: nil)
        #expect(css != nil)
        // Default unified 18 → calibrated Foliate value.
        let calibrated = FontSizeCalibrator().calibratedFoliateSize(forUnified: 18)
        #expect(css!.contains("font-size: \(calibrated)px"))
    }

    // MARK: - Boundary values

    @Test func themeCSSBoundaryUnifiedValuesProduceValidCSS() {
        for unified in [CGFloat(12), 64] {
            let store = makeStore(fontSize: unified)
            let css = FoliateSpikeView.themeCSS(for: store)!
            let calibrated = store.calibrator.calibratedFoliateSize(forUnified: unified)
            #expect(css.contains("font-size: \(calibrated)px"))
            #expect(calibrated >= 8 && calibrated <= 72)
        }
    }

    // MARK: - Cross-format consistency (the property the feature delivers)

    /// At unified 24, the rendered ratios across all four targets sit within
    /// a documented tolerance band of each other and of the TXT anchor
    /// (`1.0`) — the consistency property feature #70 exists to deliver,
    /// asserted at the value layer.
    @Test func crossFormatRatiosConsistentAtReferenceSize() {
        let calibrator = FontSizeCalibrator()
        let unified: CGFloat = 24
        let txtRatio = calibrator.calibratedSize(forUnified: unified, target: .txt) / unified
        let mdRatio = calibrator.calibratedSize(forUnified: unified, target: .md) / unified
        let epubRatio = calibrator.calibratedSize(forUnified: unified, target: .epub) / unified
        let foliateRatio = CGFloat(calibrator.calibratedFoliateSize(forUnified: unified)) / unified
        let tolerance: CGFloat = 0.25
        #expect(txtRatio == 1.0)
        #expect(abs(mdRatio - txtRatio) <= tolerance)
        #expect(abs(epubRatio - txtRatio) <= tolerance)
        #expect(abs(foliateRatio - txtRatio) <= tolerance)
        // Foliate and EPUB are both WebView CSS-px renderers — they should
        // calibrate to the same ratio (sub-pixel rounding aside).
        #expect(abs(foliateRatio - epubRatio) <= 0.5 / unified + 0.001)
    }

    // MARK: - WI-4 bridge seam: Coordinator state + setStyles JS

    /// The `Coordinator` seeds `currentThemeCSS` from `initialThemeCSS` so the
    /// `book-ready` post-init iife can apply the initial calibrated CSS even
    /// if no slider change ever fires (pre-ready belt-and-braces).
    @Test func coordinatorSeedsCurrentThemeCSSFromInitialValue() {
        let store = makeStore(fontSize: 28)
        let css = FoliateSpikeView.themeCSS(for: store)
        let coordinator = FoliateSpikeView.Coordinator(
            initialLayoutFlow: "scrolled",
            initialThemeCSS: css,
            onBookReady: { _ in },
            onError: { _ in }
        )
        #expect(coordinator.currentThemeCSS == css)
    }

    /// The default `initialThemeCSS` (omitted) leaves `currentThemeCSS` nil —
    /// keeps existing `Coordinator` call sites source-compatible.
    @Test func coordinatorCurrentThemeCSSDefaultsToNil() {
        let coordinator = FoliateSpikeView.Coordinator(
            initialLayoutFlow: "paginated",
            onBookReady: { _ in },
            onError: { _ in }
        )
        #expect(coordinator.currentThemeCSS == nil)
    }

    /// `Coordinator.setStylesJS(forCSS:)` builds a `readerAPI.setStyles('…')`
    /// call with the CSS escaped via `FoliateJSEscaper` — the bridge-safety
    /// seam for the `updateUIView` ready-path push.
    @Test func setStylesJSBuildsEscapedCall() {
        let store = makeStore(fontSize: 24)
        let css = FoliateSpikeView.themeCSS(for: store)!
        let js = FoliateSpikeView.Coordinator.setStylesJS(forCSS: css)
        #expect(js.hasPrefix("readerAPI.setStyles('"))
        #expect(js.hasSuffix("');"))
        // The calibrated font size is inside the payload.
        let calibrated = store.calibrator.calibratedFoliateSize(forUnified: 24)
        #expect(js.contains("font-size: \(calibrated)px"))
    }

    /// `setStylesJS` escapes JS-string-breaking characters so a CSS string
    /// with a single-quote / backslash cannot break out of the `setStyles('…')`
    /// literal.
    @Test func setStylesJSEscapesHostileCSS() {
        let hostile = "body { font-family: 'x'; }\\evil"
        let js = FoliateSpikeView.Coordinator.setStylesJS(forCSS: hostile)
        // The raw unescaped single-quote must not appear bare inside the
        // payload — it is escaped to \'.
        #expect(js.contains("\\'"))
        #expect(js.contains("\\\\"))
    }

    /// Gate-4 round-2 fix: the `layout-ready` message flips `isBookReady` and
    /// keeps `currentThemeCSS` intact, so the handler's reconciliation
    /// `setStyles` (which closes the post-init/pre-ready lost-update window)
    /// has the freshest CSS to apply.
    @Test func layoutReadyFlipsReadyAndPreservesThemeCSS() async {
        let store = makeStore(fontSize: 36)
        let css = FoliateSpikeView.themeCSS(for: store)
        let coordinator = FoliateSpikeView.Coordinator(
            initialLayoutFlow: "scrolled",
            initialThemeCSS: css,
            onBookReady: { _ in },
            onError: { _ in }
        )
        #expect(coordinator.isBookReady == false)
        await coordinator.handleMessage(name: "layout-ready", body: [:])
        #expect(coordinator.isBookReady == true)
        // `currentThemeCSS` survives the ready transition — the reconcile
        // `setStyles` in the handler applies exactly this value.
        #expect(coordinator.currentThemeCSS == css)
    }
}

#endif
