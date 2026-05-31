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

    // MARK: - WI-4: tap-zone mirror

    @Test func tapZoneConfig_ltr_unchanged() {
        let cfg = EPUBPagedAxis.tapZoneConfig(base: .default, axis: .horizontalLTR)
        #expect(cfg == TapZoneConfig.default)
        #expect(cfg.leftAction == .previousPage)
        #expect(cfg.rightAction == .nextPage)
    }

    @Test func tapZoneConfig_rtl_mirrorsLeftRight() {
        let cfg = EPUBPagedAxis.tapZoneConfig(base: .default, axis: .horizontalRTL)
        #expect(cfg.leftAction == .nextPage)      // leading edge advances in RTL
        #expect(cfg.rightAction == .previousPage)
        #expect(cfg.centerAction == .toggleChrome) // center unchanged
    }

    @Test func tapZoneConfig_verticalRL_mirrors() {
        let cfg = EPUBPagedAxis.tapZoneConfig(base: .default, axis: .verticalRL)
        #expect(cfg.leftAction == .nextPage)
        #expect(cfg.rightAction == .previousPage)
    }

    @Test func tapZoneConfig_preservesCustomBase() {
        let base = TapZoneConfig(leftAction: .none, centerAction: .nextPage, rightAction: .previousPage)
        let cfg = EPUBPagedAxis.tapZoneConfig(base: base, axis: .horizontalRTL)
        #expect(cfg.leftAction == .previousPage)  // was rightAction
        #expect(cfg.centerAction == .nextPage)    // unchanged
        #expect(cfg.rightAction == .none)         // was leftAction
    }

    // MARK: - WI-4: swipe inversion

    @Test func swipeOutcome_ltr_unchanged() {
        #expect(EPUBPagedAxis.swipeOutcome(.nextPage, axis: .horizontalLTR) == .nextPage)
        #expect(EPUBPagedAxis.swipeOutcome(.previousPage, axis: .horizontalLTR) == .previousPage)
        #expect(EPUBPagedAxis.swipeOutcome(.none, axis: .horizontalLTR) == .none)
    }

    @Test func swipeOutcome_rtl_inverts() {
        #expect(EPUBPagedAxis.swipeOutcome(.nextPage, axis: .horizontalRTL) == .previousPage)
        #expect(EPUBPagedAxis.swipeOutcome(.previousPage, axis: .horizontalRTL) == .nextPage)
        #expect(EPUBPagedAxis.swipeOutcome(.none, axis: .horizontalRTL) == .none)
    }

    @Test func swipeOutcome_verticalRL_inverts() {
        #expect(EPUBPagedAxis.swipeOutcome(.nextPage, axis: .verticalRL) == .previousPage)
        #expect(EPUBPagedAxis.swipeOutcome(.previousPage, axis: .verticalRL) == .nextPage)
    }
}
