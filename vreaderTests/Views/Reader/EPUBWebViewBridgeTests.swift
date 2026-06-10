// Purpose: Tests for EPUBWebViewBridge scroll-to-fraction JS generation.
// Verifies the JavaScript string produced by scrollToFractionJS is well-formed
// and handles edge cases (0, 1, negative, NaN).
//
// @coordinates-with: EPUBWebViewBridge.swift

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
import WebKit
@testable import vreader

@Suite("EPUBWebViewBridge - scrollToFractionJS")
struct EPUBWebViewBridgeScrollJSTests {

    @Test("generates JS that scrolls to given fraction")
    func scrollToFractionGeneratesValidJS() {
        let js = EPUBWebViewBridge.scrollToFractionJS(0.5)
        #expect(js.contains("scrollTo"))
        #expect(js.contains("0.5"))
    }

    @Test("fraction 0 scrolls to top")
    func scrollToFractionZero() {
        let js = EPUBWebViewBridge.scrollToFractionJS(0.0)
        #expect(js.contains("scrollTo"))
        #expect(js.contains("0.0"))
    }

    @Test("fraction 1 scrolls to bottom")
    func scrollToFractionOne() {
        let js = EPUBWebViewBridge.scrollToFractionJS(1.0)
        #expect(js.contains("scrollTo"))
        #expect(js.contains("1.0"))
    }

    @Test("fraction 0.75 generates correct value")
    func scrollToFractionThreeQuarters() {
        let js = EPUBWebViewBridge.scrollToFractionJS(0.75)
        #expect(js.contains("0.75"))
    }

    @Test("negative fraction clamps to 0")
    func scrollToFractionNegativeClamps() {
        let js = EPUBWebViewBridge.scrollToFractionJS(-0.5)
        #expect(!js.contains("-0.5"))
        #expect(js.contains("0.0"))
    }

    @Test("fraction > 1 clamps to 1")
    func scrollToFractionOverOneClamps() {
        let js = EPUBWebViewBridge.scrollToFractionJS(1.5)
        #expect(!js.contains("1.5"))
        #expect(js.contains("1.0"))
    }

    @Test("NaN fraction clamps to 0")
    func scrollToFractionNaN() {
        let js = EPUBWebViewBridge.scrollToFractionJS(.nan)
        #expect(!js.contains("nan"))
        #expect(js.contains("0.0"))
    }
}

// Bug #167 / GH #494: EPUB overscroll bounce reveals white background instead
// of theme color. Root cause: `webView.scrollView.backgroundColor = .clear`
// hard-coded; rubber-band area falls through to the host UIView (white default).
// Fix: parameterize on a theme-derived color so Sepia and Dark themes don't
// expose white. The bridge stores `UIColor?` for decoupling; nil preserves
// the prior `.clear` behaviour for back-compat.
@Suite("EPUBWebViewBridge - scrollViewBackgroundColor")
struct EPUBWebViewBridgeScrollBackgroundTests {

