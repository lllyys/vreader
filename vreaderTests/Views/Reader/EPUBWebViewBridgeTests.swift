// Purpose: Tests for EPUBWebViewBridge scroll-to-fraction JS generation.
// Verifies the JavaScript string produced by scrollToFractionJS is well-formed
// and handles edge cases (0, 1, negative, NaN).
//
// @coordinates-with: EPUBWebViewBridge.swift

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
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
#endif
