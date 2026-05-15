// Purpose: Regression tests for Bug #180 (GH #614) — TXT scroll mode now
// detects chapter boundaries and fires delegate callbacks so the ViewModel
// can advance/retreat one chapter without requiring chrome-button taps.
//
// Tests live in vreaderTests/Views/Reader/ to mirror the source path.

#if canImport(UIKit)
import Testing
import UIKit
@testable import vreader

@Suite("TXT scroll boundary → chapter navigation (Bug #180)")
@MainActor
struct TXTScrollBoundaryChapterNavTests {

    @Test func decelerateAtBottomFiresBottomBoundaryCallback() {
        let spy = SpyDelegate()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: spy)
        let scrollView = BoundaryStubScrollView(
            contentSize: CGSize(width: 393, height: 2000),
            boundsHeight: 852,
            contentOffsetY: 2000 - 852  // exactly at bottom
        )

        coordinator.scrollViewDidEndDecelerating(scrollView)

        #expect(spy.bottomBoundaryFireCount == 1, "Expected one bottom-boundary fire when settled at bottom")
        #expect(spy.topBoundaryFireCount == 0, "Top-boundary must not fire at bottom")
    }

    @Test func decelerateAtTopFiresTopBoundaryCallback() {
        let spy = SpyDelegate()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: spy)
        let scrollView = BoundaryStubScrollView(
            contentSize: CGSize(width: 393, height: 2000),
            boundsHeight: 852,
            contentOffsetY: 0
        )

        coordinator.scrollViewDidEndDecelerating(scrollView)

        #expect(spy.topBoundaryFireCount == 1, "Expected one top-boundary fire when settled at top")
        #expect(spy.bottomBoundaryFireCount == 0, "Bottom-boundary must not fire at top")
    }

    @Test func decelerateMidContentFiresNeitherBoundary() {
        let spy = SpyDelegate()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: spy)
        let scrollView = BoundaryStubScrollView(
            contentSize: CGSize(width: 393, height: 2000),
            boundsHeight: 852,
            contentOffsetY: 500  // well within the middle
        )

        coordinator.scrollViewDidEndDecelerating(scrollView)

        #expect(spy.bottomBoundaryFireCount == 0)
        #expect(spy.topBoundaryFireCount == 0)
    }

    /// When the loaded chapter is smaller than the viewport, contentOffset = 0
    /// AND offset+bounds >= contentSize. Without this guard the boundary
    /// detection would fire BOTH callbacks every settle, causing rapid
    /// repeated chapter navigation.
    @Test func decelerateWithContentSmallerThanViewportFiresNeitherBoundary() {
        let spy = SpyDelegate()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: spy)
        let scrollView = BoundaryStubScrollView(
            contentSize: CGSize(width: 393, height: 400),
            boundsHeight: 852,
            contentOffsetY: 0
        )

        coordinator.scrollViewDidEndDecelerating(scrollView)

        #expect(spy.bottomBoundaryFireCount == 0,
                "Content shorter than viewport must NOT fire bottom-boundary (would cause runaway chapter advance)")
        #expect(spy.topBoundaryFireCount == 0,
                "Content shorter than viewport must NOT fire top-boundary either")
    }

    /// `suppressScrollCallbacks` is the coordinator's general signal for
    /// "this scroll callback is programmatic, not user-driven". Boundary
    /// detection must honor the same guard. Bug-row scenario: chapter-
    /// restore + chrome-button-driven chapter nav both set this flag during
    /// the programmatic scroll-to-target so neither path auto-fires another
    /// chapter advance once the scroll settles. Validates the coordinator
    /// guard itself — the per-bridge wiring is exercised by the integration
    /// path, not this unit test.
    @Test func decelerateAtTopWithSuppressedCallbacksFiresNeitherBoundary() {
        let spy = SpyDelegate()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: spy)
        coordinator.suppressScrollCallbacks = true
        let scrollView = BoundaryStubScrollView(
            contentSize: CGSize(width: 393, height: 2000),
            boundsHeight: 852,
            contentOffsetY: 0
        )

        coordinator.scrollViewDidEndDecelerating(scrollView)

        #expect(spy.bottomBoundaryFireCount == 0)
        #expect(spy.topBoundaryFireCount == 0,
                "Programmatic scroll (suppressed callbacks) must not trigger chapter nav")
    }

    /// Codex Gate 4 round-1 Medium #1: when `contentSize.height - bounds.height`
    /// is tiny (sub-slack from layout rounding), the previous implementation
    /// satisfied BOTH the bottom and top predicates at offset=0, and bottom
    /// (checked first) won — advancing instead of no-op-ing. The
    /// `maxOffset > 2 * boundarySlack` guard makes the zones non-overlapping.
    @Test func decelerateOnNearFitChapterAtOffsetZeroFiresNeitherBoundary() {
        let spy = SpyDelegate()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: spy)
        // contentSize.height = bounds.height + 0.4 → maxOffset = 0.4 < 2*slack(=1.0)
        let scrollView = BoundaryStubScrollView(
            contentSize: CGSize(width: 393, height: 852.4),
            boundsHeight: 852,
            contentOffsetY: 0
        )

        coordinator.scrollViewDidEndDecelerating(scrollView)

        #expect(spy.bottomBoundaryFireCount == 0,
                "Near-fit chapter (maxOffset < 2*slack) at offset 0 must not fire bottom")
        #expect(spy.topBoundaryFireCount == 0,
                "Near-fit chapter at offset 0 must not fire top either")
    }

    /// `scrollViewDidEndDragging(decelerate: false)` is the path for slow
    /// drags that don't trigger kinetic deceleration. Boundary detection
    /// must apply on this code path too.
    @Test func endDraggingWithoutDecelerateAtBottomFiresBottomBoundary() {
        let spy = SpyDelegate()
        let coordinator = TXTTextViewBridge.Coordinator(delegate: spy)
        let scrollView = BoundaryStubScrollView(
            contentSize: CGSize(width: 393, height: 2000),
            boundsHeight: 852,
            contentOffsetY: 2000 - 852
        )

        coordinator.scrollViewDidEndDragging(scrollView, willDecelerate: false)

        #expect(spy.bottomBoundaryFireCount == 1)
    }
}

// MARK: - Test doubles

@MainActor
private final class SpyDelegate: TXTTextViewBridgeDelegate {
    var topBoundaryFireCount = 0
    var bottomBoundaryFireCount = 0
    var lastScrollOffset: Int?
    var lastSelectionRange: UTF16Range?

    func selectionDidChange(utf16Range: UTF16Range) { lastSelectionRange = utf16Range }
    func scrollPositionDidChange(topCharOffsetUTF16: Int) { lastScrollOffset = topCharOffsetUTF16 }
    func didScrollPastTopBoundary() { topBoundaryFireCount += 1 }
    func didScrollPastBottomBoundary() { bottomBoundaryFireCount += 1 }
}

/// Stubbed UIScrollView whose contentOffset, contentSize, and bounds can be
/// set independently — UIScrollView doesn't let tests fake bounds from
/// outside, so we set the frame and let bounds derive from it.
private final class BoundaryStubScrollView: UIScrollView {
    init(contentSize: CGSize, boundsHeight: CGFloat, contentOffsetY: CGFloat) {
        super.init(frame: CGRect(x: 0, y: 0, width: contentSize.width, height: boundsHeight))
        self.contentSize = contentSize
        self.contentOffset = CGPoint(x: 0, y: contentOffsetY)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
}

#endif