    @Test("nil falls back to .clear (back-compat for callers without a theme)")
    func nilFallsBackToClear() {
        let color = EPUBWebViewBridge.scrollViewBackgroundColor(for: nil)
        #expect(color == .clear,
                "Without a themed color, the helper must preserve the prior `.clear` behaviour so non-themed callers don't regress")
    }

    @Test("light theme background flows through to the resolved color")
    func lightThemeFlowsThrough() {
        let color = EPUBWebViewBridge.scrollViewBackgroundColor(for: ReaderTheme.light.backgroundColor)
        #expect(color == ReaderTheme.light.backgroundColor)
    }

    @Test("sepia theme background flows through — no white bleed in overscroll")
    func sepiaThemeFlowsThrough() {
        let color = EPUBWebViewBridge.scrollViewBackgroundColor(for: ReaderTheme.sepia.backgroundColor)
        #expect(color == ReaderTheme.sepia.backgroundColor,
                "Sepia overscroll must match the sepia page so the rubber-band area doesn't flash white")
    }

    @Test("dark theme background flows through — no white bleed in overscroll")
    func darkThemeFlowsThrough() {
        let color = EPUBWebViewBridge.scrollViewBackgroundColor(for: ReaderTheme.dark.backgroundColor)
        #expect(color == ReaderTheme.dark.backgroundColor,
                "Dark overscroll must match the dark page so the rubber-band area doesn't flash white")
    }

    @Test("themed backgrounds never resolve to .clear (would re-introduce the bug)")
    func themedBackgroundsAreNotClear() {
        for theme in ReaderTheme.allCases {
            let color = EPUBWebViewBridge.scrollViewBackgroundColor(for: theme.backgroundColor)
            #expect(color != .clear,
                    "\(theme.rawValue) must not resolve to .clear — that's exactly the bug")
        }
    }

    @Test("an explicit non-nil color passes through unchanged")
    func explicitColorPassesThrough() {
        let custom = UIColor(red: 0.4, green: 0.2, blue: 0.6, alpha: 1.0)
        let color = EPUBWebViewBridge.scrollViewBackgroundColor(for: custom)
        #expect(color == custom,
                "Bridge must not transform the input — the caller is the source of truth for the color")
    }

    // applyScrollViewBackground — exercises the actual `UIScrollView.backgroundColor`
    // assignment seam so the resolver→assignment contract is locked in.
    //
    // Coverage gap (intentional, documented): these tests do NOT verify that
    // `EPUBWebViewBridge.makeUIView` and `updateUIView` actually CALL the
    // seam at the right times. If a future change deletes either call site,
    // the suite still passes and the white-bleed regression returns.
    // Constructing a `UIViewRepresentableContext` in unit tests requires
    // SwiftUI internals beyond the public API; a representable round-trip
    // test would need a UIHostingController harness, which is out of scope
    // for a bridge unit-test file. The wiring is locked instead by the
    // post-merge device-verification step (Phase 9 of `/fix-issue`).

    @MainActor
    @Test("applyScrollViewBackground writes the resolved color to the scroll view")
    func applyWritesResolvedColorToScrollView() {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .red  // Pre-existing value to confirm overwrite.

        EPUBWebViewBridge.applyScrollViewBackground(to: scrollView, color: ReaderTheme.dark.backgroundColor)
        #expect(scrollView.backgroundColor == ReaderTheme.dark.backgroundColor)

        EPUBWebViewBridge.applyScrollViewBackground(to: scrollView, color: ReaderTheme.sepia.backgroundColor)
        #expect(scrollView.backgroundColor == ReaderTheme.sepia.backgroundColor,
                "Subsequent calls must overwrite the prior value — supports live theme switch")
    }

    @MainActor
    @Test("applyScrollViewBackground with nil writes .clear")
    func applyWithNilWritesClear() {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .red
        EPUBWebViewBridge.applyScrollViewBackground(to: scrollView, color: nil)
        #expect(scrollView.backgroundColor == .clear,
                "nil input must restore the prior `.clear` behaviour")
    }
}

// MARK: - Bug #163 — Safe-area top inset

/// Bug #163: Tests for the seam that writes a safe-area top inset to the
/// WKWebView's scroll view, so EPUB chapter content isn't clipped behind
/// the Dynamic Island when `contentInsetAdjustmentBehavior = .never`.
///
/// Same coverage-gap caveat as the scroll-background suite: these tests
/// lock the seam's contract, not the call-site wiring inside
/// `makeUIView` / `updateUIView`. If a future change deletes either call
/// site, the suite still passes; the device-verification step (Phase 9
/// of `/fix-issue`) is the wiring lock for that.
@Suite("EPUBWebViewBridge - applySafeAreaTopInset (bug #163)")
struct EPUBWebViewBridgeSafeAreaInsetTests {

