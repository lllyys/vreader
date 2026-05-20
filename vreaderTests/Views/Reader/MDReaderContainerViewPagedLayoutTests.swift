// Purpose: Bug #215 / GH #837 — unit tests for the MD paged-mode layout
// helpers. Locks the formulas that the rendered behavior depends on:
//
// - `pagedBottomPadding(chromeVisible:)` reserves the right amount of space
//   for the opaque `ReaderBottomChrome` overlay (design §3.1).
// - `paginatorViewportSize(proxy:chromeVisible:)` subtracts the chrome-
//   aware bottom padding, the page-indicator's reserved height (when chrome
//   hidden), AND the paged textView's `textContainerInset` so the
//   paginator's `NSTextContainer` size matches what the renderer actually
//   displays (Codex audit Round-1 High #1).
//
// These are extracted `static` seams on `MDReaderContainerView` precisely
// so they can be unit-tested without standing up a SwiftUI view tree.
//
// @coordinates-with: MDReaderContainerView.swift, NativeTextPagedView.swift

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

@Suite("MDReaderContainerView paged layout helpers")
struct MDReaderContainerViewPagedLayoutTests {

    // MARK: - pagedBottomPadding

    @Test func pagedBottomPadding_chromeVisible_reservesChromeHeightPlusBreath() {
        // Design §3.1: chrome-visible bottom padding ≈ chrome height + 8pt
        // breath. Today's chrome measured ≈128pt on iPhone 17 Pro Sim; the
        // helper locks 128 + 8 = 136.
        #expect(MDReaderContainerView.pagedBottomPadding(chromeVisible: true) == 136)
    }

    @Test func pagedBottomPadding_chromeHidden_usesDesignBaseline() {
        // Design §3.1: chrome-hidden baseline = 56pt so the page extends
        // close to the edge with room for the compact indicator.
        #expect(MDReaderContainerView.pagedBottomPadding(chromeVisible: false) == 56)
    }

    // MARK: - paginatorViewportSize

    @Test func paginatorViewportSize_chromeVisible_subtractsChromePaddingAndInset() {
        // For a 400×900 proxy with chrome visible:
        //   bottom = 136 (chrome height + breath)
        //   indicator reserved = 0 (hidden when chrome visible)
        //   inset = 16 on every side → 32 total per axis
        // Width  = 400 - 32 = 368
        // Height = 900 - 136 - 0 - 32 = 732
        let proxy = CGSize(width: 400, height: 900)
        let viewport = MDReaderContainerView.paginatorViewportSize(
            proxy: proxy, chromeVisible: true
        )
        #expect(viewport.width == 368)
        #expect(viewport.height == 732)
    }

    @Test func paginatorViewportSize_chromeHidden_includesIndicatorReservation() {
        // For 400×900 proxy with chrome hidden:
        //   bottom = 56 (chrome-hidden baseline)
        //   indicator reserved = 24
        //   inset = 16 on every side → 32 total per axis
        // Width  = 400 - 32 = 368
        // Height = 900 - 56 - 24 - 32 = 788
        let proxy = CGSize(width: 400, height: 900)
        let viewport = MDReaderContainerView.paginatorViewportSize(
            proxy: proxy, chromeVisible: false
        )
        #expect(viewport.width == 368)
        #expect(viewport.height == 788)
    }

    @Test func paginatorViewportSize_chromeVisibleProducesSmallerPage_thanChromeHidden() {
        // Sanity invariant — chrome visible reserves more vertical room
        // than chrome hidden (because the chrome takes more space than the
        // indicator does). A page computed for the chrome-visible mode must
        // therefore have a smaller usable height. Locks the design's
        // intent without depending on the exact constants.
        let proxy = CGSize(width: 400, height: 900)
        let visible = MDReaderContainerView.paginatorViewportSize(
            proxy: proxy, chromeVisible: true
        )
        let hidden = MDReaderContainerView.paginatorViewportSize(
            proxy: proxy, chromeVisible: false
        )
        #expect(visible.height < hidden.height,
                "chrome-visible viewport should reserve more vertical room")
        #expect(visible.width == hidden.width,
                "horizontal viewport is chrome-independent")
    }

    @Test func paginatorViewportSize_degenerateProxy_clampsToPositive() {
        // A degenerate proxy (zero or smaller than the inset) must not
        // produce a zero/negative viewport — the paginator would either
        // crash or compute pages with zero glyphs. Clamped minimum of 1
        // keeps the pipeline safe across first-render / split-view edge
        // cases.
        let tiny = CGSize(width: 10, height: 10)
        let viewport = MDReaderContainerView.paginatorViewportSize(
            proxy: tiny, chromeVisible: true
        )
        #expect(viewport.width >= 1)
        #expect(viewport.height >= 1)
    }
}
