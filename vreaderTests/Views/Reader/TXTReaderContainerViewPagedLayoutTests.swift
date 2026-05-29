// Purpose: Bug #284 / GH #1261 — unit tests for the TXT paged-mode layout
// helpers (`TXTReaderContainerView+Paged.swift`). Locks the chrome-aware
// viewport formulas the paged renderer depends on, mirroring
// `MDReaderContainerViewPagedLayoutTests` (the TXT formulas are intentionally
// identical so both reflowable formats paginate to the same per-page box;
// they are duplicated rather than shared because the two containers are
// independent value types).
//
// - `pagedBottomPadding(chromeVisible:)` reserves space for the opaque
//   `ReaderBottomChrome` overlay (design §3.1).
// - `paginatorViewportSize(proxy:chromeVisible:)` subtracts the chrome-aware
//   bottom padding, the page-indicator's reserved height (chrome-hidden only),
//   and the paged textView's `textContainerInset` so the paginator's
//   `NSTextContainer` matches the renderer's interior box.
//
// @coordinates-with: TXTReaderContainerView+Paged.swift, NativeTextPagedView.swift

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

#if canImport(UIKit)
@Suite("TXTReaderContainerView paged layout helpers")
@MainActor
struct TXTReaderContainerViewPagedLayoutTests {

    // MARK: - pagedBottomPadding

    @Test func pagedBottomPadding_chromeVisible_reservesChromeHeightPlusBreath() {
        #expect(TXTReaderContainerView.pagedBottomPadding(chromeVisible: true) == 136)
    }

    @Test func pagedBottomPadding_chromeHidden_usesDesignBaseline() {
        #expect(TXTReaderContainerView.pagedBottomPadding(chromeVisible: false) == 56)
    }

    // MARK: - paginatorViewportSize

    @Test func paginatorViewportSize_chromeVisible_subtractsChromePaddingAndInset() {
        // 400×900 proxy, chrome visible: bottom=136, indicator=0, inset=16/side.
        // Width = 400 - 32 = 368; Height = 900 - 136 - 0 - 32 = 732.
        let proxy = CGSize(width: 400, height: 900)
        let viewport = TXTReaderContainerView.paginatorViewportSize(
            proxy: proxy, chromeVisible: true
        )
        #expect(viewport.width == 368)
        #expect(viewport.height == 732)
    }

    @Test func paginatorViewportSize_chromeHidden_includesIndicatorReservation() {
        // 400×900 proxy, chrome hidden: bottom=56, indicator=24, inset=16/side.
        // Width = 400 - 32 = 368; Height = 900 - 56 - 24 - 32 = 788.
        let proxy = CGSize(width: 400, height: 900)
        let viewport = TXTReaderContainerView.paginatorViewportSize(
            proxy: proxy, chromeVisible: false
        )
        #expect(viewport.width == 368)
        #expect(viewport.height == 788)
    }

    @Test func paginatorViewportSize_chromeVisibleProducesSmallerPage_thanChromeHidden() {
        let proxy = CGSize(width: 400, height: 900)
        let visible = TXTReaderContainerView.paginatorViewportSize(
            proxy: proxy, chromeVisible: true
        )
        let hidden = TXTReaderContainerView.paginatorViewportSize(
            proxy: proxy, chromeVisible: false
        )
        #expect(visible.height < hidden.height)
        #expect(visible.width == hidden.width)
    }

    @Test func paginatorViewportSize_degenerateProxy_clampsToPositive() {
        let tiny = CGSize(width: 10, height: 10)
        let viewport = TXTReaderContainerView.paginatorViewportSize(
            proxy: tiny, chromeVisible: true
        )
        #expect(viewport.width >= 1)
        #expect(viewport.height >= 1)
    }

    // MARK: - Parity with MD (both reflowable formats paginate to the same box)

    @Test func txt_matchesMDFormula_forParity() {
        let proxy = CGSize(width: 393, height: 852) // iPhone 17 Pro points
        for chromeVisible in [true, false] {
            let txt = TXTReaderContainerView.paginatorViewportSize(
                proxy: proxy, chromeVisible: chromeVisible
            )
            let md = MDReaderContainerView.paginatorViewportSize(
                proxy: proxy, chromeVisible: chromeVisible
            )
            #expect(txt == md, "TXT + MD paged viewport formulas must stay identical")
        }
    }
}
#endif