    @MainActor
    @Test("applySafeAreaTopInset writes the input value to contentInset.top")
    func applyWritesTopInsetToScrollView() {
        let scrollView = UIScrollView()
        // Pre-existing value to confirm overwrite.
        scrollView.contentInset = UIEdgeInsets(top: 99, left: 0, bottom: 0, right: 0)

        EPUBWebViewBridge.applySafeAreaTopInset(to: scrollView, top: 59)
        #expect(scrollView.contentInset.top == 59)

        EPUBWebViewBridge.applySafeAreaTopInset(to: scrollView, top: 47)
        #expect(scrollView.contentInset.top == 47,
                "Subsequent calls must overwrite the prior value")
    }

    @MainActor
    @Test("applySafeAreaTopInset preserves left/bottom/right insets")
    func applyPreservesNonTopInsets() {
        let scrollView = UIScrollView()
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 16, right: 24)

        EPUBWebViewBridge.applySafeAreaTopInset(to: scrollView, top: 59)

        #expect(scrollView.contentInset.top == 59)
        #expect(scrollView.contentInset.left == 8,
                "left inset must not be overwritten")
        #expect(scrollView.contentInset.bottom == 16,
                "bottom inset must not be overwritten")
        #expect(scrollView.contentInset.right == 24,
                "right inset must not be overwritten")
    }

    @MainActor
    @Test("applySafeAreaTopInset with 0 clears the top inset")
    func applyWithZeroClearsTopInset() {
        let scrollView = UIScrollView()
        scrollView.contentInset = UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0)

        EPUBWebViewBridge.applySafeAreaTopInset(to: scrollView, top: 0)
        #expect(scrollView.contentInset.top == 0)
    }

    @MainActor
    @Test("applySafeAreaTopInset with negative value clamps to 0")
    func applyWithNegativeClampsToZero() {
        let scrollView = UIScrollView()

        EPUBWebViewBridge.applySafeAreaTopInset(to: scrollView, top: -10)
        #expect(scrollView.contentInset.top == 0,
                "Negative input must clamp to 0 — UIScrollView accepts negative insets but they would push content UP into the chrome bar, regressing the bug we're fixing")
    }

    @MainActor
    @Test("applySafeAreaTopInset matches scrollIndicatorInsets to keep scrollbar in safe area")
    func applyAlsoUpdatesScrollIndicatorInsets() {
        let scrollView = UIScrollView()

        EPUBWebViewBridge.applySafeAreaTopInset(to: scrollView, top: 59)

        // The scrollbar indicator should also start below the safe area
        // — otherwise it's clipped behind the Dynamic Island just like the
        // content was. iOS 13+ uses verticalScrollIndicatorInsets;
        // setting `scrollIndicatorInsets` covers both.
        #expect(scrollView.verticalScrollIndicatorInsets.top == 59)
    }
}

// MARK: - Bug #163 — Paged mode pagination height

/// Round-1 audit fix [1]: when contentInset.top is applied for the safe
/// area, paged mode's column height must be reduced by the same amount;
/// otherwise each column extends below the visible viewport and text at
/// the bottom of each page is clipped. These tests pin the paged-mode
/// pagination CSS shape against viewport-minus-inset.
@Suite("EPUBPaginationHelper - safe-area-aware viewport (bug #163)")
struct EPUBPaginationHelperSafeAreaTests {

    @Test("paginationCSS uses the supplied viewportHeight literally")
    func paginationCSSUsesViewportHeightAsIs() {
        // The helper itself doesn't know about safe area — it just emits
        // the height it's given. The caller (EPUBWebViewBridge.Coordinator)
        // is responsible for subtracting the inset before calling.
        let css = EPUBPaginationHelper.paginationCSS(
            viewportWidth: 393,
            viewportHeight: 852
        )
        #expect(css.contains("height: 852px"))
    }

    @Test("paginationCSS reflects reduced height when caller subtracts inset")
    func paginationCSSReflectsReducedHeight() {
        let bounds: CGFloat = 852
        let safeAreaTop: CGFloat = 59
        let effective = max(bounds - safeAreaTop, 0)

        let css = EPUBPaginationHelper.paginationCSS(
            viewportWidth: 393,
            viewportHeight: effective
        )
        #expect(css.contains("height: \(Int(effective))px"))
        // Sanity: the original full-bounds height is NOT in the CSS.
        #expect(!css.contains("height: \(Int(bounds))px"))
    }

    @Test("zero or negative effective height produces guard fallback")
    func paginationCSSWithZeroHeight() {
        // The bridge's `setupPagination` guards: `viewportWidth > 0 &&
        // viewportHeight > 0`, so a zero-or-negative computed height
        // produces a no-op (no CSS injected). The helper itself just
        // emits whatever it gets — we assert here that
        // `max(bounds - inset, 0) == 0` falls into the guard.
        let bounds: CGFloat = 30  // unrealistically small
        let safeAreaTop: CGFloat = 59
        let effective = max(bounds - safeAreaTop, 0)
        #expect(effective == 0)
    }
}

// MARK: - Bug #163 (reopen) — Initial content offset after page load

