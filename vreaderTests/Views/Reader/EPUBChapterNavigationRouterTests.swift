// Purpose: Tests for EPUBChapterNavigationRouter — the helper that decides
// what side-tap-driven navigation should do given the current page state
// and spine position. Implements design §2.2 (paged mode chapter wrap):
//
// | Position                     | Right tap                    | Left tap                     |
// |------------------------------|------------------------------|------------------------------|
// | Last page of chapter N (N<L) | wrap to chapter N+1, page 0  | in-chapter previousPage      |
// | First page of chapter N (N>0)| in-chapter nextPage          | wrap to chapter N-1, last pg |
// | Last page of LAST chapter    | bounce                       | in-chapter previousPage      |
// | First page of FIRST chapter  | in-chapter nextPage          | bounce                       |
// | Middle of any chapter        | in-chapter nextPage          | in-chapter previousPage      |
//
// Bug #165 / GH #489: pre-fix, side-tap at last/first page of a chapter
// was a no-op because `BasePageNavigator.nextPage()` / `.previousPage()`
// silently clamp at the boundary. Now the router fires a wrap decision
// when at the boundary so the container's `.readerNextPage` /
// `.readerPreviousPage` handler can call `viewModel.navigateNext()` /
// `.navigatePrevious()` instead.
//
// @coordinates-with: EPUBChapterNavigationRouter.swift,
//                    EPUBReaderContainerView.swift,
//                    EPUBReaderViewModel.swift, BasePageNavigator.swift

import XCTest
@testable import vreader

final class EPUBChapterNavigationRouterTests: XCTestCase {

    // MARK: - Middle of a chapter — never wraps

    func test_nextFromMiddleOfChapter_resolvesToWithinChapter() {
        let decision = EPUBChapterNavigationRouter.decideNext(
            currentPage: 3, totalPages: 10,
            currentSpineIndex: 1, spineCount: 5
        )
        XCTAssertEqual(decision, .withinChapter)
    }

    func test_previousFromMiddleOfChapter_resolvesToWithinChapter() {
        let decision = EPUBChapterNavigationRouter.decidePrevious(
            currentPage: 3, totalPages: 10,
            currentSpineIndex: 1, spineCount: 5
        )
        XCTAssertEqual(decision, .withinChapter)
    }

    // MARK: - Boundary: last page of a non-final chapter wraps forward

    func test_nextFromLastPageOfNonFinalChapter_wrapsToNextChapter() {
        // currentPage == totalPages - 1, spine 1 of 5 (0..4) -> wrap
        let decision = EPUBChapterNavigationRouter.decideNext(
            currentPage: 9, totalPages: 10,
            currentSpineIndex: 1, spineCount: 5
        )
        XCTAssertEqual(decision, .wrapToNextChapter)
    }

    func test_nextFromLastPageOfFinalChapter_bouncesAtEndOfBook() {
        // last spine, last page -> bounce (no next chapter)
        let decision = EPUBChapterNavigationRouter.decideNext(
            currentPage: 9, totalPages: 10,
            currentSpineIndex: 4, spineCount: 5
        )
        XCTAssertEqual(decision, .bounceAtEndOfBook)
    }

    // MARK: - Boundary: first page of a non-initial chapter wraps backward

    func test_previousFromFirstPageOfNonInitialChapter_wrapsToPreviousChapter() {
        // currentPage 0, spine 1 of 5 -> wrap backward
        let decision = EPUBChapterNavigationRouter.decidePrevious(
            currentPage: 0, totalPages: 10,
            currentSpineIndex: 1, spineCount: 5
        )
        XCTAssertEqual(decision, .wrapToPreviousChapter)
    }

    func test_previousFromFirstPageOfInitialChapter_bouncesAtStartOfBook() {
        // first spine, first page -> bounce (no previous chapter)
        let decision = EPUBChapterNavigationRouter.decidePrevious(
            currentPage: 0, totalPages: 10,
            currentSpineIndex: 0, spineCount: 5
        )
        XCTAssertEqual(decision, .bounceAtStartOfBook)
    }

    // MARK: - Edge: single-page chapter (totalPages == 1)

    func test_nextFromSinglePageChapter_isBothFirstAndLastPage() {
        // 1-page chapter -> at last page from page 0 -> wrap if not final
        let decision = EPUBChapterNavigationRouter.decideNext(
            currentPage: 0, totalPages: 1,
            currentSpineIndex: 1, spineCount: 5
        )
        XCTAssertEqual(decision, .wrapToNextChapter)
    }

