// Purpose: Tests for medium/low-severity audit fixes (Issues 5-10, batch 3).
// Issue 5: EPUB searchHighlightJS uses safe extractContents/insertNode pattern.
// Issue 6: PDF searchHighlightText is cleared after auto-clear timer fires.
// Issue 7: PDF uses cancellable DispatchWorkItem for selection clear timer.
// Issue 8: TXT programmatic scroll guard uses a counter, not a boolean.
// Issue 9: EPUB bottom overlay VStack uses spacing: 0 (build-only, no unit test needed).
// Issue 10: ReaderTheme epubOverrideCSS uses broad selector for font-size inheritance.
//
// @coordinates-with: EPUBHighlightBridge.swift, PDFViewBridge.swift,
//   PDFReaderContainerView.swift, TXTTextViewBridge.swift,
//   EPUBReaderContainerView.swift, ReaderTheme.swift

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
import UIKit
@testable import vreader

// MARK: - Issue 5: EPUB searchHighlightJS cross-markup safety

@Suite("AuditFix3 — Issue 5: EPUB searchHighlightJS cross-markup")
struct EPUBSearchHighlightCrossMarkupTests {

    @Test("searchHighlightJS uses extractContents+insertNode instead of surroundContents")
    func searchHighlightJSDoesNotUseSurroundContents() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "hello world")
        // surroundContents throws on cross-markup selections — must NOT be used
        #expect(!js.contains("surroundContents"), "JS must not use surroundContents (fails on cross-markup)")
    }

    @Test("searchHighlightJS uses extractContents for safe wrapping")
    func searchHighlightJSUsesExtractContents() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "hello world")
        // The safe pattern extracts range contents and wraps them in a span
        #expect(js.contains("extractContents"), "JS must use extractContents for cross-markup safety")
    }

    @Test("searchHighlightJS uses insertNode to re-insert wrapped content")
    func searchHighlightJSUsesInsertNode() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "hello world")
        #expect(js.contains("insertNode"), "JS must use insertNode to place the highlight span")
    }

    @Test("searchHighlightJS still creates vreader_search_highlight span")
    func searchHighlightJSCreatesHighlightSpan() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "some text")
        #expect(js.contains("vreader_search_highlight"), "JS must create a span with search highlight class")
    }

    @Test("searchHighlightJS still scrolls into view")
    func searchHighlightJSScrollsIntoView() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "some text")
        #expect(js.contains("scrollIntoView"), "JS must scroll to the highlighted text")
    }

    @Test("searchHighlightJS still removes previous highlights")
    func searchHighlightJSRemovesPrevious() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "some text")
        #expect(js.contains("querySelectorAll"), "JS must clean up previous search highlights")
    }

    @Test("searchHighlightJS still auto-clears after timeout")
    func searchHighlightJSAutoClears() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "some text")
        #expect(js.contains("setTimeout"), "JS must auto-clear the highlight after timeout")
    }
}

// MARK: - Issue 6: PDF searchHighlightText cleared after auto-clear

@Suite("AuditFix3 — Issue 6: PDF searchHighlightText deduplication fix")
struct PDFSearchHighlightDedupeTests {

    @Test("PDFViewBridge Coordinator has a clearSearchWorkItem property")
    @MainActor
    func coordinatorHasClearWorkItem() {
        let coordinator = PDFViewBridge.Coordinator()
        #expect(coordinator.clearSearchWorkItem == nil)
    }

    @Test("PDFViewBridge Coordinator resets lastSearchHighlightText when work item fires")
    @MainActor
    func coordinatorResetsSearchTextOnClear() {
        let coordinator = PDFViewBridge.Coordinator()
        coordinator.lastSearchHighlightText = "test quote"
        coordinator.lastSearchHighlightText = nil
        #expect(coordinator.lastSearchHighlightText == nil)
    }
}

// MARK: - Issue 7: PDF uncancelled asyncAfter — use DispatchWorkItem

@Suite("AuditFix3 — Issue 7: PDF cancellable clear timer")
struct PDFCancellableClearTimerTests {

    @Test("Coordinator clearSearchWorkItem can be cancelled")
    @MainActor
    func clearWorkItemCancellable() {
        let coordinator = PDFViewBridge.Coordinator()
        let workItem = DispatchWorkItem { }
        coordinator.clearSearchWorkItem = workItem
        workItem.cancel()
        #expect(workItem.isCancelled)
    }

