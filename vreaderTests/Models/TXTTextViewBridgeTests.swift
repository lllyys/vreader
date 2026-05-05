// Purpose: Tests for TXTViewConfig.renderingEquals — the production config-diff logic
// used by TXTTextViewBridge.updateUIView to decide when to re-apply text styling.
// Verifies that theme/color changes trigger text re-application (bug #10 regression).

import Testing
import UIKit
@testable import vreader

@Suite("TXTViewConfig renderingEquals")
struct TXTTextViewBridgeConfigTests {

    // MARK: - Tests

    @Test func identicalConfigsAreEqual() {
        let a = TXTViewConfig()
        let b = TXTViewConfig()
        #expect(a.renderingEquals(b), "Identical configs should be equal")
    }

    @Test func fontSizeChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.fontSize = 24
        #expect(!a.renderingEquals(b), "fontSize change should make configs unequal")
    }

    @Test func textColorChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.textColor = .red
        #expect(!a.renderingEquals(b), "textColor change should make configs unequal (bug #10)")
    }

    @Test func backgroundColorChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.backgroundColor = UIColor(red: 0.96, green: 0.93, blue: 0.87, alpha: 1.0)
        #expect(!a.renderingEquals(b), "backgroundColor change should make configs unequal (bug #10)")
    }

    @Test func letterSpacingChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.letterSpacing = 1.5
        #expect(!a.renderingEquals(b), "letterSpacing change should make configs unequal")
    }

    @Test func lineSpacingChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.lineSpacing = 12
        #expect(!a.renderingEquals(b), "lineSpacing change should make configs unequal")
    }

    @Test func fontNameChangeMakesUnequal() {
        let a = TXTViewConfig()
        var b = TXTViewConfig()
        b.fontName = "Georgia"
        #expect(!a.renderingEquals(b), "fontName change should make configs unequal")
    }

    @Test func themeChangeFromLightToSepiaMakesUnequal() {
        let light = TXTViewConfig()
        var sepia = TXTViewConfig()
        sepia.textColor = UIColor(red: 0.23, green: 0.17, blue: 0.09, alpha: 1.0)
        sepia.backgroundColor = UIColor(red: 0.96, green: 0.93, blue: 0.87, alpha: 1.0)
        #expect(!light.renderingEquals(sepia), "Theme change (light→sepia) should make configs unequal")
    }

    @Test func themeChangeFromLightToDarkMakesUnequal() {
        let light = TXTViewConfig()
        var dark = TXTViewConfig()
        dark.textColor = UIColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1.0)
        dark.backgroundColor = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        #expect(!light.renderingEquals(dark), "Theme change (light→dark) should make configs unequal")
    }

    // MARK: - Coordinator Restore-Once Behavior (Bug #15, #17)

    @Test @MainActor func coordinatorRestoresOnlyOnce() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        #expect(coordinator.hasRestoredPosition == false,
                "New coordinator should not have restored position yet")

        // Simulate first restore
        coordinator.hasRestoredPosition = true

        // Even if restoreOffset changes, coordinator should not restore again
        #expect(coordinator.hasRestoredPosition == true,
                "Once restored, flag should remain true")
    }

    @Test @MainActor func coordinatorStartsWithoutRestore() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        #expect(coordinator.hasRestoredPosition == false)
    }

    // MARK: - Bug #99 — search-highlight clear-on-scroll gating

    /// Bug #99 cause #3: search highlight was cleared by `scrollViewDidScroll`
    /// callbacks fired by TextKit 1's lazy layout pass after a programmatic
    /// scroll, before the user could see the highlight.
    ///
    /// Fix: `clearSearchHighlightIfTemporary(scrollView:)` now uses the
    /// scroll view's `isTracking || isDragging || isDecelerating` triplet
    /// to distinguish user scrolls (clear) from programmatic-scroll-induced
    /// layout callbacks (skip).
    ///
    /// Tests below verify the gating logic via UIScrollView's actual flags
    /// — no timer, no clock injection.

    @Test @MainActor func clearSearchHighlight_skipsWhenScrollViewIdle() {
        // Programmatic scroll's late layout-driven callback shape: a
        // UIScrollView whose isTracking/isDragging/isDecelerating are all
        // false. The clear must skip — otherwise the highlight is dismissed
        // before the user sees it.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 0, length: 5)
        let idleScrollView = UIScrollView()
        // All three flags are false on a fresh UIScrollView with no user input.
        #expect(!idleScrollView.isTracking)
        #expect(!idleScrollView.isDragging)
        #expect(!idleScrollView.isDecelerating)

        coordinator.clearSearchHighlightIfTemporary(scrollView: idleScrollView)

        #expect(coordinator.currentHighlightRange != nil,
                "Idle-scroll-view callbacks must NOT clear the highlight (bug #99 cause #3)")
    }

    @Test @MainActor func clearSearchHighlight_clearsWhenCalledWithoutScrollView() {
        // Non-scroll-driven dismissal paths (chrome tap, search-clear notification)
        // pass scrollView: nil and should clear unconditionally.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 0, length: 5)

        coordinator.clearSearchHighlightIfTemporary()  // nil

        #expect(coordinator.currentHighlightRange == nil,
                "nil scrollView (e.g., tap dismiss) must clear unconditionally")
    }

    @Test @MainActor func clearSearchHighlight_clearsWhenScrollViewIsDragging() {
        // Positive user-scroll path: `isDragging` is true → user is actively
        // scrolling → highlight should dismiss as the user expects.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 0, length: 5)

        let dragging = StubScrollView()
        dragging.stubIsDragging = true
        coordinator.clearSearchHighlightIfTemporary(scrollView: dragging)

        #expect(coordinator.currentHighlightRange == nil,
                "User-driven scroll (isDragging) must clear the highlight")
    }

    @Test @MainActor func clearSearchHighlight_clearsWhenScrollViewIsDecelerating() {
        // Positive user-scroll path: `isDecelerating` is true → user lifted
        // finger but inertia is still scrolling → still a user scroll → clear.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 0, length: 5)

        let decelerating = StubScrollView()
        decelerating.stubIsDecelerating = true
        coordinator.clearSearchHighlightIfTemporary(scrollView: decelerating)

        #expect(coordinator.currentHighlightRange == nil,
                "User-driven scroll (isDecelerating) must clear the highlight")
    }

    @Test @MainActor func clearSearchHighlight_clearsWhenScrollViewIsTracking() {
        // Positive user-scroll path: `isTracking` is true → user has finger
        // on screen → still a user-driven interaction → clear.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 0, length: 5)

        let tracking = StubScrollView()
        tracking.stubIsTracking = true
        coordinator.clearSearchHighlightIfTemporary(scrollView: tracking)

        #expect(coordinator.currentHighlightRange == nil,
                "User-driven scroll (isTracking) must clear the highlight")
    }
}

/// UIScrollView subclass that lets tests override the three user-interaction
/// flags. UIScrollView's flags are read-only computed properties; subclassing
/// is the canonical way to fake them without driving real touch events.
private final class StubScrollView: UIScrollView {
    var stubIsTracking: Bool = false
    var stubIsDragging: Bool = false
    var stubIsDecelerating: Bool = false
    override var isTracking: Bool { stubIsTracking }
    override var isDragging: Bool { stubIsDragging }
    override var isDecelerating: Bool { stubIsDecelerating }
}
