// Purpose: Bug #284 / GH #1261 — unit tests for the pure cross-chapter
// page-advance decision logic in TXT paged mode. Before this fix, TXT paged
// layout rendered only the current chapter in a single non-chunked text view
// and `.readerNextPage` was a no-op (the page navigator was never created), so
// the reader could not advance past a chapter boundary except via the TOC.
//
// These tests lock the PURE decision: given the current page within the
// current chapter, the chapter's total page count, and whether adjacent
// chapters exist, decide whether a next/previous "page" turn stays within the
// chapter, crosses to the adjacent chapter (and which page it lands on), or
// clamps at a document boundary.
//
// @coordinates-with: TXTPagedChapterAdvance.swift

import Testing
@testable import vreader

@Suite("TXTPagedChapterAdvance decision logic")
struct TXTPagedChapterAdvanceTests {

    // MARK: - Next page (forward)

    @Test func next_withinChapter_whenNotOnLastPage() {
        // Page 0 of a 3-page chapter → advance within the chapter.
        let decision = TXTPagedChapterAdvance.next(
            currentPage: 0, totalPages: 3, hasNextChapter: true
        )
        #expect(decision == .withinChapter)
    }

    @Test func next_withinChapter_whenMiddlePage() {
        let decision = TXTPagedChapterAdvance.next(
            currentPage: 1, totalPages: 3, hasNextChapter: true
        )
        #expect(decision == .withinChapter)
    }

    @Test func next_crossesToNextChapterFirstPage_onLastPageWithNextChapter() {
        // On the last page (index 2 of 3) with a next chapter available →
        // load the next chapter and land on its first page (design §2.2:
        // "→ page 1 of chapter N+1").
        let decision = TXTPagedChapterAdvance.next(
            currentPage: 2, totalPages: 3, hasNextChapter: true
        )
        #expect(decision == .crossToNextChapter)
    }

    @Test func next_clampsAtEnd_onLastPageOfLastChapter() {
        // Last page of the last chapter → clamp (design §2.2: bounce, no nav).
        let decision = TXTPagedChapterAdvance.next(
            currentPage: 2, totalPages: 3, hasNextChapter: false
        )
        #expect(decision == .clampAtDocumentEnd)
    }

    @Test func next_singlePageChapter_crossesWhenNextChapterExists() {
        // A 1-page chapter: page 0 IS the last page → cross to next chapter.
        let decision = TXTPagedChapterAdvance.next(
            currentPage: 0, totalPages: 1, hasNextChapter: true
        )
        #expect(decision == .crossToNextChapter)
    }

    @Test func next_singlePageLastChapter_clamps() {
        let decision = TXTPagedChapterAdvance.next(
            currentPage: 0, totalPages: 1, hasNextChapter: false
        )
        #expect(decision == .clampAtDocumentEnd)
    }

    // MARK: - Previous page (backward)

    @Test func previous_withinChapter_whenNotOnFirstPage() {
        let decision = TXTPagedChapterAdvance.previous(
            currentPage: 2, totalPages: 3, hasPreviousChapter: true
        )
        #expect(decision == .withinChapter)
    }

    @Test func previous_crossesToPreviousChapterLastPage_onFirstPageWithPreviousChapter() {
        // On the first page (index 0) with a previous chapter → load the
        // previous chapter and land on its LAST page (design §2.2:
        // "→ last page of chapter N-1").
        let decision = TXTPagedChapterAdvance.previous(
            currentPage: 0, totalPages: 3, hasPreviousChapter: true
        )
        #expect(decision == .crossToPreviousChapter)
    }

    @Test func previous_clampsAtStart_onFirstPageOfFirstChapter() {
        let decision = TXTPagedChapterAdvance.previous(
            currentPage: 0, totalPages: 3, hasPreviousChapter: false
        )
        #expect(decision == .clampAtDocumentStart)
    }

    // MARK: - Edge cases: empty / zero-page chapters

    @Test func next_zeroPageChapter_crossesWhenNextExists() {
        // A chapter that paginated to 0 pages (empty/short chapter) must not
        // trap the reader — treat page 0 as the boundary and cross forward.
        let decision = TXTPagedChapterAdvance.next(
            currentPage: 0, totalPages: 0, hasNextChapter: true
        )
        #expect(decision == .crossToNextChapter)
    }

    @Test func next_zeroPageLastChapter_clamps() {
        let decision = TXTPagedChapterAdvance.next(
            currentPage: 0, totalPages: 0, hasNextChapter: false
        )
        #expect(decision == .clampAtDocumentEnd)
    }

    @Test func previous_zeroPageChapter_crossesWhenPreviousExists() {
        let decision = TXTPagedChapterAdvance.previous(
            currentPage: 0, totalPages: 0, hasPreviousChapter: true
        )
        #expect(decision == .crossToPreviousChapter)
    }

    // MARK: - Landing-page resolution after a cross-chapter load

    @Test func landingPageAfterCrossForward_isFirstPage() {
        // After loading the next chapter (any page count), forward crossing
        // lands on page 0.
        #expect(TXTPagedChapterAdvance.landingPageForwardCross(newTotalPages: 5) == 0)
        #expect(TXTPagedChapterAdvance.landingPageForwardCross(newTotalPages: 1) == 0)
        #expect(TXTPagedChapterAdvance.landingPageForwardCross(newTotalPages: 0) == 0)
    }

    @Test func landingPageAfterCrossBackward_isLastPage() {
        // After loading the previous chapter, backward crossing lands on the
        // last page (totalPages - 1), clamped to 0 for empty chapters.
        #expect(TXTPagedChapterAdvance.landingPageBackwardCross(newTotalPages: 5) == 4)
        #expect(TXTPagedChapterAdvance.landingPageBackwardCross(newTotalPages: 1) == 0)
        #expect(TXTPagedChapterAdvance.landingPageBackwardCross(newTotalPages: 0) == 0)
    }

    // MARK: - TXTPagedLanding target encoding (Codex Gate-4 Round-1 fix)
    //
    // The landing carries the chapter index it targets so the container applies
    // it ONLY when the view model has actually loaded that chapter — guarding
    // against a failed/aborted load (index unchanged → never matches) and a
    // rapid double-tap (intermediate chapter → never matches the newer target).

    @Test func landing_forwardCarriesNextChapterIndexAndFirstEdge() {
        // A forward cross from chapter 3 targets chapter 4's first page.
        let landing = TXTPagedLanding(targetChapterIndex: 4, edge: .firstPage)
        #expect(landing.targetChapterIndex == 4)
        #expect(landing.edge == .firstPage)
    }

    @Test func landing_backwardCarriesPreviousChapterIndexAndLastEdge() {
        let landing = TXTPagedLanding(targetChapterIndex: 2, edge: .lastPage)
        #expect(landing.targetChapterIndex == 2)
        #expect(landing.edge == .lastPage)
    }

    @Test func landing_distinctTargetsAreNotEqual() {
        // Two landings for different chapters must not compare equal — the
        // container's `targetChapterIndex == currentChapterIdx` gate relies on
        // distinguishing them so a stale landing is never consumed by the wrong
        // chapter's rebuild.
        let a = TXTPagedLanding(targetChapterIndex: 4, edge: .firstPage)
        let b = TXTPagedLanding(targetChapterIndex: 5, edge: .firstPage)
        #expect(a != b)
    }

    @Test func landing_sameTargetDifferentEdgeAreNotEqual() {
        let a = TXTPagedLanding(targetChapterIndex: 4, edge: .firstPage)
        let b = TXTPagedLanding(targetChapterIndex: 4, edge: .lastPage)
        #expect(a != b)
    }
}
