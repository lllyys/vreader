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

    private func makeStore(
        fontSize: CGFloat, lineSpacing: CGFloat = 1.4, theme: ReaderThemeV2 = .paper
    ) -> ReaderSettingsStore {
        let s = ReaderSettingsStore(
            defaults: UserDefaults(suiteName: "FoliateSpikeThemeCSSTests-\(UUID().uuidString)")!
        )
        s.typography.fontSize = fontSize
        s.typography.lineSpacing = lineSpacing
        s.theme = theme
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
        // Bug #280: EPUB and Foliate are both WebView CSS-px renderers, but
        // they do NOT share a multiplier. Sim-measured cap-heights at unified
        // 24 (see `FontSizeCalibrationMeasurementTests`) show EPUB's
        // `-apple-system` stack renders at TXT parity (multiplier 1.0) while
        // Foliate's default UA font renders marginally smaller-capped
        // (multiplier 1.06). The prior assertion that the two ratios are
        // identical encoded the un-verified shared-1.12 estimate; the real
        // invariant is that each web target sits within the ±25% band of the
        // TXT anchor (asserted above), not that they equal each other.
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

    // MARK: - Feature #93: AZW3/MOBI theme-color parity

    /// A paper-theme store's `themeCSS` injects the theme paper as the iframe
    /// `body` background (the `background` shorthand neutralizes the
    /// publisher's `background-image`).
    @Test func themeCSSEmitsThemePaperBackground() {
        let css = FoliateSpikeView.themeCSS(for: makeStore(fontSize: 18, theme: .paper))!
        #expect(css.contains("body { background: rgb(250,246,234) !important; }"))
    }

    /// …and the theme ink as the body text color.
    @Test func themeCSSEmitsThemeInk() {
        let css = FoliateSpikeView.themeCSS(for: makeStore(fontSize: 18, theme: .paper))!
        #expect(css.contains("body { color: rgb(29,26,20) !important; }"))
    }

    /// Dark theme injects the dark paper + dark ink — the whole point of the
    /// feature (a publisher's near-black text becomes legible).
    @Test func themeCSSDarkThemeEmitsDarkPaperAndInk() {
        let css = FoliateSpikeView.themeCSS(for: makeStore(fontSize: 18, theme: .dark))!
        #expect(css.contains("body { background: rgb(33,32,28) !important; }"))
        #expect(css.contains("body { color: rgb(216,210,197) !important; }"))
    }

    /// A themed store also emits the descendant `color: inherit` reset (incl.
    /// legacy `<font>`) so publisher per-element ink yields to the theme ink.
    @Test func themeCSSEmitsDescendantColorResetWhenThemed() {
        let css = FoliateSpikeView.themeCSS(for: makeStore(fontSize: 18, theme: .dark))!
        #expect(css.contains("font { color: inherit !important; }"))
    }

    /// A `nil` store (previews / tests) emits NO color/background/descendant
    /// rules — the font-size-only fallback is preserved (regression guard).
    @Test func themeCSSNilStoreEmitsNoColorRules() {
        let css = FoliateSpikeView.themeCSS(for: nil)!
        #expect(!css.contains("body { background:"))
        #expect(!css.contains("body { color:"))
        #expect(!css.contains("color: inherit"))
    }

    /// Photo theme is EXCLUDED from color theming — its `paperColor` is an
    /// alpha overlay for a background IMAGE; applying it would bleed the
    /// publisher image. Photo-theme AZW3 keeps the font-size-only CSS.
    @Test func themeCSSPhotoThemeEmitsNoColorRules() {
        let css = FoliateSpikeView.themeCSS(for: makeStore(fontSize: 18, theme: .photo))!
        #expect(!css.contains("body { background:"))
        #expect(!css.contains("body { color:"))
        #expect(!css.contains("color: inherit"))
    }

    /// Switching the store's theme changes the emitted colors — drives the
    /// live-switch contract (`updateUIView` diffs the themeCSS string and
    /// re-pushes `setStyles`).
    @Test func themeCSSColorRulesChangeWithTheme() {
        let store = makeStore(fontSize: 18, theme: .paper)
        let lightCSS = FoliateSpikeView.themeCSS(for: store)!
        store.theme = .dark
        let darkCSS = FoliateSpikeView.themeCSS(for: store)!
        #expect(lightCSS.contains("rgb(250,246,234)"))
        #expect(darkCSS.contains("rgb(33,32,28)"))
        #expect(lightCSS != darkCSS)
    }

    // MARK: - Feature #93: theme CSS-color accessors

    @Test(arguments: [
        (ReaderThemeV2.paper, "rgb(250,246,234)", "rgb(29,26,20)"),
        (ReaderThemeV2.dark,  "rgb(33,32,28)",    "rgb(216,210,197)"),
    ])
    func themeColorCSSAccessors(theme: ReaderThemeV2, paper: String, ink: String) {
        #expect(theme.paperColorCSS == paper)
        #expect(theme.inkColorCSS == ink)
    }

    // MARK: - Feature #93: host-shell background uses the OUTER token

    /// The defensive host-shell fill uses the theme's OUTER `backgroundColor`
    /// (matching EPUB's `html` frame), NOT `paperColor`. Nil store / Photo
    /// theme → no host fill (keep the WebView default).
    @Test func hostShellBackgroundColorUsesOuterToken() {
        let dark = makeStore(fontSize: 18, theme: .dark)
        #expect(FoliateSpikeView.hostShellBackgroundColor(for: dark) == ReaderThemeV2.dark.backgroundColor)
        #expect(FoliateSpikeView.hostShellBackgroundColor(for: nil) == nil)
        let photo = makeStore(fontSize: 18, theme: .photo)
        #expect(FoliateSpikeView.hostShellBackgroundColor(for: photo) == nil)
    }
}

#endif