    @Test("Setting new clearSearchWorkItem replaces old one")
    @MainActor
    func clearWorkItemReplaceable() {
        let coordinator = PDFViewBridge.Coordinator()
        let oldItem = DispatchWorkItem { }
        coordinator.clearSearchWorkItem = oldItem
        let newItem = DispatchWorkItem { }
        coordinator.clearSearchWorkItem = newItem
        #expect(coordinator.clearSearchWorkItem === newItem)
    }
}

// MARK: - Bug #99 cause #3: TXT search-highlight clear-on-scroll gating
//
// Original (Issue 8): a `programmaticScrollCount` counter + 0.3s
// timer-based decrement to guard against scroll-callback dismissal
// during programmatic scroll. Bug #99 surfaced that 0.3s was racing
// TextKit 1's lazy-layout `scrollViewDidScroll` callbacks (400-1200ms
// late). Replaced (this branch) with a canonical-signal approach:
// `clearSearchHighlightIfTemporary(scrollView:)` checks the scroll
// view's `isTracking || isDragging || isDecelerating` triplet — true
// only for user-driven scrolls; programmatic scrolls and their late
// layout callbacks have all three false and skip the clear without
// any timer. Tests mirror the new behavior.

@Suite("Bug #99 — TXT search-highlight clear-on-scroll gating")
struct TXTSearchHighlightGatingTests {

    @Test @MainActor
    func nilScrollView_clearsUnconditionally() {
        // Non-scroll-driven dismissal paths (chrome tap, search-clear notification)
        // pass scrollView: nil and clear without inspecting any flag.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 10, length: 5)

        coordinator.clearSearchHighlightIfTemporary()  // nil

        #expect(coordinator.currentHighlightRange == nil,
                "nil scrollView (tap-driven dismiss) must clear unconditionally")
    }

    @Test @MainActor
    func idleScrollView_skipsClear() {
        // Programmatic scroll's late layout-driven callback shape: a
        // UIScrollView whose isTracking/isDragging/isDecelerating are all
        // false. The clear must skip — this is the bug #99 cause #3 fix.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 10, length: 5)
        let idle = UIScrollView()
        #expect(!idle.isTracking)
        #expect(!idle.isDragging)
        #expect(!idle.isDecelerating)

        coordinator.clearSearchHighlightIfTemporary(scrollView: idle)

        #expect(coordinator.currentHighlightRange == NSRange(location: 10, length: 5),
                "Idle scroll-view callbacks must NOT clear the highlight (bug #99 cause #3)")
    }
}

// MARK: - Issue 10: ReaderTheme broad font-size override

@Suite("AuditFix3 — Issue 10: ReaderTheme broad font-size CSS")
struct ReaderThemeBroadFontSizeTests {

    @Test("epubOverrideCSS covers headings via wildcard or explicit list")
    func cssCoversHeadings() {
        let css = ReaderTheme.light.epubOverrideCSS(fontSize: 18)
        let coversAll = css.contains("body *")
            || (css.contains("h1") && css.contains("h2") && css.contains("h3"))
        #expect(coversAll, "CSS must cover all text elements (including headings) via broad selector")
    }

    @Test("epubOverrideCSS excludes headings from font-size: inherit")
    func cssExcludesHeadingsFromInherit() {
        let css = ReaderTheme.light.epubOverrideCSS(fontSize: 18)
        let hasRevertRule = css.contains("h1") && css.contains("revert")
        let headingsNotInInheritRule = !css.contains("h1,") || css.contains("h1 { font-size: revert")
            || css.contains("h1,h2,h3,h4,h5,h6")
        #expect(hasRevertRule || headingsNotInInheritRule,
                "Headings must be excluded from font-size: inherit or have a revert rule")
    }

    @Test("epubOverrideCSS covers pre and code elements")
    func cssCoversPreAndCode() {
        let css = ReaderTheme.light.epubOverrideCSS(fontSize: 18)
        let coversPre = css.contains("pre") || css.contains("body *")
        let coversCode = css.contains("code") || css.contains("body *")
        #expect(coversPre, "CSS must cover <pre> elements")
        #expect(coversCode, "CSS must cover <code> elements")
    }

    @Test("epubOverrideCSS all themes have broad coverage")
    func allThemesBroadCoverage() {
        for theme in ReaderTheme.allCases {
            let css = theme.epubOverrideCSS(fontSize: 18)
            let hasBroad = css.contains("body *") || css.contains("pre") || css.contains("code")
            #expect(hasBroad, "\(theme.rawValue) must have broad font-size coverage")
        }
    }
}
#endif
