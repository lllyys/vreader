// Purpose: Device verification for Bug #160 — TXT highlight gesture path end-to-end.
// Verifies that long-press → Highlight menu → tap creates a persisted highlight
// in the TXT reader (non-chapter mode via Position Test Book).
//
// Uses --seed-position-test (real TXT file) to exercise the live reader path.
// Chapter-mode coverage is provided by unit tests:
//   TXTReaderContainerHighlightCoordinatorWiringTests (wiring)
//   TXTChapterHighlightCreationTests (locator translation)
//
// @coordinates-with: TXTReaderContainerView.swift, TXTBridgeShared.swift,
//   HighlightCoordinator.swift, HighlightListView.swift

import XCTest

@MainActor
final class TXTHighlightGestureVerificationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // reset-preferences ensures no stale highlights from a prior run
        app = launchApp(seed: .positionTest, resetPreferences: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Finds the UITextView that wraps the TXT reader content.
    /// Note: `.accessibilityIdentifier("txtReaderContent")` is flattened in iOS 26
    /// SwiftUI — the outer container identifier propagates to the UITextView.
    private func txtReaderTextView() -> XCUIElement {
        app.textViews.matching(identifier: AccessibilityID.txtReaderContainer).firstMatch
    }

    // MARK: - Bug #160 Verification

    /// Verifies that the TXT highlight gesture pipeline creates a persisted
    /// highlight: long-press a word → tap Highlight → Highlights tab has an entry.
    ///
    /// Pre-fix: menu dismissed cleanly but no DB row was written (HighlightCoordinator
    /// was never instantiated in TXTReaderContainerView's .task block). Highlight tab
    /// stayed empty.
    ///
    /// Post-fix: HighlightCoordinator + TextHighlightRenderer are wired in .task,
    /// and locatorFactory uses makeLocatorForTXT for correct global/chapter-local offsets.
    func testHighlightGestureCreatesPersistedEntry() {
        // 1. Open Position Test Book (real TXT file, single-chapter mode)
        tapBook(titled: "Position Test Book", in: app)

        // 2. Wait for the TXT reader text view to load
        let textView = txtReaderTextView()
        XCTAssertTrue(
            textView.waitForExistence(timeout: 15),
            "TXT reader text view should appear after opening Position Test Book"
        )

        // 3. Wait for loading to complete — the loading spinner must disappear
        //    and the container value must carry a real restoredOffset before pressing.
        let loading = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.txtReaderLoading).firstMatch
        if loading.exists {
            XCTAssertTrue(
                loading.waitForDisappearance(timeout: 10),
                "Loading indicator should disappear once content loads"
            )
        }

        // Confirm content is ready: container value shows a numeric restoredOffset.
        let readyPredicate = NSPredicate(format: "value CONTAINS 'restoredOffset:' AND NOT value CONTAINS 'restoredOffset:none'")
        let readyExpect = XCTNSPredicateExpectation(predicate: readyPredicate, object: textView)
        let readyResult = XCTWaiter().wait(for: [readyExpect], timeout: 10)
        XCTAssertEqual(readyResult, .completed, "Text view should have a real restoredOffset once content is ready")

        // 4. Long-press at a coordinate within the upper third of the text area
        //    to select a word in the visible text ("Paragraph 1: This is...").
        //    Using normalizedOffset (0.5, 0.25) avoids the chrome overlay at top/bottom.
        let pressCoord = textView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        pressCoord.press(forDuration: 1.5)

        // 5. Look for the Highlight action in the edit menu.
        // UIEditMenuInteraction items appear as menuItems (XCUIElementTypeMenuItem) in iOS 16+.
        // Fall back to buttons if menuItems isn't found (iOS version differences).
        var highlightElement: XCUIElement = app.menuItems["Highlight"]
        if !highlightElement.waitForExistence(timeout: 4) {
            highlightElement = app.buttons["Highlight"]
        }

        guard highlightElement.waitForExistence(timeout: 4) else {
            XCTFail(
                "Highlight action should appear in context menu after long-press. " +
                "If missing, text was not selected or the edit menu did not present."
            )
            return
        }

        // 6. Tap Highlight — posts .readerHighlightRequested, which HighlightCoordinator
        //    handles, creates a Locator, and calls PersistenceActor.addHighlight.
        highlightElement.tap()

        // 7. Open the Annotations panel.
        //    A tap on the TXT text view TOGGLES chrome (postContentTappedNotification).
        //    Only tap if the chrome is currently hidden (annotations button absent from
        //    the view hierarchy). Tapping when chrome is already visible would hide it.
        // Feature #62: the Notes bottom-chrome button opens `HighlightsSheet`.
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        if !annotationsButton.waitForExistence(timeout: 2) {
            // Chrome was hidden — one tap reveals it.
            txtReaderTextView().tap()
        }
        XCTAssertTrue(
            annotationsButton.waitForHittable(timeout: 10),
            "Notes button should be hittable (chrome visible)"
        )
        annotationsButton.tap()

        let panel = app.otherElements[AccessibilityID.highlightsSheet]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "HighlightsSheet should appear"
        )

        // 8. Select the Highlights filter chip.
        let highlightsFilter = app.buttons[AccessibilityID.highlightsSheetFilterHighlights]
        XCTAssertTrue(
            highlightsFilter.waitForExistence(timeout: 3),
            "Highlights filter chip should exist in HighlightsSheet"
        )
        highlightsFilter.tap()

        // 9. Verify the Highlights empty state is GONE — a highlight was persisted.
        // If the bug regresses: empty state would still be visible.
        let emptyState = app.otherElements[AccessibilityID.highlightsEmptyState]
        let emptyGonePredicate = NSPredicate(format: "exists == false")
        let emptyGoneExpect = XCTNSPredicateExpectation(predicate: emptyGonePredicate, object: emptyState)
        let result = XCTWaiter().wait(for: [emptyGoneExpect], timeout: 5)

        XCTAssertEqual(
            result, .completed,
            "Highlights tab should show a highlight entry (empty state gone) after gesture-driven " +
            "highlight creation. If this fails, the highlight was not persisted — Bug #160 regressed."
        )
    }
}
