// Purpose: Bug #348 — pins the no-system-scroll-indicator policy for
// reader content surfaces: the single-scroller helper, the recursive
// traversal (Readium spine webviews / PDFView wrap their scrollers
// privately), and the continuous stitched root's CSS scrollbar hide
// (the primary offender — the overlay scrollbar tracked the loaded
// WINDOW, not the book).

import Testing
import UIKit
@testable import vreader

@Suite("ReaderScrollIndicatorPolicy (bug #348)")
@MainActor
struct ReaderScrollIndicatorPolicyTests {

    @Test func hidesBothIndicatorsOnOneScroller() {
        let scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        ReaderScrollIndicatorPolicy.hide(on: scrollView)
        #expect(!scrollView.showsVerticalScrollIndicator)
        #expect(!scrollView.showsHorizontalScrollIndicator)
    }

    @Test func traversalReachesNestedScrollers() {
        // Readium/PDFKit wrap their scrollers privately — the policy must
        // find them at any depth.
        let root = UIView()
        let mid = UIView()
        let deep = UIScrollView()
        deep.showsVerticalScrollIndicator = true
        let shallow = UITableView()   // UITableView IS a UIScrollView
        shallow.showsVerticalScrollIndicator = true
        root.addSubview(shallow)
        root.addSubview(mid)
        mid.addSubview(deep)
        ReaderScrollIndicatorPolicy.hideIndicators(in: root)
        #expect(!deep.showsVerticalScrollIndicator)
        #expect(!shallow.showsVerticalScrollIndicator)
    }

    @Test func continuousBootstrapHidesTheStitchedRootsScrollbar() {
        // The stitched window's overlay scrollbar is misleading (it tracks
        // the loaded window and jumps on every append/evict) — the
        // bootstrap CSS must suppress it in both vendor forms.
        let html = EPUBContinuousScrollJS.bootstrapDocumentHTML(themeCSS: "")
        #expect(html.contains("::-webkit-scrollbar { display: none;"))
        #expect(html.contains("scrollbar-width: none;"))
    }
}
