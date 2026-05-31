// Purpose: Feature #75 WI-2 — pure axis-aware seams for EPUB paged navigation.
// Given a resolved per-document `PageAxis`, produce (a) the body direction /
// writing-mode CSS fragment and (b) the page→scroll-offset for `navigateToPageJS`.
// Kept pure (Int / String generators) so the axis math is unit-testable; the
// actual WKWebView multicol layout is validated on-device in WI-5.
//
// Horizontal LTR/RTL are fully resolved here (LTR is byte-unchanged; RTL uses
// WebKit's negative `scrollLeft` convention — scrollLeft is 0 at the right/start
// edge and goes negative toward later content). `verticalRL` emits its
// writing-mode CSS and uses the SAME negative-`scrollLeft` page advance as RTL
// (vertical-rl columns also overflow horizontally right-to-left); the exact
// WebKit stride for vertical writing is confirmed on-device in WI-5.
//
// @coordinates-with: PageAxisResolver.swift (PageAxis), EPUBPaginationHelper.swift

import Foundation

enum EPUBPagedAxis {
    /// The horizontal page→`scrollLeft` offset for `page` (zero-based) under
    /// `axis`. LTR is `page * viewportWidth`; RTL / vertical-rl negate it
    /// (WebKit's negative-`scrollLeft` RTL convention).
    static func scrollOffset(page: Int, viewportWidth: Int, axis: PageAxis) -> Int {
        let safePage = max(0, page)
        let magnitude = safePage * max(0, viewportWidth)
        switch axis {
        case .horizontalLTR: return magnitude
        case .horizontalRTL, .verticalRL: return -magnitude
        }
    }

    /// The body CSS fragment that sets writing direction for `axis`. Empty for
    /// LTR (no override needed); `direction: rtl` for horizontal RTL; both
    /// `writing-mode: vertical-rl` + `direction: rtl` for vertical-rl. Each
    /// declaration is `!important` to win over the book's stylesheet, matching
    /// the pagination CSS's specificity discipline.
    static func directionCSS(axis: PageAxis) -> String {
        switch axis {
        case .horizontalLTR:
            return ""
        case .horizontalRTL:
            return "direction: rtl !important;"
        case .verticalRL:
            return "writing-mode: vertical-rl !important; direction: rtl !important;"
        }
    }
}