    func test_previousFromSinglePageChapter_isBothFirstAndLastPage() {
        let decision = EPUBChapterNavigationRouter.decidePrevious(
            currentPage: 0, totalPages: 1,
            currentSpineIndex: 1, spineCount: 5
        )
        XCTAssertEqual(decision, .wrapToPreviousChapter)
    }

    // MARK: - Edge: zero-page or unknown pagination — never wraps

    func test_nextWithZeroTotalPages_resolvesToWithinChapter() {
        // Pagination not ready yet — let the page navigator handle it
        // (no-op via clamp). Wrapping with no totalPages would skip a
        // chapter the user never saw.
        let decision = EPUBChapterNavigationRouter.decideNext(
            currentPage: 0, totalPages: 0,
            currentSpineIndex: 1, spineCount: 5
        )
        XCTAssertEqual(decision, .withinChapter)
    }

    func test_previousWithZeroTotalPages_resolvesToWithinChapter() {
        let decision = EPUBChapterNavigationRouter.decidePrevious(
            currentPage: 0, totalPages: 0,
            currentSpineIndex: 1, spineCount: 5
        )
        XCTAssertEqual(decision, .withinChapter)
    }

    // MARK: - Edge: empty book (spineCount == 0)

    func test_nextWithEmptyBook_resolvesToBounceAtEndOfBook() {
        let decision = EPUBChapterNavigationRouter.decideNext(
            currentPage: 0, totalPages: 1,
            currentSpineIndex: 0, spineCount: 0
        )
        XCTAssertEqual(decision, .bounceAtEndOfBook)
    }

    func test_previousWithEmptyBook_resolvesToBounceAtStartOfBook() {
        let decision = EPUBChapterNavigationRouter.decidePrevious(
            currentPage: 0, totalPages: 1,
            currentSpineIndex: 0, spineCount: 0
        )
        XCTAssertEqual(decision, .bounceAtStartOfBook)
    }

    // MARK: - Edge: single-chapter book

    func test_nextAtLastPageOfOnlyChapter_bouncesAtEndOfBook() {
        // spineCount == 1, at last page -> bounce
        let decision = EPUBChapterNavigationRouter.decideNext(
            currentPage: 9, totalPages: 10,
            currentSpineIndex: 0, spineCount: 1
        )
        XCTAssertEqual(decision, .bounceAtEndOfBook)
    }

    func test_previousAtFirstPageOfOnlyChapter_bouncesAtStartOfBook() {
        let decision = EPUBChapterNavigationRouter.decidePrevious(
            currentPage: 0, totalPages: 10,
            currentSpineIndex: 0, spineCount: 1
        )
        XCTAssertEqual(decision, .bounceAtStartOfBook)
    }

    // MARK: - Edge: stale spine index (out-of-range) — treats as final

    func test_nextWithSpineIndexBeyondCount_treatsAsFinalChapter() {
        // Defensive: spine index 10 with count 5 should bounce (can't wrap)
        let decision = EPUBChapterNavigationRouter.decideNext(
            currentPage: 9, totalPages: 10,
            currentSpineIndex: 10, spineCount: 5
        )
        XCTAssertEqual(decision, .bounceAtEndOfBook)
    }

    func test_previousWithNegativeSpineIndex_treatsAsInitialChapter() {
        let decision = EPUBChapterNavigationRouter.decidePrevious(
            currentPage: 0, totalPages: 10,
            currentSpineIndex: -1, spineCount: 5
        )
        XCTAssertEqual(decision, .bounceAtStartOfBook)
    }

    // Round-1 audit finding [2] (Medium): asymmetric stale-spine-index
    // handling. Previously `decideNext(currentSpineIndex: -1)` returned
    // `.wrapToNextChapter` and `decidePrevious(currentSpineIndex: spineCount)`
    // returned `.wrapToPreviousChapter`. Both must bounce.

    func test_nextWithNegativeSpineIndex_treatsAsBounceNotWrap() {
        // Stale / out-of-range backward — must NOT wrap forward into a
        // chapter the user wasn't reading.
        let decision = EPUBChapterNavigationRouter.decideNext(
            currentPage: 9, totalPages: 10,
            currentSpineIndex: -1, spineCount: 5
        )
        XCTAssertEqual(decision, .bounceAtEndOfBook)
    }

    func test_previousWithSpineIndexEqualToCount_treatsAsBounceNotWrap() {
        // currentSpineIndex == spineCount (one past end) — must NOT
        // wrap backward into the previous chapter from an unknown
        // position.
        let decision = EPUBChapterNavigationRouter.decidePrevious(
            currentPage: 0, totalPages: 10,
            currentSpineIndex: 5, spineCount: 5
        )
        XCTAssertEqual(decision, .bounceAtStartOfBook)
    }
}