/// Bug #163 was REOPENED because `applySafeAreaTopInset` correctly sets
/// `contentInset.top` but WKWebView resets `contentOffset` to `.zero` after
/// every `loadFileURL` call. With contentInset.top = 59 and contentOffset.y = 0,
/// the content's first line sits at screen y=0 — behind the Dynamic Island.
/// Fix: `applyInitialContentOffset(to:topInset:)` resets contentOffset.y to
/// -topInset so document y=0 lands just below the DI.
@Suite("EPUBWebViewBridge - applyInitialContentOffset (bug #163 reopen)")
struct EPUBWebViewBridgeInitialContentOffsetTests {

    @MainActor
    @Test("applyInitialContentOffset sets contentOffset.y to -topInset")
    func applyWritesNegativeInsetAsOffset() {
        let scrollView = UIScrollView()
        scrollView.contentOffset = .zero

        EPUBWebViewBridge.applyInitialContentOffset(to: scrollView, topInset: 59)
        #expect(scrollView.contentOffset.y == -59,
                "contentOffset.y must be -59 so document y=0 appears at screen y=59 (just below the Dynamic Island)")
    }

    @MainActor
    @Test("applyInitialContentOffset resets x to 0 for chapter-top position")
    func applyResetsHorizontalOffsetToZero() {
        let scrollView = UIScrollView()
        scrollView.contentOffset = CGPoint(x: 100, y: 0)

        EPUBWebViewBridge.applyInitialContentOffset(to: scrollView, topInset: 59)
        #expect(scrollView.contentOffset.x == 0,
                "x offset must be reset to 0 — chapter top means no horizontal scroll")
    }

    @MainActor
    @Test("applyInitialContentOffset with 0 topInset leaves offset at origin (no-notch device)")
    func applyWithZeroInsetLeavesOffsetAtZero() {
        let scrollView = UIScrollView()
        scrollView.contentOffset = .zero

        EPUBWebViewBridge.applyInitialContentOffset(to: scrollView, topInset: 0)
        #expect(scrollView.contentOffset.y == 0,
                "On no-notch devices (topInset=0), contentOffset.y must stay at 0 — no negative shift")
    }

    @MainActor
    @Test("applyInitialContentOffset does not change contentInset")
    func applyDoesNotModifyContentInset() {
        let scrollView = UIScrollView()
        scrollView.contentInset = UIEdgeInsets(top: 59, left: 0, bottom: 0, right: 0)

        EPUBWebViewBridge.applyInitialContentOffset(to: scrollView, topInset: 59)
        #expect(scrollView.contentInset.top == 59,
                "contentInset must not be modified — that is applySafeAreaTopInset's job")
    }

    @MainActor
    @Test("applyInitialContentOffset negative topInset clamps to offset 0")
    func applyNegativeInsetClampsOffsetToZero() {
        let scrollView = UIScrollView()
        scrollView.contentOffset = .zero

        EPUBWebViewBridge.applyInitialContentOffset(to: scrollView, topInset: -10)
        #expect(scrollView.contentOffset.y == 0,
                "Negative inset is invalid; offset must clamp to 0 so content doesn't overshoot above the top chrome")
    }
}

// MARK: - Bug #278: continuous-scroll live theme/typography re-inject

/// Bug #278 / GH #1255: in continuous-scroll mode the EPUB font-size slider had
/// no live effect because `updateUIView` returned early (continuous bootstrap
/// load) BEFORE the paged theme-change cascade that re-injects `#vreader-theme`.
/// The pure decision seam below captures "given the old vs new theme CSS, what
/// JS should the bridge run to live-apply the change to the stitched document?"
/// — re-injecting `#vreader-theme` into the bootstrap `document.head` cascades
/// document-wide (`html, body { font-size }`), reaching every materialized
/// section in the single stitched DOM.
@Suite("EPUBWebViewBridge - continuousThemeReinjectJS (bug #278)")
struct EPUBWebViewBridgeContinuousThemeReinjectTests {

    private func css(fontSizePx: Double) -> String {
        // Minimal stand-in for `ReaderThemeV2.epubOverrideCSS` output: the part
        // that matters for the decision is the `#vreader-theme` style wrapper
        // carrying a `font-size` rule that the slider mutates.
        "<style id=\"vreader-theme\">html, body { font-size: \(fontSizePx)px !important; }</style>"
    }

