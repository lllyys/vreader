// Purpose: Pure-logic seam that turns a horizontal touch swipe (the total
// dx / dy of a gesture) into a next / previous / none page-turn outcome.
// Bug #281 / GH #1258: the custom EPUB WKWebView host only had a `click`
// listener (side-tap), so paged mode had no swipe-to-turn — unlike the
// AZW3/Foliate paged reader, whose paginator.js turns on swipe. This seam
// classifies a swipe so the JS touch handler (`pagedSwipeTrackingJS`) can post
// a discrete page-turn that routes through the SAME `.readerNextPage` /
// `.readerPreviousPage` notifications side-tap already produces — adding no new
// visible chrome, only an input affordance reaching parity with the designed
// paged surface.
//
// Key decisions:
// - Pure namespace-only `enum`, mirroring `ReaderTapZoneRouter` /
//   `EPUBChapterNavigationRouter` / `EPUBPagedProgress`.
// - `dx` convention: positive `dx` = a leftward swipe (finger right→left,
//   start.x - end.x > 0) = advance to the NEXT page, matching natural
//   page-turn affordance (push the page leftwards). Negative dx = previous.
// - Horizontal dominance guard: a predominantly vertical gesture
//   (`|dy| >= |dx|`) never turns the page, so it can't hijack a vertical pan.
// - Threshold guard: horizontal travel must strictly EXCEED the threshold so a
//   tap-like micro-movement is not a turn. Non-positive thresholds fall back to
//   a sane positive default. Non-finite deltas are no-turn (defensive).
//
// @coordinates-with: EPUBPaginationHelper.pagedSwipeTrackingJS,
//   EPUBWebViewBridgeCoordinator (routes the parsed payload through
//   ReaderTapZoneRouter's notifications), EPUBReaderContainerView.swift
//   (.readerNextPage / .readerPreviousPage observers).

import Foundation

/// Pure helper that classifies a horizontal swipe into a page-turn outcome.
enum EPUBSwipeGestureClassifier {

    /// The outcome of a swipe classification.
    enum SwipeOutcome: Equatable {
        /// Advance one page (leftward swipe in LTR).
        case nextPage
        /// Go back one page (rightward swipe in LTR).
        case previousPage
        /// Not a page-turn (too small, or vertically dominant).
        case none
    }

    /// Default minimum horizontal travel (in CSS px / points) for a swipe to
    /// register as a page turn. Used when the caller passes a non-positive
    /// threshold. Comfortably above tap jitter, below a deliberate flick.
    static let defaultThreshold: Double = 50

    /// Classifies a swipe given its total `deltaX` / `deltaY` and a minimum
    /// horizontal travel threshold.
    ///
    /// - Parameters:
    ///   - deltaX: total horizontal travel, `start.x - end.x` (positive = swipe
    ///     left = next page).
    ///   - deltaY: total vertical travel, `start.y - end.y`.
    ///   - threshold: minimum `|deltaX|` to count as a turn; non-positive values
    ///     fall back to `defaultThreshold`.
    /// - Returns: `.nextPage`, `.previousPage`, or `.none`.
    static func classify(deltaX: Double, deltaY: Double, threshold: Double) -> SwipeOutcome {
        guard deltaX.isFinite, deltaY.isFinite else { return .none }
        let effectiveThreshold = threshold > 0 ? threshold : defaultThreshold
        let absX = abs(deltaX)
        let absY = abs(deltaY)
        // Must exceed the threshold AND be horizontally dominant.
        guard absX > effectiveThreshold, absX > absY else { return .none }
        return deltaX > 0 ? .nextPage : .previousPage
    }
}
