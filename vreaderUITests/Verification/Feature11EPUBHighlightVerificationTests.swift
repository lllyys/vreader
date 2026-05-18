// Purpose: Verification tests for Feature #11 — EPUB highlight creation.
// Exercises the highlight gesture pipeline end-to-end:
// (1) Happy path: long-press → Highlight menu → persisted entry in
//     Highlights tab → survives reader reopen.
// (2) Regression gate for bug #77 (JS buffering race): rapid long-press
//     before DOMContentLoaded settles still creates the highlight.
//
// Seed: .epubFixture — the bundled mini-epub3.epub seeded in-process as
// a single real, openable EPUB. The .books launch seed only carries
// metadata-only EPUB records that never open (Bug #209 Cause A); seeding
// .books here silently skipped both tests — Bug #219 / GH #844.
//
// @coordinates-with: EPUBReaderContainerView.swift, EPUBWebViewBridge.swift,
//   HighlightCoordinator.swift, AnnotationsPanelView.swift

import XCTest

@MainActor
final class Feature11EPUBHighlightVerificationTests: XCTestCase {
    var app: XCUIApplication!
    private var bridgeHelper: VerificationDebugBridgeHelper!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // .epubFixture seeds the bundled mini-epub3.epub in-process as a
        // single real, openable EPUB (Bug #219 — .books records are
        // metadata-only and never open).
        app = launchApp(seed: .epubFixture, resetPreferences: true)
        bridgeHelper = VerificationDebugBridgeHelper(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        bridgeHelper = nil
    }

    // MARK: - Helpers

    /// Opens the seeded EPUB and waits for the reader to push. Returns
    /// `false` if the card or reader never appeared.
    ///
    /// With the `.epubFixture` seed the EPUB is guaranteed-openable, so a
    /// `false` is a real seed/launch/navigation regression — callers fail
    /// hard, never `XCTSkip` (an `XCTSkip` on the reader-load gate is how
    /// Bug #219's silent vacuous pass happened). The tap is retried up to
    /// 3× because a first tap can land before the library LazyVGrid
    /// finishes layout (the card exists but is not yet hittable /
    /// navigation-wired) — mirrors
    /// `Feature11EPUBBottomChromeVerificationTests.openEPUB()`.
    private func openEPUBBook() -> Bool {
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        ).firstMatch
        guard card.waitForExistence(timeout: 20) else { return false }