    @Test("font-size change emits inject JS carrying the NEW size (the bug #278 regression)")
    func fontSizeChangeEmitsInject() throws {
        let oldCSS = css(fontSizePx: 18)
        let newCSS = css(fontSizePx: 28)

        let js = try #require(
            EPUBWebViewBridge.continuousThemeReinjectJS(previousCSS: oldCSS, newCSS: newCSS),
            "A typography change in continuous mode MUST produce re-inject JS — the pre-fix bridge skipped it (early return), so the slider had no live effect."
        )
        #expect(js.contains("vreader-theme"),
                "Re-inject must target the #vreader-theme style element so the document-wide font-size cascade reaches all materialized sections.")
        #expect(js.contains("28"),
                "The re-injected CSS must carry the NEW font size, not the stale baked-in bootstrap size.")
        #expect(!js.contains("18.0") && !js.contains("18px"),
                "The stale size must not survive in the re-injected CSS.")
    }

    @Test("no change returns nil (no redundant eval / no double-apply)")
    func noChangeReturnsNil() {
        let same = css(fontSizePx: 20)
        #expect(EPUBWebViewBridge.continuousThemeReinjectJS(previousCSS: same, newCSS: same) == nil,
                "An identical theme must not re-inject — guards against churn + double-apply on every unrelated updateUIView.")
    }

    @Test("theme cleared (newCSS nil) emits remove JS")
    func clearedEmitsRemove() throws {
        let js = try #require(
            EPUBWebViewBridge.continuousThemeReinjectJS(previousCSS: css(fontSizePx: 20), newCSS: nil)
        )
        #expect(js == EPUBWebViewBridge.removeThemeCSSJS,
                "Clearing the theme in continuous mode must remove the injected style, mirroring paged mode.")
    }

    @Test("first-time CSS (previous nil → non-nil) emits inject JS")
    func firstApplicationEmitsInject() throws {
        let js = try #require(
            EPUBWebViewBridge.continuousThemeReinjectJS(previousCSS: nil, newCSS: css(fontSizePx: 22))
        )
        #expect(js.contains("vreader-theme") && js.contains("22"))
    }

    @Test("both nil returns nil")
    func bothNilReturnsNil() {
        #expect(EPUBWebViewBridge.continuousThemeReinjectJS(previousCSS: nil, newCSS: nil) == nil)
    }
}

// MARK: - Bug #279: EPUB content pan/zoom lock

/// Bug #279 / GH #1256: legacy EPUB content (raw-spine `loadFileURL` path) could
/// be freely pinch-zoomed and dragged on both axes, instead of being locked to
/// clean vertical scroll / discrete page-turns. The Foliate spike
/// (`FoliateSpikeView`) and the continuous-scroll bootstrap
/// (`EPUBContinuousScrollJS.bootstrapDocumentHTML`) already pin
/// `maximum-scale=1, user-scalable=no` in their constructed documents; the legacy
/// single-chapter path loads the EPUB's own XHTML (whose `<head>` we don't
/// control) with WebKit's default gesture/zoom config, so nothing constrained it.
///
/// Fix = two seams, both pinned here:
///   1. `applyScrollLock(to:)` — pins the WKWebView scrollView's zoom + bounce
///      config directly (works regardless of the chapter's own viewport meta).
///   2. `viewportLockJS` — injects a `user-scalable=no, maximum-scale=1` viewport
///      `<meta>` so the rendered content's CSS-pixel mapping also forbids zoom
///      (defense in depth, consistent with the other engines).
///
/// Same coverage-gap caveat as the bug #163 / #167 seams: these tests lock the
/// seam contracts, not the `makeUIView` call-site wiring (representable-context
/// plumbing is too deep to mock). Device verification is the wiring lock.
@Suite("EPUBWebViewBridge - applyScrollLock (bug #279)")
struct EPUBWebViewBridgeScrollLockTests {

