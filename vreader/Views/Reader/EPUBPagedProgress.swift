// Purpose: Pure-logic seam mapping a within-chapter paged position
// (currentPage / totalPages) to an intra-chapter progress fraction
// (0.0...1.0). Bug #281 / GH #1258: paged-mode page turns only changed the
// horizontal `scrollLeft`, and the only `onProgressChange` producer is bound
// to the vertical scroll event (disabled in paged mode), so the progress bar /
// "Chapter X of Y" label / persisted EPUBPosition all froze while paging
// within a chapter. The container composes this fraction with
// `EPUBProgressCalculator.progress(spineIndex:scrollFraction:totalSpineItems:)`
// — exactly the path the vertical-scroll fraction already flows through — so a
// within-chapter paged turn updates progress the same way scroll does, mirroring
// the AZW3/Foliate paged reader (which reports a relocate fraction on every turn).
//
// Key decisions:
// - Pure namespace-only `enum`, every call a `static func` with no shared state
//   — mirrors `EPUBPaginationHelper`, `EPUBProgressCalculator`,
//   `EPUBChapterNavigationRouter`, `ReaderTapZoneRouter`.
// - Fraction formula matches `BasePageNavigator.progression` exactly
//   (`currentPage / (totalPages - 1)`) so the live page navigator and the
//   persisted fraction never disagree. Single-page / not-yet-paginated chapters
//   report chapter-start (0.0), never a divide-by-zero.
// - All inputs clamped to safe ranges (negative page, overflow page, zero /
//   negative totalPages).
//
// @coordinates-with: EPUBProgressCalculator.swift, BasePageNavigator.swift,
//   EPUBReaderContainerView+ChapterWrap.swift (consumes the fraction after a
//   within-chapter paged turn), EPUBPaginationHelper.swift

import Foundation

/// Pure helper mapping a paged position to an intra-chapter progress fraction.
enum EPUBPagedProgress {

    /// Computes the intra-chapter progress fraction (0.0...1.0) for a paged
    /// position. The first page is 0.0, the last page is 1.0, and intermediate
    /// pages map proportionally — matching `BasePageNavigator.progression`.
    ///
    /// - Parameters:
    ///   - currentPage: zero-based current page index (clamped to
    ///     `0...(totalPages - 1)`).
    ///   - totalPages: total pages in the current chapter. `<= 1` (single-page,
    ///     empty, or not-yet-paginated) reports `0.0` — there is no within-
    ///     chapter movement to express, and dividing by `totalPages - 1` would
    ///     be undefined.
    /// - Returns: The intra-chapter fraction, clamped to `0.0...1.0`.
    static func intraChapterFraction(currentPage: Int, totalPages: Int) -> Double {
        guard totalPages > 1 else { return 0.0 }
        let maxPage = totalPages - 1
        let clampedPage = max(0, min(currentPage, maxPage))
        let fraction = Double(clampedPage) / Double(maxPage)
        return min(max(fraction, 0.0), 1.0)
    }
}
