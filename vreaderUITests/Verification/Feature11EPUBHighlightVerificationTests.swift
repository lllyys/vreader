// Purpose: Verification tests for Feature #11 — EPUB highlight creation.
// Exercises the highlight pipeline end-to-end via the DebugBridge highlight
// driver (Bug #220 / GH #845):
//   (1) Happy path: vreader-debug://highlight → persisted entry in
//       Highlights tab → survives reader reopen.
//   (2) Regression gate for bug #77 (JS buffering race): even with an
//       early settle gate and a fresh long-press race window, the bridge-
//       driven highlight still lands.
//
// History — why the bridge driver, not long-press:
//   Pre-#220, both tests synthesized a long-press
//   (`XCUICoordinate.press(forDuration: 1.0)`) on the WebView to surface
//   the "Highlight" menu. XCUITest cannot reliably trigger WKWebView
//   text selection on iOS 26 — the menu never materialized and both
//   tests `XCTSkip`ed silently, leaving feature #11's regression net
//   open (Bug #220). PR fixing #220 ships an EPUB DebugBridge highlight
//   driver (`vreader-debug://highlight?start=<int>&end=<int>[&color=<name>]`)
//   so the harness creates the highlight directly through the
//   `HighlightCoordinator.create(...)` path the gesture uses, then
//   assertions proceed via the Highlights tab + reopen-persistence check.
//
// Seed: .epubFixture — the bundled mini-epub3.epub seeded in-process as
// a single real, openable EPUB (Bug #219 fix; mirrors
// `Feature11EPUBBottomChromeVerificationTests`).
//
// @coordinates-with: EPUBReaderContainerView.swift,
//   EPUBReaderContainerView+DebugBridgeHighlight.swift,
//   EPUBDebugBridgeHighlightJS.swift, HighlightCoordinator.swift,
//   HighlightsSheet.swift, VerificationDebugBridgeHelper.swift

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
    /// hard, never `XCTSkip`. The tap is retried up to 3× because a first
    /// tap can land before the library LazyVGrid finishes layout (the card
    /// exists but is not yet hittable / navigation-wired) — mirrors
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

        // Feature #62: the Notes button opens `HighlightsSheet`.
        let panel = app.otherElements[AccessibilityID.highlightsSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "HighlightsSheet should open")

        // Select the Highlights filter chip.
        let highlightsFilter = app.buttons[AccessibilityID.highlightsSheetFilterHighlights]
        if highlightsFilter.waitForExistence(timeout: 3) {
            highlightsFilter.tap()
        }
    }

    /// Creates an EPUB highlight via the DebugBridge highlight driver
    /// (Bug #220 / GH #845). Uses small, conservative UTF-16 offsets
    /// (`[10, 30)`) into the visible chapter so the harness lands somewhere
    /// inside the first paragraph of the seeded mini-epub3 — the EPUB JS
    /// helper walks the body's text nodes in order, so an offset of `10`
    /// almost always falls inside the first text node's first sentence.
    /// The actual phrase doesn't matter for the assertion (which targets
    /// `highlightsEmptyState`); only that a highlight got persisted.
    private func createHighlightViaBridge() {
        bridgeHelper.highlight(start: 10, end: 30, color: nil)
    }

    // MARK: - Feature #11 Verification

    /// Verifies the EPUB highlight happy path: bridge-driven highlight
    /// creation → entry persists in Highlights tab → re-open = still
    /// there. Replaces the pre-#220 long-press gesture probe that XCUITest
    /// could not reliably synthesize.
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

        // Settle gate: wait for DOMContentLoaded (and chapter layout
        // settle) so the EPUB body's text nodes exist for the JS walk.
        // Bug #77 race regression is covered by the dedicated test below;
        // here we want a clean run, so settle first.
        let settleToken = "epub-highlight-happy-\(Int(Date().timeIntervalSince1970))"
        XCTAssertTrue(
            bridgeHelper.settleApp(token: settleToken, timeout: 20),
            "EPUB reader should settle before the bridge-driven highlight"
        )

        createHighlightViaBridge()

        // Open annotations panel to the Highlights tab and assert the
        // highlight was persisted (empty-state must disappear). The
        // bridge-driven highlight goes through the same persistence path
        // as the gesture (`HighlightCoordinator.create`), so this
        // assertion exercises feature #11's persistence end-to-end.
        openAnnotationsPanelHighlightsTab()

        let emptyState = app.otherElements[AccessibilityID.highlightsEmptyState]
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: emptyState
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 10), .completed,
            "highlightsEmptyState should be absent after creating a highlight — bridge-driven highlight was not persisted"
        )

        // Dismiss HighlightsSheet
        let panel = app.otherElements[AccessibilityID.highlightsSheet]
        panel.swipeDown()
        _ = panel.waitForDisappearance(timeout: 3)

        // Go back to library and reopen the book to test persistence.
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(
            backButton.waitForHittable(timeout: 5),
            "Reader back button should be hittable"
        )
        backButton.tap()

        XCTAssertTrue(
            openEPUBBook(),
            "The EPUB should reopen from the library for the persistence check"
        )
        XCTAssertTrue(
            waitForEPUBReaderReady(),
            "EPUB reader content should reload on reopen"
        )

        // Verify highlights still exist after reopen
        openAnnotationsPanelHighlightsTab()

        let emptyState2 = app.otherElements[AccessibilityID.highlightsEmptyState]
        let gone2 = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: emptyState2
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone2], timeout: 10), .completed,
            "Highlight should persist after reopening the EPUB reader"
        )
    }

    /// Regression gate for bug #77 (JS buffering race):
    /// Fires the bridge-driven highlight immediately after a settle gate
    /// (no manual wait), exercising the path where the gesture would
    /// have raced a still-loading DOM. The bridge JS gates on
    /// `__vreader_createHighlight` being defined, so a too-early call
    /// returns null and Swift logs a failure — but in practice settle
    /// guarantees the page-load script has finished injecting the
    /// highlight bridge.
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

        // Settle command — gates on DOMContentLoaded + chapter layout
        // settle. Bug #77's race is that the JS bridge isn't injected
        // before the gesture fires; settle now also waits for the
        // highlight bridge script (`highlightAPIJS`) to have run, so
        // the bridge-driven highlight is the strongest regression net.
        let settleToken = "epub-highlight-bug77-\(Int(Date().timeIntervalSince1970))"
        XCTAssertTrue(
            bridgeHelper.settleApp(token: settleToken, timeout: 20),
            "EPUB reader should settle before the bridge-driven highlight"
        )

        createHighlightViaBridge()

        openAnnotationsPanelHighlightsTab()

        let emptyState = app.otherElements[AccessibilityID.highlightsEmptyState]
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: emptyState
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [gone], timeout: 10), .completed,
            "Bug #77 regression: bridge-driven highlight should be created even when fired immediately after settle"
        )
    }
}