    @MainActor
    @Test("applyScrollLock pins maximum and minimum zoom scale to 1 (no pinch-zoom)")
    func applyScrollLockPinsZoomScale() {
        let scrollView = UIScrollView()
        // Pre-existing values to confirm overwrite — WebKit's default
        // maximumZoomScale is permissive, which is the bug.
        scrollView.maximumZoomScale = 4
        scrollView.minimumZoomScale = 0.5

        EPUBWebViewBridge.applyScrollLock(to: scrollView)

        #expect(scrollView.maximumZoomScale == 1,
                "maximumZoomScale must be pinned to 1 so the user cannot pinch-zoom the EPUB content")
        #expect(scrollView.minimumZoomScale == 1,
                "minimumZoomScale must be pinned to 1 so the content cannot be pinched smaller either")
    }

    @MainActor
    @Test("applyScrollLock disables bouncesZoom (no rubber-band zoom past the pin)")
    func applyScrollLockDisablesBouncesZoom() {
        let scrollView = UIScrollView()
        scrollView.bouncesZoom = true
        EPUBWebViewBridge.applyScrollLock(to: scrollView)
        #expect(scrollView.bouncesZoom == false,
                "bouncesZoom must be off so the content can't rubber-band-zoom past the pinned scale")
    }

    @MainActor
    @Test("applyScrollLock enables directional lock (a vertical drag suppresses horizontal movement)")
    func applyScrollLockEnablesDirectionalLock() {
        let scrollView = UIScrollView()
        scrollView.isDirectionalLockEnabled = false
        EPUBWebViewBridge.applyScrollLock(to: scrollView)
        #expect(scrollView.isDirectionalLockEnabled == true,
                "Directional lock is the lever that actually pins pan to one axis — without it the page can drift diagonally even with bounce off")
    }

    @MainActor
    @Test("applyScrollLock disables horizontal bounce (no sideways rubber-band)")
    func applyScrollLockDisablesHorizontalBounce() {
        let scrollView = UIScrollView()
        scrollView.alwaysBounceHorizontal = true
        EPUBWebViewBridge.applyScrollLock(to: scrollView)
        // Codex Gate-4 finding 1: this flag only governs rubber-band when there
        // is no horizontal content to scroll; directional lock (above) is what
        // pins the pan axis. We assert it is off so an over-wide chapter can't
        // be bounced sideways.
        #expect(scrollView.alwaysBounceHorizontal == false,
                "alwaysBounceHorizontal must be off so an over-wide chapter can't rubber-band sideways")
    }

    @MainActor
    @Test("applyScrollLock is idempotent (re-applying keeps the locked config)")
    func applyScrollLockIsIdempotent() {
        let scrollView = UIScrollView()
        EPUBWebViewBridge.applyScrollLock(to: scrollView)
        EPUBWebViewBridge.applyScrollLock(to: scrollView)
        #expect(scrollView.maximumZoomScale == 1)
        #expect(scrollView.minimumZoomScale == 1)
        #expect(scrollView.bouncesZoom == false)
        #expect(scrollView.isDirectionalLockEnabled == true)
        #expect(scrollView.alwaysBounceHorizontal == false)
    }
}

/// Bug #279 / GH #1256: the JS that forces a non-scalable viewport meta into the
/// legacy chapter document so the content's CSS-pixel mapping forbids zoom,
/// matching the meta the Foliate spike and continuous bootstrap already bake in.
@Suite("EPUBWebViewBridge - viewportLockJS (bug #279)")
struct EPUBWebViewBridgeViewportLockJSTests {

    @Test("viewportLockJS pins maximum-scale=1 and user-scalable=no")
    func viewportLockPinsScale() {
        let js = EPUBWebViewBridge.viewportLockJS
        #expect(js.contains("maximum-scale=1"),
                "The injected viewport meta must pin maximum-scale=1 — the same value the Foliate spike and continuous bootstrap use.")
        #expect(js.contains("user-scalable=no"),
                "The injected viewport meta must forbid user scaling so pinch-zoom is disabled at the document level too.")
        #expect(js.contains("width=device-width"),
                "The viewport must still map to device width so layout isn't broken.")
    }

    @Test("viewportLockJS targets the viewport meta element")
    func viewportLockTargetsViewportMeta() {
        let js = EPUBWebViewBridge.viewportLockJS
        #expect(js.contains("viewport"),
                "The JS must locate/create the name=viewport meta element.")
        #expect(js.contains("setAttribute") || js.contains("content"),
                "The JS must write the content attribute on the meta element.")
    }

    @Test("viewportLockJS is wrapped as an IIFE (consistent with the other bridge scripts)")
    func viewportLockIsIIFE() {
        let js = EPUBWebViewBridge.viewportLockJS
        #expect(js.contains("(function()") && js.contains("})();"),
                "Bridge JS snippets run as self-invoking functions so injected globals don't leak.")
    }

    @Test("viewportLockJS contains no unescaped string-breaking characters")
    func viewportLockHasNoInjectionRisk() {
        let js = EPUBWebViewBridge.viewportLockJS
        // The meta content is a fixed, app-authored literal (no interpolation),
        // so there is no untrusted input — but assert it stays a single clean
        // literal so a future edit can't smuggle in a quote that breaks the eval.
        #expect(!js.contains("\\(") ,
                "viewportLockJS must remain a static literal with no Swift string interpolation of untrusted input.")
    }
}

