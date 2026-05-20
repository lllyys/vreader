// Purpose: Feature #64 WI-6 — Gate-5a slice verification for the native TXT
// container's migration to the unified highlight-action popover.
//
// WI-6's behavioral change: a *tap* on an existing highlight in the TXT
// reader opens the unified highlight-action popover — NOT feature #55's
// read-only note callout, and NOT feature #53's long-press delete `UIMenu`.
// On the native TXT container `hostViewProvider` is `{ nil }`, so the popover
// resolves to its bottom-sheet form (`highlightPopoverSheet`).
//
// CU-free: drives the app entirely through XCUITest's accessibility layer
// plus the `vreader-debug://highlight?start=<int>&end=<int>[&color=<name>]`
// DebugBridge command (Bug #237 / GH #986). The legacy long-press →
// "Highlight" menu path is unreliable on iOS 26 (Bug #240) — XCUITest
// cannot synthesize a `UITextView` selection menu tap, which is exactly
// the harness defect that Bug #237's bridge driver fixed. We create the
// highlight CU-free via the bridge, then tap the rendered highlight and
// assert the unified popover sheet appears while the legacy `noteCallout`
// does not.
//
// Bug #240b — DebugBridge URL channel may be unreachable from the
// XCUITest runner: see `Feature11EPUBHighlightVerificationTests` header
// for the full investigation. We probe via `bridgeHelper.settleApp` and
// XCTSkip with a reason that names both the common cause (sandboxed
// runner can't reach CoreSimulatorService) and the alternative
// possibilities (bridge / settle / container-path regression). The
// verify-cron HOST driver covers the bridge pipeline end-to-end.
//
// @coordinates-with: TXTReaderContainerView.swift, HighlightActionCardView.swift,
//   HighlightPopoverModifier.swift, VerificationDebugBridgeHelper.swift

import XCTest

