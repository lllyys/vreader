// Purpose: Tests for EPUBChapterWrapPendingTarget — a small state holder
// that the container uses to record "after pagination is ready in the
// newly-loaded chapter, jump to the LAST page". This is the missing link
// between `viewModel.navigatePrevious()` (which lands on page 0 of the
// previous chapter) and design §2.2's requirement that a left-tap from
// the first page of chapter N goes to the LAST page of chapter N-1.
//
// The pure type holds a one-shot intent that the container's
// `onPaginationReady` callback consumes.
//
// @coordinates-with: EPUBChapterNavigationRouter.swift,
//                    EPUBReaderContainerView.swift

import XCTest
@testable import vreader

@MainActor
final class EPUBChapterWrapPendingTargetTests: XCTestCase {

    // MARK: - lifecycle

    func test_initiallyHasNoPendingTarget() {
        let target = EPUBChapterWrapPendingTarget()
        XCTAssertFalse(target.wantsLastPage)
    }

    func test_setWantsLastPage_marksTrueOneShot() {
        let target = EPUBChapterWrapPendingTarget()
        target.armWantsLastPage()
        XCTAssertTrue(target.wantsLastPage)
    }

    func test_consume_returnsResolvedPageAndClears() {
        let target = EPUBChapterWrapPendingTarget()
        target.armWantsLastPage()
        let resolved = target.consume(totalPages: 7)
        XCTAssertEqual(resolved, 6)
        XCTAssertFalse(target.wantsLastPage)
    }

    func test_consumeWithoutArming_returnsNil() {
        let target = EPUBChapterWrapPendingTarget()
        XCTAssertNil(target.consume(totalPages: 7))
    }

    func test_consumeWithZeroTotalPages_returnsNil() {
        // Pagination not ready / empty doc — don't crash, don't jump.
        let target = EPUBChapterWrapPendingTarget()
        target.armWantsLastPage()
        XCTAssertNil(target.consume(totalPages: 0))
        // Intent stays armed so a subsequent valid totalPages can resolve.
        XCTAssertTrue(target.wantsLastPage)
    }

    func test_consumeWithNegativeTotalPages_returnsNil() {
        let target = EPUBChapterWrapPendingTarget()
        target.armWantsLastPage()
        XCTAssertNil(target.consume(totalPages: -1))
        XCTAssertTrue(target.wantsLastPage)
    }

    func test_consumeWithSinglePage_returnsZero() {
        let target = EPUBChapterWrapPendingTarget()
        target.armWantsLastPage()
        XCTAssertEqual(target.consume(totalPages: 1), 0)
        XCTAssertFalse(target.wantsLastPage)
    }

    func test_armAndClear_clearsWithoutResolving() {
        let target = EPUBChapterWrapPendingTarget()
        target.armWantsLastPage()
        target.clear()
        XCTAssertFalse(target.wantsLastPage)
    }

    // MARK: - Audit round-1 finding [1] (High): bleeding-intent regression

    /// The container clears `chapterWrapPendingTarget` from
    /// `.readerNavigateToLocator` (TOC / search) and `handleProgressSeek`
    /// (scrubber). This regression test pins the contract those clears
    /// rely on: after `clear()`, a subsequent `consume(totalPages:)`
    /// returns nil even with a sensible totalPages — so a stale
    /// `onPaginationReady` cannot accidentally jump the user to the
    /// last page of the unrelated chapter they navigated to.
    func test_clearAfterArm_consumeReturnsNilEvenWithValidTotalPages() {
        let target = EPUBChapterWrapPendingTarget()
        target.armWantsLastPage()
        target.clear()
        // The unrelated chapter loads with valid pagination, but the
        // pending target is gone — no spurious jump.
        XCTAssertNil(target.consume(totalPages: 12))
        XCTAssertFalse(target.wantsLastPage)
    }

    /// Double-clear is idempotent — protects against a path that
    /// pre-emptively clears AND a later path also clears before
    /// pagination resolves.
    func test_doubleClear_isIdempotent() {
        let target = EPUBChapterWrapPendingTarget()
        target.armWantsLastPage()
        target.clear()
        target.clear()
        XCTAssertFalse(target.wantsLastPage)
        XCTAssertNil(target.consume(totalPages: 12))
    }

    /// After a successful consume, a subsequent consume returns nil —
    /// preserves the one-shot semantics. Without this the second
    /// chapter load (e.g. user side-taps forward immediately after a
    /// successful backward wrap) would also be pushed to last page.
    func test_consume_doesNotReArmForSubsequentChapterLoad() {
        let target = EPUBChapterWrapPendingTarget()
        target.armWantsLastPage()
        _ = target.consume(totalPages: 5)
        // Second chapter loads — pending target should NOT resolve.
        XCTAssertNil(target.consume(totalPages: 5))
    }

    // MARK: - Audit round-2 fix [Medium]: dedicated cancel entry point

    /// The container calls `cancelBecauseUnrelatedNavigationStarted()`
    /// from `.readerNavigateToLocator` (TOC / search) and
    /// `handleProgressSeek` (scrubber) so a future call-site grep can
    /// be precise. Functionally equivalent to `clear()`.
    func test_cancelBecauseUnrelatedNavigationStarted_dropsIntent() {
        let target = EPUBChapterWrapPendingTarget()
        target.armWantsLastPage()
        target.cancelBecauseUnrelatedNavigationStarted()
        XCTAssertFalse(target.wantsLastPage)
        XCTAssertNil(target.consume(totalPages: 12))
    }

    /// Cancel is idempotent when there's nothing to cancel — protects
    /// the common case where the user navigates via TOC without ever
    /// having armed a backward wrap.
    func test_cancelBecauseUnrelatedNavigationStarted_isIdempotentWhenUnarmed() {
        let target = EPUBChapterWrapPendingTarget()
        target.cancelBecauseUnrelatedNavigationStarted()
        XCTAssertFalse(target.wantsLastPage)
    }
}
