// Purpose: Side-tap navigation handlers for EPUBReaderContainerView that
// implement design §2.2 (paged-mode chapter wrap). When a tap fires
// `.readerNextPage` / `.readerPreviousPage` AND the current page is the
// last / first page of the chapter, the container forwards to the
// chapter-wrap path instead of letting `BasePageNavigator` no-op at the
// clamp.
//
// Background: Bug #165 / GH #489 — pre-fix, side-tap at the chapter
// boundary was a no-op (the page navigator silently clamped at
// totalPages-1 / 0). Per design §2.2 the user-expected behavior at the
// boundary is to advance to the next chapter's first page (right-tap)
// or the previous chapter's last page (left-tap), matching Apple Books
// and Kindle.
//
// Design source: dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md §2.2
//
// @coordinates-with: EPUBChapterNavigationRouter.swift (pure decision
//                    logic), EPUBChapterWrapPendingTarget.swift (one-shot
//                    "land on last page" intent), EPUBReaderContainerView.swift
//                    (.readerNextPage / .readerPreviousPage observers).

#if canImport(UIKit)
import SwiftUI

extension EPUBReaderContainerView {

    /// Right-edge side-tap (or any next-page command). Decides whether
    /// to turn within the current chapter, wrap forward to the next
    /// chapter, or bounce at the end of the book.
    func handleSideTapNext() {
        let decision = EPUBChapterNavigationRouter.decideNext(
            currentPage: pageNavigator.currentPage,
            totalPages: pageNavigator.totalPages,
            currentSpineIndex: viewModel.currentSpineIndex,
            spineCount: viewModel.metadata?.spineCount ?? 0
        )
        switch decision {
        case .withinChapter:
            pageNavigator.nextPage()
            currentPaginationPage = pageNavigator.currentPage
        case .wrapToNextChapter:
            wrapForward()
        case .bounceAtEndOfBook:
            // Design §2.2's "subtle horizontal nudge" affordance is
            // not yet visually specified; the bounce surfaces as a
            // no-op for now (matches the legacy clamp). Documented as
            // a known gap so a follow-up can wire haptic / animation
            // once the spec lands.
            break
        case .wrapToPreviousChapter, .bounceAtStartOfBook:
            // Defensive — decideNext never returns these. Treat as
            // legacy clamp to avoid mis-navigating.
            pageNavigator.nextPage()
            currentPaginationPage = pageNavigator.currentPage
        }
    }

    /// Left-edge side-tap (or any previous-page command). Decides
    /// whether to turn within the current chapter, wrap backward to
    /// the previous chapter's LAST page, or bounce at the start of
    /// the book.
    func handleSideTapPrevious() {
        let decision = EPUBChapterNavigationRouter.decidePrevious(
            currentPage: pageNavigator.currentPage,
            totalPages: pageNavigator.totalPages,
            currentSpineIndex: viewModel.currentSpineIndex,
            spineCount: viewModel.metadata?.spineCount ?? 0
        )
        switch decision {
        case .withinChapter:
            pageNavigator.previousPage()
            currentPaginationPage = pageNavigator.currentPage
        case .wrapToPreviousChapter:
            wrapBackward()
        case .bounceAtStartOfBook:
            break // Same rationale as bounceAtEndOfBook above.
        case .wrapToNextChapter, .bounceAtEndOfBook:
            pageNavigator.previousPage()
            currentPaginationPage = pageNavigator.currentPage
        }
    }

    // MARK: - Wrap helpers

    /// Advance to the next chapter and reset the page navigator. The
    /// `currentHref` binding on `EPUBWebViewBridge` watches
    /// `viewModel.currentPosition?.href` and triggers a `loadFileURL`
    /// when it changes; `onPaginationReady` sets `pageNavigator.totalPages`
    /// once the new chapter has paginated.
    private func wrapForward() {
        guard let meta = viewModel.metadata,
              let base = resourceBase else { return }
        let nextIndex = viewModel.currentSpineIndex + 1
        guard nextIndex >= 0, nextIndex < meta.spineItems.count else { return }
        chapterWrapPendingTarget.clear()
        navigateToSpineForWrap(index: nextIndex, meta: meta, base: base)
    }

    /// Step back to the previous chapter AND arm
    /// `chapterWrapPendingTarget` so the new chapter's
    /// `onPaginationReady` callback lands on the last page.
    private func wrapBackward() {
        guard let meta = viewModel.metadata,
              let base = resourceBase else { return }
        let previousIndex = viewModel.currentSpineIndex - 1
        guard previousIndex >= 0, previousIndex < meta.spineItems.count else { return }
        chapterWrapPendingTarget.armWantsLastPage()
        navigateToSpineForWrap(index: previousIndex, meta: meta, base: base)
    }

    /// Shared chapter-load tail used by `wrapForward` / `wrapBackward`.
    /// Mirrors the body of the existing `.readerNavigateToLocator`
    /// observer minus the locator-specific search-highlight injection
    /// (a side-tap wrap never carries a `textQuote`).
    private func navigateToSpineForWrap(
        index: Int,
        meta: EPUBMetadata,
        base: URL
    ) {
        viewModel.navigateToSpine(index: index)
        webViewError = nil
        // Reset pagination on chapter nav so the new chapter starts at
        // page 0 (`onPaginationReady` may then jump to last page when
        // `chapterWrapPendingTarget.wantsLastPage` is armed).
        pageNavigator.reset()
        currentPaginationPage = nil
        seekScrollFraction = nil
        let href = meta.spineItems[index].href
        Task { await ensureChapterExtracted(href: href) } // bug #102
        contentURL = base.appendingPathComponent(href)
    }
}
#endif
