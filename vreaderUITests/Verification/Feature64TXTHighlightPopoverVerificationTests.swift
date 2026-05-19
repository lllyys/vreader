// Purpose: Feature #64 WI-6 — Gate-5a slice verification for the native TXT
// container's migration to the unified highlight-action popover.
//
// WI-6's behavioral change: a *tap* on an existing highlight in the TXT
// reader opens the unified highlight-action popover — NOT feature #55's
// read-only note callout, and NOT feature #53's long-press delete `UIMenu`.
// On the native TXT container `hostViewProvider` is `{ nil }`, so the popover
// resolves to its bottom-sheet form (`highlightPopoverSheet`).
//
// CU-free: drives the app entirely through XCUITest's accessibility layer,
// no computer-use. Creates a highlight via the existing long-press → Highlight
// selection flow (unchanged by WI-6), then taps it and asserts the unified
// popover sheet appears while the legacy `noteCallout` does not.
//
// @coordinates-with: TXTReaderContainerView.swift, HighlightActionCardView.swift,
//   HighlightPopoverModifier.swift

import XCTest

@MainActor
final class Feature64TXTHighlightPopoverVerificationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .positionTest, resetPreferences: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    private func txtReaderTextView() -> XCUIElement {
        app.textViews.matching(identifier: AccessibilityID.txtReaderContainer).firstMatch
    }

    /// Verifies: long-press → Highlight creates a highlight; tapping that
    /// highlight opens the unified highlight-action popover (bottom-sheet form
    /// on the native TXT container) — not the feature #55 note callout.
    func testTapOnHighlightOpensUnifiedPopover() {
        // 1. Open the Position Test Book (real TXT file, single-chapter mode).
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

        // 2. Long-press a word and tap Highlight — creates a persisted
        //    highlight (the feature #60 selection flow, unchanged by WI-6).
        let pressCoord = textView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        pressCoord.press(forDuration: 1.5)

        var highlightElement: XCUIElement = app.menuItems["Highlight"]
        if !highlightElement.waitForExistence(timeout: 4) {
            highlightElement = app.buttons["Highlight"]
        }
        guard highlightElement.waitForExistence(timeout: 4) else {
            XCTFail("Highlight action should appear in the selection menu after long-press")
            return
        }
        highlightElement.tap()

        // Give the highlight paint a moment to land before tapping it.
        let paintedPredicate = NSPredicate(format: "exists == true")
        let settle = XCTNSPredicateExpectation(predicate: paintedPredicate, object: textView)
        _ = XCTWaiter().wait(for: [settle], timeout: 2)

        // 3. Tap the highlighted word. WI-6: this posts `.readerHighlightTapped`,
        //    which the unified popover observes.
        let tapCoord = textView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        tapCoord.tap()

        // 4. The unified highlight-action popover must appear. On the native
        //    TXT container (`hostViewProvider == { nil }`) it resolves to the
        //    bottom-sheet form.
        let popoverSheet = app.descendants(matching: .any)
            .matching(identifier: "highlightPopoverSheet").firstMatch
        let popoverCard = app.descendants(matching: .any)
            .matching(identifier: "highlightPopoverCard").firstMatch
        let popoverAppeared = NSPredicate(format: "exists == true")
        let sheetExpect = XCTNSPredicateExpectation(predicate: popoverAppeared, object: popoverSheet)
        let cardExpect = XCTNSPredicateExpectation(predicate: popoverAppeared, object: popoverCard)
        let result = XCTWaiter().wait(for: [sheetExpect, cardExpect], timeout: 6, enforceOrder: false)
        // Either form satisfies the migration — the sheet is expected on TXT,
        // but accept the card too in case a future host-view wiring lands.
        XCTAssertTrue(
            result == .completed || popoverSheet.exists || popoverCard.exists,
            "Tapping a TXT highlight should open the unified highlight-action popover " +
            "(feature #64 WI-6). Neither `highlightPopoverSheet` nor `highlightPopoverCard` appeared."
        )

        // 5. The superseded feature #55 read-only note callout must NOT appear.
        let legacyCallout = app.descendants(matching: .any)
            .matching(identifier: "noteCallout").firstMatch
        XCTAssertFalse(
            legacyCallout.exists,
            "The feature #55 `noteCallout` must not appear — it is superseded by the " +
            "unified highlight-action popover (feature #64 WI-6)."
        )
    }
}
