// Purpose: Tests for EPUBSwipeGestureClassifier — the pure seam that turns a
// horizontal touch swipe (dx, dy over the gesture) into a next/previous/none
// page-turn outcome, so paged-mode EPUB reaches swipe-to-turn parity with the
// AZW3/Foliate paged reader (which turns on swipe).
//
// Bug #281 / GH #1258 — pre-fix, side-tap was the only page-turn input in the
// custom EPUB WKWebView host; there was no horizontal swipe.
//
// @coordinates-with: EPUBSwipeGestureClassifier.swift, EPUBPaginationHelper.swift

import Testing
import Foundation
@testable import vreader

@Suite("EPUBSwipeGestureClassifier - classify")
struct EPUBSwipeGestureClassifierTests {

    private let threshold: Double = 50

    @Test("swipe left (content moves left, finger right→left) turns to next page")
    func swipeLeft_isNextPage() {
        // Finger travels right→left: end.x < start.x, so dx = start - end > 0.
        // Convention: positive dx (leftward swipe) advances forward.
        let outcome = EPUBSwipeGestureClassifier.classify(
            deltaX: 120, deltaY: 10, threshold: threshold
        )
        #expect(outcome == .nextPage)
    }

    @Test("swipe right (finger left→right) turns to previous page")
    func swipeRight_isPreviousPage() {
        let outcome = EPUBSwipeGestureClassifier.classify(
            deltaX: -120, deltaY: 10, threshold: threshold
        )
        #expect(outcome == .previousPage)
    }

    @Test("horizontal movement below threshold is no turn (tap-like)")
    func belowThreshold_isNone() {
        let outcome = EPUBSwipeGestureClassifier.classify(
            deltaX: 20, deltaY: 5, threshold: threshold
        )
        #expect(outcome == .none)
    }

    @Test("at exactly the threshold is no turn (must exceed)")
    func atThreshold_isNone() {
        let outcome = EPUBSwipeGestureClassifier.classify(
            deltaX: 50, deltaY: 0, threshold: threshold
        )
        #expect(outcome == .none)
    }

    @Test("just over the threshold turns the page")
    func justOverThreshold_turns() {
        let outcome = EPUBSwipeGestureClassifier.classify(
            deltaX: 51, deltaY: 0, threshold: threshold
        )
        #expect(outcome == .nextPage)
    }

    @Test("predominantly vertical swipe is no turn (don't hijack vertical pans)")
    func verticalDominant_isNone() {
        // |dy| > |dx|: a vertical drag should never turn the page.
        let outcome = EPUBSwipeGestureClassifier.classify(
            deltaX: 60, deltaY: 200, threshold: threshold
        )
        #expect(outcome == .none)
    }

    @Test("diagonal but horizontally dominant past threshold turns the page")
    func diagonalHorizontalDominant_turns() {
        let outcome = EPUBSwipeGestureClassifier.classify(
            deltaX: 120, deltaY: 80, threshold: threshold
        )
        #expect(outcome == .nextPage)
    }

    @Test("zero movement is no turn")
    func zeroMovement_isNone() {
        let outcome = EPUBSwipeGestureClassifier.classify(
            deltaX: 0, deltaY: 0, threshold: threshold
        )
        #expect(outcome == .none)
    }

    @Test("NaN / non-finite deltas are no turn (defensive)")
    func nonFinite_isNone() {
        #expect(EPUBSwipeGestureClassifier.classify(
            deltaX: .nan, deltaY: 0, threshold: threshold) == .none)
        #expect(EPUBSwipeGestureClassifier.classify(
            deltaX: .infinity, deltaY: 0, threshold: threshold) == .none)
        #expect(EPUBSwipeGestureClassifier.classify(
            deltaX: 100, deltaY: .nan, threshold: threshold) == .none)
    }

    @Test("non-positive threshold falls back to a positive default")
    func nonPositiveThreshold_usesDefault() {
        // A zero/negative threshold must not make every micro-jitter a turn.
        // The classifier clamps to a sane positive default.
        let outcome = EPUBSwipeGestureClassifier.classify(
            deltaX: 5, deltaY: 0, threshold: 0
        )
        #expect(outcome == .none)
    }
}

// MARK: - Paged swipe-tracking JS

@Suite("EPUBPaginationHelper - pagedSwipeTrackingJS")
struct EPUBPagedSwipeTrackingJSTests {

    @Test("JS registers touchstart and touchend listeners")
    func swipeJS_registersTouchListeners() {
        let js = EPUBPaginationHelper.pagedSwipeTrackingJS
        #expect(js.contains("touchstart"))
        #expect(js.contains("touchend"))
    }

    @Test("JS posts to the pagedSwipeHandler message channel")
    func swipeJS_postsToHandler() {
        let js = EPUBPaginationHelper.pagedSwipeTrackingJS
        #expect(js.contains("pagedSwipeHandler"))
        #expect(js.contains("postMessage"))
    }

    @Test("JS carries dx and dy in its payload")
    func swipeJS_carriesDeltas() {
        let js = EPUBPaginationHelper.pagedSwipeTrackingJS
        #expect(js.contains("dx"))
        #expect(js.contains("dy"))
    }

    // Codex Gate-4 round-1 [M1]: the JS consume threshold must equal the Swift
    // classifier's default, or an 11-49px jitter would swallow the synthetic
    // click without turning, making a genuine side-tap feel dropped.
    @Test("JS swipe-consume threshold matches the classifier default")
    func swipeJS_consumeThresholdMatchesClassifier() {
        let js = EPUBPaginationHelper.pagedSwipeTrackingJS
        let expected = "SWIPE_PX = \(Int(EPUBSwipeGestureClassifier.defaultThreshold))"
        #expect(js.contains(expected),
                "JS consume threshold must equal EPUBSwipeGestureClassifier.defaultThreshold")
    }

    // Codex Gate-4 round-1 [Low]: touchcancel must reset gesture state so a
    // cancelled swipe can't strand the consume flag.
    @Test("JS handles touchcancel cleanup")
    func swipeJS_handlesTouchCancel() {
        let js = EPUBPaginationHelper.pagedSwipeTrackingJS
        #expect(js.contains("touchcancel"))
    }

    // The consume flag must auto-expire (round-1 [Low]) so a swipe with no
    // following synthetic click can't swallow the next genuine tap.
    @Test("JS auto-expires the swipe-consume flag")
    func swipeJS_autoExpiresConsumeFlag() {
        let js = EPUBPaginationHelper.pagedSwipeTrackingJS
        #expect(js.contains("setTimeout"))
        #expect(js.contains("__vreaderSwipeConsumedTap = false"))
    }
}
