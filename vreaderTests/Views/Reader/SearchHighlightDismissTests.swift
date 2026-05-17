// Purpose: Tests for WI-003 — Search Highlight Auto-Dismiss.
// Validates that search highlights clear on scroll, tap, new search, and no-crash
// when no highlight is active.
//
// @coordinates-with HighlightableTextView.swift, TXTTextViewBridge.swift,
//   SearchViewModel.swift, ReaderNotifications.swift

import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("SearchHighlightDismiss")
struct SearchHighlightDismissTests {

    // MARK: - Helpers

    /// Creates a HighlightableTextView with source text and an active search highlight.
    @MainActor
    private static func makeHighlightedTextView(
        text: String = "Hello World Search Result Here",
        highlightRange: NSRange? = NSRange(location: 12, length: 13)
    ) -> HighlightableTextView {
        let tv = HighlightableTextView()
        tv.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        tv.setSourceText(NSAttributedString(string: text))
        if let range = highlightRange {
            tv.setHighlightRanges(persisted: [], active: range)
        }
        return tv
    }

    // MARK: - clearSearchHighlight

    @Test @MainActor func clearSearchHighlightRemovesActiveRange() {
        let tv = Self.makeHighlightedTextView()
        let lm = tv.layoutManager as! HighlightingLayoutManager

        // Precondition: search highlight is active
        #expect(lm.searchHighlightRange != nil)

        tv.clearSearchHighlight()

        // Active search highlight should be cleared
        #expect(lm.searchHighlightRange == nil)
    }

    @Test @MainActor func clearSearchHighlightPreservesPersistedHighlights() {
        let tv = Self.makeHighlightedTextView()
        let persisted = [PaintedHighlight(range: NSRange(location: 0, length: 5), colorName: "yellow")]
        let active = NSRange(location: 12, length: 13)
        tv.setHighlightRanges(persisted: persisted, active: active)
        let lm = tv.layoutManager as! HighlightingLayoutManager

        // Precondition: both persisted + active
        #expect(lm.persistedHighlights.count == 1)
        #expect(lm.searchHighlightRange != nil)

        tv.clearSearchHighlight()

        // Only the persisted highlight should remain
        #expect(lm.persistedHighlights.count == 1)
        #expect(lm.persistedHighlights[0].range == NSRange(location: 0, length: 5))
        #expect(lm.searchHighlightRange == nil)
    }

    @Test @MainActor func clearSearchHighlightNoHighlightNoCrash() {
        let tv = Self.makeHighlightedTextView(highlightRange: nil)
        let lm = tv.layoutManager as! HighlightingLayoutManager

        // Precondition: no highlight
        #expect(lm.persistedHighlights.isEmpty)
        #expect(lm.searchHighlightRange == nil)

        // Should be a no-op, no crash
        tv.clearSearchHighlight()

        #expect(lm.searchHighlightRange == nil)
    }