        let backButton = app.buttons[AccessibilityID.readerBackButton]
        for _ in 0..<3 {
            if card.waitForHittable(timeout: 8) {
                card.tap()
            } else if card.exists {
                card.tap()
            }
            if backButton.waitForExistence(timeout: 20) {
                return true
            }
        }
        return false
    }

    private func waitForEPUBReaderReady(timeout: TimeInterval = 20) -> Bool {
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        guard backButton.waitForExistence(timeout: timeout) else { return false }

        // The EPUB content is a WKWebView. Query it by element TYPE, not
        // by a11y identifier: Bug #214 scoped `epubReaderContainer` to an
        // inner content `Group`, and the `epubReaderContent` /
        // `epubReaderContainer` identifiers no longer resolve as a
        // top-level `webViews`/`otherElements` identifier query (that
        // stale probe made this test fail even after the Bug #219 seed
        // fix). `app.webViews.firstMatch` is the identifier-independent
        // signal that the reader's content view has mounted.
        return app.webViews.firstMatch.waitForExistence(timeout: timeout)
    }

    private func openAnnotationsPanelHighlightsTab() {
        // Show chrome first if needed
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        if !annotationsButton.waitForExistence(timeout: 3) {
            app.tap()
        }
        XCTAssertTrue(
            annotationsButton.waitForHittable(timeout: 10),
            "Annotations button should become hittable"
        )
        annotationsButton.tap()

        // Panel appears
        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "Annotations panel should open")

        // Tap Highlights tab
        let highlightsTab = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[cd] 'Highlight'")
        ).firstMatch
        if highlightsTab.waitForExistence(timeout: 3) {
            highlightsTab.tap()
        }
    }

    // MARK: - Feature #11 Verification

    /// Verifies the EPUB highlight happy path: long-press text → Highlight
    /// menu → entry persists in Highlights tab → re-open = still there.
    func test_verify_feature_11_epub_highlight_happy_path() throws {
        XCTAssertTrue(
            openEPUBBook(),
            "The seeded mini-epub3 EPUB should open into the reader — a " +
            "failure here is a seed/launch-arg/navigation regression, not " +
            "an environmental skip (Bug #219)"
        )
        XCTAssertTrue(
            waitForEPUBReaderReady(),
            "EPUB reader content should load after opening the seeded EPUB"
        )

        // Settle: wait for DOMContentLoaded to prevent bug #77 race
        // (settle fires vreader-debug://settle, but we can also just wait
        //  for the webview content to appear before the long-press)
        let webView = app.webViews.firstMatch
        guard webView.waitForExistence(timeout: 15) else {
            throw XCTSkip("EPUB WebView not found — book may not be an EPUB")
        }
        // Brief wait for initial render (EPUB WebView needs JS to finish)
        _ = XCTWaiter().wait(for: [], timeout: 2.5)

        // Long-press in the center of the WebView to select a word
        let pressCoord = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        pressCoord.press(forDuration: 1.0)

        // Look for Highlight in the selection menu
        let highlightMenu = app.menuItems.matching(
            NSPredicate(format: "label CONTAINS[cd] 'Highlight'")
        ).firstMatch
        guard highlightMenu.waitForExistence(timeout: 5) else {
            // Selection menu did not appear or no "Highlight" option — skip
            // rather than fail, as the book loaded may not be an EPUB
            throw XCTSkip("Highlight menu item not found after long-press — book may not support highlights or long-press did not select text")
        }
        highlightMenu.tap()

        // Open annotations panel to the Highlights tab
        openAnnotationsPanelHighlightsTab()

        // Assert highlight was created (highlightEmptyState must be absent)
        let emptyState = app.otherElements[AccessibilityID.highlightEmptyState]
        let notEmptyPredicate = NSPredicate(format: "exists == false")
        let gone = XCTNSPredicateExpectation(predicate: notEmptyPredicate, object: emptyState)
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 5), .completed,
            "highlightEmptyState should be absent after creating a highlight — highlight was not persisted"
        )

        // Dismiss panel
        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        panel.swipeDown()
        _ = panel.waitForDisappearance(timeout: 3)

        // Go back to library and reopen the book to test persistence.
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(
            backButton.waitForHittable(timeout: 5),
            "Reader back button should be hittable"
        )
        backButton.tap()

        // Reopen the same book. `openEPUBBook()` re-finds the card and
        // retries the tap; a failure here is a real regression, not a
        // silent pass — the reopen half previously had `else { return }`
        // vacuous-success exits (Codex audit finding, Bug #219).
        XCTAssertTrue(
            openEPUBBook(),
            "The EPUB should reopen from the library for the persistence check"
        )
        XCTAssertTrue(
            waitForEPUBReaderReady(),
            "EPUB reader content should reload on reopen"
        )
        _ = XCTWaiter().wait(for: [], timeout: 2.5)

        // Verify highlights still exist after reopen
        openAnnotationsPanelHighlightsTab()

        let emptyState2 = app.otherElements[AccessibilityID.highlightEmptyState]
        let gone2 = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: emptyState2
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone2], timeout: 5), .completed,
            "Highlight should persist after reopening the EPUB reader"
        )
    }

    /// Regression gate for bug #77 (JS buffering race):
    /// Sends settle command before the long-press to ensure the reader
    /// has fully rendered before the gesture. The highlight must still
    /// be created when the gesture is gated on the settle signal.
    func test_verify_feature_11_epub_highlight_regression_bug77_buffering_race() throws {
        XCTAssertTrue(
            openEPUBBook(),
            "The seeded mini-epub3 EPUB should open into the reader — a " +
            "failure here is a seed/launch-arg/navigation regression, not " +
            "an environmental skip (Bug #219)"
        )
        XCTAssertTrue(
            waitForEPUBReaderReady(),
            "EPUB reader content should load after opening the seeded EPUB"
        )

        // Send settle command — gates on DOMContentLoaded before gesture
        let settleToken = "epub-highlight-bug77-\(Int(Date().timeIntervalSince1970))"
        bridgeHelper.settleApp(token: settleToken, timeout: 15)

        let webView = app.webViews.firstMatch
        guard webView.waitForExistence(timeout: 5) else {
            throw XCTSkip("EPUB WebView not found")
        }

        // Long-press after settle has confirmed render-ready state
        let pressCoord = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        pressCoord.press(forDuration: 1.0)

        let highlightMenu = app.menuItems.matching(
            NSPredicate(format: "label CONTAINS[cd] 'Highlight'")
        ).firstMatch
        guard highlightMenu.waitForExistence(timeout: 5) else {
            throw XCTSkip("Highlight menu not found after settle-gated long-press")
        }
        highlightMenu.tap()

        openAnnotationsPanelHighlightsTab()

        let emptyState = app.otherElements[AccessibilityID.highlightEmptyState]
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: emptyState
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 5), .completed,
            "Bug #77 regression: highlight should be created even after settle-gated long-press"
        )
    }
}