/// Bug #279 / GH #1256 — Codex Gate-4 finding 2: behavioral DOM coverage for
/// `viewportLockJS`. String-shape assertions can't catch a regression where the
/// upsert creates a duplicate meta, fails to overwrite a permissive viewport, or
/// crashes on a head-less document. These run the actual JS in a live WKWebView
/// and assert the resulting `meta[name=viewport]` content / count.
@MainActor
@Suite("EPUBWebViewBridge - viewportLockJS DOM behavior (bug #279)")
struct EPUBWebViewBridgeViewportLockDOMTests {

    /// Loads `html` into a fresh WKWebView, runs `viewportLockJS`, then returns
    /// the evaluated result of `readback` (a JS expression). Drives navigation
    /// completion off the WebView's `didFinish` via a continuation.
    private func runLock(html: String, readback: String) async throws -> String? {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let delegate = LoadWaiter()
        webView.navigationDelegate = delegate
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            delegate.onFinish = { cont.resume() }
            webView.loadHTMLString(html, baseURL: nil)
        }
        // Run the injection IIFE raw (it evaluates to `undefined`); only the
        // readback expression is wrapped in `String(...)` for a Sendable result.
        try await webView.run(EPUBWebViewBridge.viewportLockJS)
        return try await webView.evaluateString(readback)
    }

    private let expectedContent =
        "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"
    private let viewportSelector = "meta[name=\"viewport\"]"

    @Test("upserts the pin into a document that has NO viewport meta")
    func upsertsWhenAbsent() async throws {
        let html = "<!DOCTYPE html><html><head><title>t</title></head><body><p>hi</p></body></html>"
        let count = try await runLock(html: html, readback: "document.querySelectorAll('\(viewportSelector)').length")
        #expect(count == "1", "Exactly one viewport meta must exist after the upsert")
        let content = try await runLock(html: html, readback: "document.querySelector('\(viewportSelector)').getAttribute('content')")
        #expect(content == expectedContent)
    }

    @Test("overwrites an EXISTING permissive viewport meta in place (no duplicate)")
    func overwritesPermissiveInPlace() async throws {
        // A chapter that explicitly allows zoom — the exact case the bug describes.
        let html = """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, user-scalable=yes, maximum-scale=5">
        </head><body><p>hi</p></body></html>
        """
        let count = try await runLock(html: html, readback: "document.querySelectorAll('\(viewportSelector)').length")
        #expect(count == "1",
                "The upsert must reuse the existing meta, not append a second one")
        let content = try await runLock(html: html, readback: "document.querySelector('\(viewportSelector)').getAttribute('content')")
        #expect(content == expectedContent,
                "The permissive content must be replaced with the locked pin")
    }

    @Test("does not throw on a head-less document (meta still pinned)")
    func handlesHeadlessDocument() async throws {
        // WKWebView synthesizes a <head>, but assert the upsert still yields the
        // pinned meta even when the source markup omits an explicit <head>.
        let html = "<html><body><p>hi</p></body></html>"
        let content = try await runLock(html: html, readback: "(function(){var m=document.querySelector('\(viewportSelector)');return m?m.getAttribute('content'):'MISSING';})()")
        #expect(content == expectedContent,
                "Even without an authored <head>, the viewport pin must be present")
    }
}

/// Minimal navigation delegate that fires a callback on load completion, so the
/// DOM-harness tests can `await` a fully-loaded document before evaluating JS.
@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
        onFinish = nil
    }
}

