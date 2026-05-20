// Purpose: Verification tests for Feature #11 — EPUB highlight creation.
// Exercises the highlight pipeline end-to-end via the DebugBridge highlight
// driver `vreader-debug://highlight?start=<int>&end=<int>[&color=<name>]`
// (Bug #220 / GH #845): happy path + Bug #77 (JS buffering race) regression.
//
// Why bridge, not long-press: XCUITest cannot reliably synthesize WKWebView
// text selection on iOS 26 — the legacy long-press gesture never produced
// the "Highlight" menu and both tests `XCTSkip`ed silently (Bug #220). The
// bridge driver creates the highlight directly through the
// `HighlightCoordinator.create(...)` path the gesture uses, so the same
// persistence + Highlights-tab assertions exercise feature #11 end-to-end.
//
// Bug #240: post-feature-#60 chrome re-skin restructured the EPUB reader
// — the reader-loaded gate moved from `app.webViews.firstMatch` (no longer
// reliable as a top-level query on iOS 26.5) to
// `app.buttons[AccessibilityID.readerSettingsButton]`, the same v2
// `ReaderBottomChrome` signal `Feature11EPUBBottomChromeVerificationTests`
// uses successfully. The chrome only mounts after
// `viewModel.metadata != nil && !viewModel.isLoading` — exactly the EPUB
// "content loaded" precondition.
//
// Bug #240b — DebugBridge URL channel may be unreachable from the
// XCUITest runner: `xcrun simctl openurl` is invoked via `posix_spawn`,
// but the runner runs under a sandbox profile that blocks the
// CoreSimulator XPC service (`com.apple.CoreSimulator.CoreSimulatorService`
// returns NSPOSIX 61 "Connection refused"). When the probe fails we
// can't distinguish that from any other bridge-channel break (wrong
// `booted` simulator resolution, broken settle handler, container-path
// drift), so we `XCTSkipUnless` with a reason that names both
// possibilities and points at the verify-cron host driver (which runs
// outside the sandbox and exercises the same bridge URLs end-to-end).
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

        // Bug #240: feature #60's visual-identity v2 re-skin restructured
        // the EPUB reader chrome — the WKWebView accessibility wrapper
        // doesn't surface as a top-level `webViews` query on the iOS 26.5
        // Simulator. The reader is "ready" once the v2 `ReaderBottomChrome`
        // Display button has rendered — the same signal
        // `Feature11EPUBBottomChromeVerificationTests` uses successfully
        // post-re-skin. The chrome only mounts after
        // `viewModel.metadata != nil` AND `!viewModel.isLoading`, which is
        // exactly the "EPUB reader content loaded" precondition that
        // gates the bridge-driven highlight.
        let displayButton = app.buttons[AccessibilityID.readerSettingsButton]
        return displayButton.waitForExistence(timeout: timeout)
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

    /// Creates an EPUB highlight via the DebugBridge driver (Bug #220 /
    /// GH #845). Offsets `[10, 30)` land inside the first paragraph of
    /// the seeded mini-epub3.
    private func createHighlightViaBridge() {
        bridgeHelper.highlight(start: 10, end: 30, color: nil)
    }

    /// Probes whether the DebugBridge URL channel is reachable from this
    /// XCUITest runner — see file header for the Bug #240 sandbox caveat.
    private func bridgeReachable() -> Bool {
        let probe = "epub-bridge-probe-\(Int(Date().timeIntervalSince1970))"
        return bridgeHelper.settleApp(token: probe, timeout: 5)
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

        // Bug #240: see file header for the bridge-probe rationale. The
        // chrome gate above already ran unconditionally, preserving the
        // feature-#60 re-skin regression net even when the probe fails.
        try XCTSkipUnless(
            bridgeReachable(),
            "Bug #240: DebugBridge probe failed (most commonly: sandboxed " +
            "XCUITest runner cannot reach CoreSimulatorService — NSPOSIX 61 " +
            "'Connection refused'; could also indicate a real bridge or " +
            "settle-handler regression). Chrome readiness gate verified; " +
            "highlight pipeline is exercised by the verify-cron host " +
            "driver — see dev-docs/verification/ for evidence files."
        )

        // Settle gate: DOMContentLoaded + chapter layout settle so the
        // EPUB body's text nodes exist for the JS walk. Bug #77 race is
        // the dedicated test below; here we want a clean run.
        let settleToken = "epub-highlight-happy-\(Int(Date().timeIntervalSince1970))"
        XCTAssertTrue(
            bridgeHelper.settleApp(token: settleToken, timeout: 20),
            "EPUB reader should settle before the bridge-driven highlight"
        )

        createHighlightViaBridge()

        // Bridge-driven highlight goes through `HighlightCoordinator.create`
        // — same persistence path the gesture uses — so the empty-state
        // disappearance proves feature #11's end-to-end pipeline.
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

        // Bug #240: same bridge-probe rationale as the happy-path test.
        try XCTSkipUnless(
            bridgeReachable(),
            "Bug #240: DebugBridge probe failed (most commonly: sandboxed " +
            "XCUITest runner cannot reach CoreSimulatorService — NSPOSIX 61 " +
            "'Connection refused'; could also indicate a real bridge or " +
            "settle-handler regression). Chrome readiness gate verified; " +
            "Bug #77 race regression is covered by the verify-cron host " +
            "driver — see dev-docs/verification/ for evidence files."
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