@MainActor
final class Feature64TXTHighlightPopoverVerificationTests: XCTestCase {
    var app: XCUIApplication!
    private var bridgeHelper: VerificationDebugBridgeHelper!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .positionTest, resetPreferences: true)
        bridgeHelper = VerificationDebugBridgeHelper(app: app)
    }

    override func tearDownWithError() throws {
        app = nil
        bridgeHelper = nil
    }

    private func txtReaderTextView() -> XCUIElement {
        app.textViews.matching(identifier: AccessibilityID.txtReaderContainer).firstMatch
    }

    /// Probes whether the DebugBridge URL channel is reachable from this
    /// XCUITest runner. Returns `true` when a settle URL produced its
    /// expected sentinel within a short window. Bug #240: in CI / cron
    /// environments the runner is sandboxed and cannot reach the
    /// CoreSimulator XPC service, so `xcrun simctl openurl` exits
    /// non-zero and the URL never reaches the app.
    private func bridgeReachable() -> Bool {
        let probe = "txt-bridge-probe-\(Int(Date().timeIntervalSince1970))"
        return bridgeHelper.settleApp(token: probe, timeout: 5)
    }

    /// Verifies: a bridge-driven highlight is created in the TXT reader,
    /// then a tap on that rendered highlight opens the unified
    /// highlight-action popover (bottom-sheet form on the native TXT
    /// container) — not the legacy feature #55 note callout.
    func testTapOnHighlightOpensUnifiedPopover() throws {
        // 1. Open the Position Test Book (5000-char TXT file with a header
        //    followed by 100 numbered paragraphs — see `seedPositionTest`
        //    in `TestSeeder.swift`).
        tapBook(titled: "Position Test Book", in: app)

        let textView = txtReaderTextView()
        XCTAssertTrue(
            textView.waitForExistence(timeout: 15),
            "TXT reader text view should appear after opening Position Test Book"
        )

        let loading = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.txtReaderLoading).firstMatch
        if loading.exists {
            XCTAssertTrue(
                loading.waitForDisappearance(timeout: 10),
                "Loading indicator should disappear once content loads"
            )
        }

        let readyPredicate = NSPredicate(
            format: "value CONTAINS 'restoredOffset:' AND NOT value CONTAINS 'restoredOffset:none'"
        )
        let readyExpect = XCTNSPredicateExpectation(predicate: readyPredicate, object: textView)
        XCTAssertEqual(
            XCTWaiter().wait(for: [readyExpect], timeout: 10), .completed,
            "Text view should have a real restoredOffset once content is ready"
        )

        // 2. Bug #240: probe the DebugBridge before relying on it. A `false`
        //    means the bridge probe failed — most commonly the XCUITest
        //    runner is sandboxed and `xcrun simctl` cannot reach
        //    CoreSimulatorService, but it could also indicate a real
        //    bridge / settle / container-path regression. Skip with a
        //    reason that names both. TXT reader readiness gate has
        //    already run unconditionally above; the tap-on-highlight
        //    popover behavior is exercised end-to-end by the verify-cron
        //    HOST driver (outside the runner sandbox).
        try XCTSkipUnless(
            bridgeReachable(),
            "Bug #240: DebugBridge probe failed (most commonly: sandboxed " +
            "XCUITest runner cannot reach CoreSimulatorService — NSPOSIX 61 " +
            "'Connection refused'; could also indicate a real bridge or " +
            "settle-handler regression). TXT reader readiness verified; " +
            "tap-on-highlight popover behavior is exercised by the " +
            "verify-cron host driver — see dev-docs/verification/ for " +
            "evidence files."
        )

        // 3. Create a highlight CU-free via the DebugBridge highlight driver
        //    (Bug #237 / GH #986). The range spans paragraphs 1-10
        //    (UTF-16 offsets [40, 1500)) of the seeded text, which on the
        //    iPhone 17 Pro Simulator at the default 18pt body font renders
        //    inside the visible viewport from ~dy 0.05 down to ~dy 0.4 —
        //    so a single tap at `dy: 0.20` is guaranteed to land on
        //    painted highlight pixels regardless of font / scaling drift.
        //    The bridge call goes through the same
        //    `HighlightCoordinator.create(...)` path the gesture would
        //    have used, so the rendered highlight is byte-identical to a
        //    gesture-created one (`canonicalHash` matches; the popover
        //    observer doesn't care which entry path produced it).
        let settleToken = "txt-highlight-popover-\(Int(Date().timeIntervalSince1970))"
        XCTAssertTrue(
            bridgeHelper.settleApp(token: settleToken, timeout: 20),
            "TXT reader should settle before the bridge-driven highlight"
        )
        bridgeHelper.highlight(start: 40, end: 1500, color: nil)

        // Give the highlight paint a moment to land before tapping it.
        // The bridge fire-and-forget URL returns immediately; the
        // `HighlightCoordinator.create(...)` insert posts on the
        // PersistenceActor and the TXT renderer's
        // `.readerHighlightCreated` observer triggers the repaint.
        let paintToken = "txt-highlight-popover-paint-\(Int(Date().timeIntervalSince1970))"
        XCTAssertTrue(
            bridgeHelper.settleApp(token: paintToken, timeout: 20),
            "TXT reader should settle after the bridge-driven highlight " +
            "so the highlight paint has rendered before we tap it"
        )

        // 4. Tap the highlighted region. WI-6: this posts
        //    `.readerHighlightTapped`, which the unified popover observes.
        //    `dy: 0.20` is comfortably inside the [40, 1500) highlight's
        //    rendered band (paragraphs 1-10 of the seeded text).
        let tapCoord = textView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.20))
        tapCoord.tap()

        // 5. The unified highlight-action popover must appear in its
        //    BOTTOM-SHEET form. On the native TXT container,
        //    `hostViewProvider == { nil }` is the stated contract — the
        //    popover MUST resolve to `highlightPopoverSheet`. Accepting
        //    the card form here (an alternative SwiftUI-anchored
        //    popover presented when a host view IS available) would
        //    silently mask a TXT-specific presentation regression where
        //    the host-view-provider plumbing was wired up incorrectly.
        let popoverSheet = app.descendants(matching: .any)
            .matching(identifier: "highlightPopoverSheet").firstMatch
        let popoverAppeared = NSPredicate(format: "exists == true")
        let sheetExpect = XCTNSPredicateExpectation(predicate: popoverAppeared, object: popoverSheet)
        let result = XCTWaiter().wait(for: [sheetExpect], timeout: 6)
        XCTAssertTrue(
            result == .completed || popoverSheet.exists,
            "Tapping a TXT highlight should open the unified highlight-action " +
            "popover's bottom-sheet form (`highlightPopoverSheet`) — native TXT " +
            "`hostViewProvider == { nil }` mandates the sheet resolution " +
            "(feature #64 WI-6)."
        )

        // 6. The superseded feature #55 read-only note callout must NOT appear.
        let legacyCallout = app.descendants(matching: .any)
            .matching(identifier: "noteCallout").firstMatch
        XCTAssertFalse(
            legacyCallout.exists,
            "The feature #55 `noteCallout` must not appear — it is superseded by the " +
            "unified highlight-action popover (feature #64 WI-6)."
        )
    }
}
