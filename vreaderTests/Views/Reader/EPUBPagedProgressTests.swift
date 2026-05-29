// Purpose: Tests for EPUBPagedProgress — the pure seam mapping a within-chapter
// paged position (currentPage / totalPages) to an intra-chapter progress
// fraction (0.0...1.0), so within-chapter paged turns drive the progress bar /
// "Chapter X of Y" / persisted position the same way vertical scroll does.
//
// Bug #281 / GH #1258 — pre-fix, paged page turns only changed `scrollLeft`
// and never produced an `onProgressChange`, so progress froze within a chapter.
//
// @coordinates-with: EPUBPagedProgress.swift, EPUBProgressCalculator.swift

import Testing
import Foundation
@testable import vreader

@Suite("EPUBPagedProgress - intraChapterFraction")
struct EPUBPagedProgressIntraChapterTests {

    @Test("first page of a multi-page chapter is fraction 0")
    func firstPage_isZero() {
        #expect(EPUBPagedProgress.intraChapterFraction(currentPage: 0, totalPages: 10) == 0.0)
    }

    @Test("last page of a multi-page chapter is fraction 1")
    func lastPage_isOne() {
        // page 9 of 10 → 9 / (10 - 1) = 1.0
        #expect(EPUBPagedProgress.intraChapterFraction(currentPage: 9, totalPages: 10) == 1.0)
    }

    @Test("middle page maps to the proportional fraction")
    func middlePage_isProportional() {
        // page 1 of 5 → 1 / 4 = 0.25
        #expect(EPUBPagedProgress.intraChapterFraction(currentPage: 1, totalPages: 5) == 0.25)
        // page 2 of 5 → 2 / 4 = 0.5
        #expect(EPUBPagedProgress.intraChapterFraction(currentPage: 2, totalPages: 5) == 0.5)
    }

    @Test("single-page chapter is always fraction 0")
    func singlePageChapter_isZero() {
        // A single page can't move within the chapter; report chapter-start.
        #expect(EPUBPagedProgress.intraChapterFraction(currentPage: 0, totalPages: 1) == 0.0)
    }

    @Test("zero total pages (not paginated yet) is fraction 0")
    func zeroTotalPages_isZero() {
        #expect(EPUBPagedProgress.intraChapterFraction(currentPage: 0, totalPages: 0) == 0.0)
        #expect(EPUBPagedProgress.intraChapterFraction(currentPage: 3, totalPages: 0) == 0.0)
    }

    @Test("negative page clamps to 0")
    func negativePage_clampsToZero() {
        #expect(EPUBPagedProgress.intraChapterFraction(currentPage: -1, totalPages: 10) == 0.0)
    }

    @Test("page beyond last clamps to 1")
    func overflowPage_clampsToOne() {
        // page 99 of 10 → clamp to last page → fraction 1.0, never > 1.
        #expect(EPUBPagedProgress.intraChapterFraction(currentPage: 99, totalPages: 10) == 1.0)
    }

    @Test("negative total pages is fraction 0 (defensive)")
    func negativeTotalPages_isZero() {
        #expect(EPUBPagedProgress.intraChapterFraction(currentPage: 0, totalPages: -5) == 0.0)
    }

    @Test("matches BasePageNavigator.progression contract")
    func matchesNavigatorProgression() {
        // BasePageNavigator.progression = currentPage / (totalPages - 1) for
        // totalPages > 1, else 0. The seam must agree so the live page
        // navigator and the persisted fraction never disagree.
        #expect(EPUBPagedProgress.intraChapterFraction(currentPage: 3, totalPages: 7)
                == 3.0 / 6.0)
    }
}

// MARK: - Whole-book composition (the container's exact arithmetic)

@Suite("EPUBPagedProgress + EPUBProgressCalculator composition")
struct EPUBPagedWholeBookProgressTests {

    @Test("within-chapter paged turn advances whole-book progress")
    func pagedTurn_advancesWholeBookProgress() {
        // Chapter 1 (spineIndex 0) of 4 spine items, 10 pages. The container
        // composes the intra-chapter fraction with the spine offset exactly the
        // way the vertical-scroll fraction already flows through
        // `EPUBProgressCalculator.progress`. Paging from page 0 → page 5 must
        // move whole-book progress; pre-fix it stayed frozen at 0.0.
        let totalPages = 10
        let spineIndex = 0
        let totalSpine = 4

        let fracPage0 = EPUBPagedProgress.intraChapterFraction(currentPage: 0, totalPages: totalPages)
        let fracPage5 = EPUBPagedProgress.intraChapterFraction(currentPage: 5, totalPages: totalPages)

        let progPage0 = EPUBProgressCalculator.progress(
            spineIndex: spineIndex, scrollFraction: fracPage0, totalSpineItems: totalSpine
        )
        let progPage5 = EPUBProgressCalculator.progress(
            spineIndex: spineIndex, scrollFraction: fracPage5, totalSpineItems: totalSpine
        )
        #expect(progPage5 > progPage0)
        // page 5 of 10 → fraction 5/9; whole-book (0 + 5/9)/4.
        #expect(progPage5 == (Double(spineIndex) + 5.0 / 9.0) / Double(totalSpine))
    }

    @Test("last page of a non-final chapter approaches the next chapter boundary")
    func lastPage_approachesNextChapter() {
        // Chapter 2 of 4 (spineIndex 1), last page → fraction 1.0 → whole-book
        // (1 + 1)/4 = 0.5 — i.e. flush against chapter 3's start.
        let frac = EPUBPagedProgress.intraChapterFraction(currentPage: 7, totalPages: 8)
        let prog = EPUBProgressCalculator.progress(
            spineIndex: 1, scrollFraction: frac, totalSpineItems: 4
        )
        #expect(prog == 0.5)
    }
}
