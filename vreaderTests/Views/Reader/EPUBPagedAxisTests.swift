// Feature #75 WI-2 — tests for the pure EPUBPagedAxis seams (page→scroll offset
// + direction CSS per PageAxis). The WKWebView layout behavior is validated
// on-device in WI-5; these pin the pure generators.

import Testing
@testable import vreader

@Suite("EPUBPagedAxis")
struct EPUBPagedAxisTests {

    // MARK: - scrollOffset

    @Test func ltr_offsetIsPositive() {
        #expect(EPUBPagedAxis.scrollOffset(page: 0, viewportWidth: 400, axis: .horizontalLTR) == 0)
        #expect(EPUBPagedAxis.scrollOffset(page: 1, viewportWidth: 400, axis: .horizontalLTR) == 400)
        #expect(EPUBPagedAxis.scrollOffset(page: 3, viewportWidth: 400, axis: .horizontalLTR) == 1200)
    }

    @Test func rtl_offsetIsNegated() {
        // WebKit RTL: scrollLeft 0 at the start (right) edge, negative toward later pages.
        #expect(EPUBPagedAxis.scrollOffset(page: 0, viewportWidth: 400, axis: .horizontalRTL) == 0)
        #expect(EPUBPagedAxis.scrollOffset(page: 1, viewportWidth: 400, axis: .horizontalRTL) == -400)
        #expect(EPUBPagedAxis.scrollOffset(page: 3, viewportWidth: 400, axis: .horizontalRTL) == -1200)
    }

    @Test func verticalRL_usesNegativeScrollLikeRTL() {
        #expect(EPUBPagedAxis.scrollOffset(page: 2, viewportWidth: 400, axis: .verticalRL) == -800)
    }

    @Test func scrollOffset_clampsNegativePageAndWidth() {
        #expect(EPUBPagedAxis.scrollOffset(page: -5, viewportWidth: 400, axis: .horizontalLTR) == 0)
        #expect(EPUBPagedAxis.scrollOffset(page: 2, viewportWidth: -400, axis: .horizontalLTR) == 0)
        #expect(EPUBPagedAxis.scrollOffset(page: -5, viewportWidth: 400, axis: .horizontalRTL) == 0)
    }

    // MARK: - directionCSS

    @Test func ltr_directionCSS_isEmpty() {
        #expect(EPUBPagedAxis.directionCSS(axis: .horizontalLTR) == "")
    }

    @Test func rtl_directionCSS_setsDirectionRTL() {
        let css = EPUBPagedAxis.directionCSS(axis: .horizontalRTL)
        #expect(css.contains("direction: rtl !important;"))
        #expect(!css.contains("writing-mode"))
    }

    @Test func verticalRL_directionCSS_setsWritingModeAndDirection() {
        let css = EPUBPagedAxis.directionCSS(axis: .verticalRL)
        #expect(css.contains("writing-mode: vertical-rl !important;"))
        #expect(css.contains("direction: rtl !important;"))
    }

    // MARK: - paginationCSS integration (LTR byte-identity + non-LTR injection)

    @Test func paginationCSS_ltr_hasNoDirectionDeclarations() {
        let css = EPUBPaginationHelper.paginationCSS(viewportWidth: 400, viewportHeight: 800)
        #expect(!css.contains("direction:"))
        #expect(!css.contains("writing-mode:"))
    }

    @Test func paginationCSS_ltr_defaultMatchesExplicitLTR() {
        // The default (no axis) must be byte-identical to explicit .horizontalLTR.
        let implicit = EPUBPaginationHelper.paginationCSS(viewportWidth: 400, viewportHeight: 800)
        let explicit = EPUBPaginationHelper.paginationCSS(
            viewportWidth: 400, viewportHeight: 800, axis: .horizontalLTR)
        #expect(implicit == explicit)
    }

    @Test func paginationCSS_rtl_injectsDirection() {
        let css = EPUBPaginationHelper.paginationCSS(
            viewportWidth: 400, viewportHeight: 800, axis: .horizontalRTL)
        #expect(css.contains("direction: rtl !important;"))
    }

    @Test func paginationCSS_verticalRL_injectsWritingMode() {
        let css = EPUBPaginationHelper.paginationCSS(
            viewportWidth: 400, viewportHeight: 800, axis: .verticalRL)
        #expect(css.contains("writing-mode: vertical-rl !important;"))
    }

    @Test func navigateToPageJS_rtl_usesNegativeOffset() {
        let js = EPUBPaginationHelper.navigateToPageJS(
            page: 2, viewportWidth: 400, axis: .horizontalRTL)
        #expect(js.contains("scrollLeft = -800"))
    }
}
