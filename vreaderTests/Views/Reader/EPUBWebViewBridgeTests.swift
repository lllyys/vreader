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
#endif