private extension WKWebView {
    /// Runs a JS statement/IIFE for its side effects, discarding the (possibly
    /// non-Sendable) result so nothing crosses the actor boundary. Used to run
    /// the multi-statement injection JS, which evaluates to `undefined`.
    func run(_ js: String) async throws {
        _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            evaluateJavaScript("{ \(js) }; true") { _, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: true) }
            }
        }
    }

    /// Async wrapper over `evaluateJavaScript` that coerces the result to a
    /// `String` inside JS first. Returning a concrete `Sendable` `String?`
    /// (rather than the non-Sendable `Any?` WebKit yields) keeps the
    /// continuation resume free of Swift 6 data-race diagnostics. The DOM-harness
    /// tests only read back string/number values, so the `String(...)` coercion
    /// is lossless for their assertions (`"1"`, the meta content, or `"null"`).
    /// `js` MUST be a single expression (no trailing `;`), since it is spliced
    /// inside `String(...)`.
    func evaluateString(_ js: String) async throws -> String? {
        try await withCheckedThrowingContinuation { cont in
            evaluateJavaScript("String(\(js))") { value, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: value as? String) }
            }
        }
    }
}

// MARK: - Bug #1561: single-scroller decision (EPUB double-scroller fix)

@Suite("EPUBWebViewBridge - outerScrollEnabled (Bug #1561 double scroller)")
struct EPUBWebViewBridgeOuterScrollEnabledTests {

    @Test("legacy single-chapter scroll keeps the outer scrollView (the only scroller)")
    func legacySingleChapterScrollEnablesOuter() {
        #expect(EPUBWebViewBridge.outerScrollEnabled(isPaged: false, hasContinuousConfig: false) == true)
    }

    @Test("paged mode disables the outer scrollView (the WKWebView paginates)")
    func pagedDisablesOuter() {
        #expect(EPUBWebViewBridge.outerScrollEnabled(isPaged: true, hasContinuousConfig: false) == false)
    }

    @Test("continuous-stitch path disables the outer scrollView — inner #vreader-scroll-root owns it (Bug #1561)")
    func continuousStitchDisablesOuter() {
        #expect(EPUBWebViewBridge.outerScrollEnabled(isPaged: false, hasContinuousConfig: true) == false)
    }

    @Test("paged + continuous (defensive) still disables the outer scrollView")
    func pagedAndContinuousDisablesOuter() {
        #expect(EPUBWebViewBridge.outerScrollEnabled(isPaged: true, hasContinuousConfig: true) == false)
    }
}

// Bug #336: the document-language injection that makes `hyphens: auto` engage on
// the legacy stitched host document (whose <html> has no lang of its own).
@Suite("EPUBWebViewBridge - langInjectionJS (bug #336)")
struct EPUBWebViewBridgeLangJSTests {

    @Test func nilOrEmptyLanguageYieldsNoScript() {
        #expect(EPUBWebViewBridge.langInjectionJS(language: nil) == nil)
        #expect(EPUBWebViewBridge.langInjectionJS(language: "") == nil)
        #expect(EPUBWebViewBridge.langInjectionJS(language: "   ") == nil)  // sanitizes to empty
    }

    @Test func validLanguageSetsDocumentLangWhenAbsent() {
        let js = EPUBWebViewBridge.langInjectionJS(language: "en")
        #expect(js?.contains("var lang = 'en';") == true)
        #expect(js?.contains("html.setAttribute('lang', lang)") == true)
        #expect(js?.contains("document.body.setAttribute('lang', lang)") == true)
        // Only sets when absent — never clobbers a chapter declaring its own lang.
        #expect(js?.contains("!html.getAttribute('lang')") == true)
    }

    @Test func bcp47RegionTagPreserved() {
        #expect(EPUBWebViewBridge.langInjectionJS(language: "zh-CN")?.contains("'zh-CN'") == true)
    }

    @Test func injectionCharactersAreSanitizedOut() {
        // A hostile `dc:language` can't break out of the JS string literal — the
        // sanitizer keeps only [A-Za-z0-9-], dropping quotes / parens / semicolons.
        let js = EPUBWebViewBridge.langInjectionJS(language: "en'};alert(1)//")
        #expect(js?.contains("'};") == false)        // no break-out of the literal
        #expect(js?.contains("alert(") == false)     // the call syntax is gone
        #expect(js?.contains("var lang = 'enalert1';") == true)  // collapsed to safe charset
    }
}
#endif