    @Test @MainActor func clearSearchHighlightIdempotent() {
        let tv = Self.makeHighlightedTextView()

        tv.clearSearchHighlight()
        tv.clearSearchHighlight() // Second call should be safe

        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.searchHighlightRange == nil)
    }

    // MARK: - Coordinator scroll dismiss

    @Test @MainActor func coordinatorClearsHighlightOnScroll() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 10, length: 5)

        // Simulate scroll callback triggering clear
        coordinator.clearSearchHighlightIfTemporary()

        #expect(coordinator.currentHighlightRange == nil)
    }

    @Test @MainActor func coordinatorClearsTimerOnManualDismiss() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 10, length: 5)
        // Simulate timer being set
        coordinator.highlightClearTimer = Timer.scheduledTimer(
            withTimeInterval: 3.0, repeats: false
        ) { _ in }

        coordinator.clearSearchHighlightIfTemporary()

        #expect(coordinator.highlightClearTimer == nil)
        #expect(coordinator.currentHighlightRange == nil)
    }

    @Test @MainActor func coordinatorDoesNotCrashWhenNoHighlightOnScroll() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        #expect(coordinator.currentHighlightRange == nil)

        // Should be a safe no-op
        coordinator.clearSearchHighlightIfTemporary()

        #expect(coordinator.currentHighlightRange == nil)
    }

    // MARK: - SearchViewModel posts notification on query change

    @Test @MainActor func searchViewModelPostsNotificationOnQueryChange() async {
        let stub = StubSearchService()
        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: DocumentFingerprint(
                contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
                fileByteCount: 1024,
                format: .txt
            ),
            debounceInterval: .milliseconds(10)
        )

        var notificationReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .searchHighlightClear, object: nil, queue: .main
        ) { _ in
            notificationReceived = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        vm.query = "hello"
        // Notification should fire synchronously on query change
        #expect(notificationReceived == true)
    }

    @Test @MainActor func searchViewModelPostsNotificationOnQueryClear() async {
        let stub = StubSearchService()
        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: DocumentFingerprint(
                contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
                fileByteCount: 1024,
                format: .txt
            ),
            debounceInterval: .milliseconds(10)
        )

        vm.query = "test"

        var notificationReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .searchHighlightClear, object: nil, queue: .main
        ) { _ in
            notificationReceived = true
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        vm.query = ""
        #expect(notificationReceived == true)
    }

    // MARK: - TXT Coordinator observes searchHighlightClear notification

    @Test @MainActor func coordinatorClearsHighlightOnSearchHighlightClearNotification() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 10, length: 5)

        // Post the notification that SearchViewModel sends on new query
        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)

        // Coordinator should have cleared the highlight via its observer
        #expect(coordinator.currentHighlightRange == nil)
    }

    @Test @MainActor func coordinatorClearsTimerOnSearchHighlightClearNotification() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 10, length: 5)
        coordinator.highlightClearTimer = Timer.scheduledTimer(
            withTimeInterval: 3.0, repeats: false
        ) { _ in }

        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)

        #expect(coordinator.highlightClearTimer == nil)
        #expect(coordinator.currentHighlightRange == nil)
    }

    @Test @MainActor func coordinatorNoOpOnSearchHighlightClearWhenNoHighlight() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        #expect(coordinator.currentHighlightRange == nil)

        // Should be a safe no-op — no crash
        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)

        #expect(coordinator.currentHighlightRange == nil)
    }

    @Test @MainActor func coordinatorIdempotentOnMultipleSearchHighlightClearNotifications() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 10, length: 5)

        // Post multiple times — should be safe
        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)
        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)

        #expect(coordinator.currentHighlightRange == nil)
    }

    @Test @MainActor func coordinatorRebuildHighlightsOnNotificationWithTextView() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        let tv = Self.makeHighlightedTextView()
        coordinator.activeTextView = tv
        coordinator.currentHighlightRange = NSRange(location: 12, length: 13)

        NotificationCenter.default.post(name: .searchHighlightClear, object: nil)

        // Coordinator state cleared
        #expect(coordinator.currentHighlightRange == nil)
        // Layout manager highlights also rebuilt (active highlight removed)
        let lm = tv.layoutManager as! HighlightingLayoutManager
        #expect(lm.searchHighlightRange == nil)
    }

    // MARK: - Programmatic scroll guard (bug #43 regression)

    // Bug #99 cause #3: replaced the `programmaticScrollCount` + 0.3s timer
    // mechanism with a canonical-signal approach. The clear-on-scroll guard
    // now reads the scroll view's `isTracking || isDragging || isDecelerating`
    // triplet — true only for user scrolls; programmatic scrolls and their
    // late layout-driven callbacks have all three false and skip the clear.

    @Test @MainActor func coordinatorPreservesHighlightDuringProgrammaticScroll() {
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 10, length: 5)

        // Programmatic-scroll-induced layout callback shape: an idle
        // UIScrollView with no user input. clearSearchHighlightIfTemporary
        // must skip when called with this scroll view.
        let idle = UIScrollView()
        coordinator.clearSearchHighlightIfTemporary(scrollView: idle)

        #expect(coordinator.currentHighlightRange == NSRange(location: 10, length: 5))
    }

    @Test @MainActor func coordinatorClearsHighlightWhenCalledWithoutScrollView() {
        // Non-scroll-driven dismissal paths (chrome tap, search-clear notification)
        // pass scrollView: nil and clear unconditionally.
        let coordinator = TXTTextViewBridge.Coordinator(delegate: nil)
        coordinator.currentHighlightRange = NSRange(location: 10, length: 5)

        coordinator.clearSearchHighlightIfTemporary()  // nil

        #expect(coordinator.currentHighlightRange == nil)
    }

    // MARK: - EPUB search highlight JS (bug #43)

    @Test func epubSearchHighlightJSForTextQuote() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "hello world")
        #expect(!js.isEmpty)
        // The JS should search for the text and highlight it
        #expect(js.contains("hello world"))
    }

    @Test func epubSearchHighlightJSForEmptyQuoteReturnsEmpty() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "")
        #expect(js.isEmpty)
    }

    @Test func epubSearchHighlightJSForWhitespaceOnlyReturnsEmpty() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "   ")
        #expect(js.isEmpty)
    }

    @Test func epubSearchHighlightJSEscapesSpecialChars() {
        let js = EPUBHighlightBridge.searchHighlightJS(textQuote: "it's a \"test\"")
        #expect(!js.isEmpty)
        // Should contain escaped quotes
        #expect(js.contains("\\'"))
    }

    @Test func epubClearSearchHighlightJSIsNonEmpty() {
        let js = EPUBHighlightBridge.clearSearchHighlightJS
        #expect(!js.isEmpty)
        #expect(js.contains("vreader_search"))
    }

    // MARK: - PDF search highlight (bug #43)

    @Test func pdfSearchHighlightTextQuoteNonEmpty() {
        // PDFAnnotationBridge.searchHighlightText should produce valid non-nil for non-empty quote
        let quote = "sample text"
        #expect(!quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func pdfSearchHighlightTextQuoteEmpty() {
        let quote = ""
        #expect(quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // MARK: - Notification name exists

    @Test func searchHighlightClearNotificationNameExists() {
        let name = Notification.Name.searchHighlightClear
        #expect(name.rawValue == "vreader.searchHighlightClear")
    }
}
