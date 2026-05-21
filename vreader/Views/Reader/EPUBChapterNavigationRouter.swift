// Purpose: Decides whether a side-tap-driven next/previous page command
// should turn the page within the current chapter, wrap to the next /
// previous chapter, or bounce at the start / end of the book.
//
// Background: Bug #165 / GH #489 — pre-fix, side-tap at the boundary
// (last page of a chapter, or first page of a chapter) was a no-op
// because `BasePageNavigator.nextPage()` / `.previousPage()` silently
// clamp at totalPages-1 / 0. Per design §2.2 (paged-mode chapter wrap)
// the user-expected behavior at a chapter boundary is to advance to the
// next chapter's first page (right-tap) or the previous chapter's last
// page (left-tap), matching Apple Books and Kindle. The decision logic
// lives in this pure helper so it can be unit-tested without spinning
// up a `WKWebView` or the full container view.
//
// Design source: dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md §2.2
//
// Key decisions:
// - Pure, namespace-only `enum` — every call is a `static func` with no
//   shared state, mirroring `ReaderTapZoneRouter` and `EPUBPaginationHelper`.
// - The `Decision` enum is exhaustive over the four possible outcomes;
//   the container switches on the value and performs exactly one of:
//   call `pageNavigator.{next,previous}Page()`, call
//   `viewModel.{next,previous}Chapter()`, or do nothing (bounce).
// - Defensive against unknown / not-yet-paginated state: when
//   `totalPages == 0` (pagination not ready) the decision falls back to
//   `.withinChapter`, letting `BasePageNavigator` no-op rather than
//   blindly wrapping. That preserves the pre-fix no-op shape until
//   pagination is genuinely settled.
// - Edge of book: a bounce returns `.bounceAt{Start,End}OfBook` so the
//   container can opt into a visual / haptic affordance later without
//   the router needing to know about UIKit. Today the container treats
//   bounce as a no-op (matches the existing clamp behavior); the design
//   §2.2 "subtle horizontal nudge animation" is left for a follow-up
//   issue when its visual spec is finalized.
//
// @coordinates-with: EPUBReaderContainerView.swift (consumes the decision
//                    in `.readerNextPage` / `.readerPreviousPage`
//                    handlers), BasePageNavigator.swift,
//                    EPUBReaderViewModel.swift (navigateNext / Previous).

import Foundation

/// Pure helper that turns the current paged-mode position (page index +
/// spine index) into a `Decision` describing what a side-tap-driven
/// next / previous command should do.
enum EPUBChapterNavigationRouter {

    /// Exhaustive outcome of a side-tap navigation request.
    enum Decision: Equatable {
        /// Resolve within the current chapter via the page navigator.
        /// `BasePageNavigator.nextPage()` / `.previousPage()` already
        /// clamps at the boundary, so this is the legacy path.
        case withinChapter
        /// Boundary crossing: the next chapter exists; the container
        /// should call `viewModel.navigateNext()` and land on page 0
        /// of the new chapter (default `navigateToSpine` behavior).
        case wrapToNextChapter
        /// Boundary crossing: the previous chapter exists; the
        /// container should call `viewModel.navigatePrevious()` AND
        /// arm `EPUBChapterWrapPendingTarget` so the new chapter's
        /// `onPaginationReady` lands on the last page (matching
        /// design §2.2's "left-tap from first page → last page of N-1").
        case wrapToPreviousChapter
        /// At the last page of the last chapter — no next chapter
        /// exists. Container is free to add a bounce affordance.
        case bounceAtEndOfBook
        /// At the first page of the first chapter — no previous
        /// chapter exists. Container is free to add a bounce affordance.
        case bounceAtStartOfBook
    }

    /// Decides what a right-tap (or any next-page command) should do.
    ///
    /// - Parameters:
    ///   - currentPage: zero-based current page index in the current
    ///     chapter, as reported by `BasePageNavigator.currentPage`.
    ///   - totalPages: total pages in the current chapter as reported
    ///     by `BasePageNavigator.totalPages`. When `<= 0`, pagination
    ///     is treated as not-yet-ready and the decision collapses to
    ///     `.withinChapter` (the legacy no-op via clamp).
    ///   - currentSpineIndex: zero-based spine index of the current
    ///     chapter (`EPUBReaderViewModel.currentSpineIndex`).
    ///   - spineCount: total spine items
    ///     (`EPUBReaderViewModel.metadata?.spineCount` ?? 0).
    static func decideNext(
        currentPage: Int,
        totalPages: Int,
        currentSpineIndex: Int,
        spineCount: Int
    ) -> Decision {
        // Empty / unknown book: nothing to navigate.
        guard spineCount > 0 else { return .bounceAtEndOfBook }
        // Pagination not yet ready — defer to the page navigator's
        // clamp behavior to avoid wrapping a chapter the user has not
        // actually rendered yet.
        guard totalPages > 0 else { return .withinChapter }
        // Round-1 audit finding [2] (Medium): stale spine index outside
        // `0..<spineCount` must collapse to a safe bounce, not silently
        // wrap. `currentSpineIndex < 0` previously satisfied
        // `hasNextChapter` and would wrap forward into chapter 0 from
        // an unknown position. Treat any out-of-range index as
        // already-at-end so the user sees a bounce instead.
        guard currentSpineIndex >= 0, currentSpineIndex < spineCount else {
            return .bounceAtEndOfBook
        }

        // Are we at the last page of the current chapter? `currentPage`
        // is zero-based; `totalPages == 1` means single-page chapter
        // where page 0 IS the last page.
        let atLastPage = currentPage >= totalPages - 1
        guard atLastPage else { return .withinChapter }

        // At the last page. Is there a next chapter?
        let hasNextChapter = currentSpineIndex < spineCount - 1
        return hasNextChapter ? .wrapToNextChapter : .bounceAtEndOfBook
    }

    /// Decides what a left-tap (or any previous-page command) should do.
    /// See `decideNext(currentPage:totalPages:currentSpineIndex:spineCount:)`
    /// for parameter semantics.
    static func decidePrevious(
        currentPage: Int,
        totalPages: Int,
        currentSpineIndex: Int,
        spineCount: Int
    ) -> Decision {
        guard spineCount > 0 else { return .bounceAtStartOfBook }
        guard totalPages > 0 else { return .withinChapter }
        // Round-1 audit finding [2] (Medium): stale spine index outside
        // `0..<spineCount` must collapse to a safe bounce, not silently
        // wrap. `currentSpineIndex >= spineCount` previously satisfied
        // `hasPreviousChapter` and would wrap backward to a chapter the
        // user wasn't reading.
        guard currentSpineIndex >= 0, currentSpineIndex < spineCount else {
            return .bounceAtStartOfBook
        }

        let atFirstPage = currentPage <= 0
        guard atFirstPage else { return .withinChapter }

        let hasPreviousChapter = currentSpineIndex > 0
        return hasPreviousChapter ? .wrapToPreviousChapter : .bounceAtStartOfBook
    }
}
