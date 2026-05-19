// Purpose: Device verification for Feature #48 — TXT chapter-mode highlight pipeline end-to-end.
// Verifies that long-press → Highlight in chapter mode creates a persisted highlight
// that survives app relaunch (PersistenceActor + global-offset locator translation).
//
// Uses --seed-war-and-peace (real chaptered TXT) to exercise chapter-mode reader path.
// Continuous-mode coverage is provided by:
//   TXTHighlightGestureVerificationTests (Bug #160 — Position Test Book)
//
// @coordinates-with: TXTReaderContainerView.swift, TXTBridgeShared.swift,
//   HighlightCoordinator.swift, TXTChapterModeHighlightLocator.swift,
//   HighlightListView.swift, TestSeeder.swift (seedWarAndPeace)

import XCTest

@MainActor
final class TXTChapterModeHighlightVerificationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // disk-backed store + reset-preferences for a clean, persistent slate
        app = launchApp(seed: .warAndPeace, resetPreferences: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func txtReaderTextView() -> XCUIElement {
        app.textViews.matching(identifier: AccessibilityID.txtReaderContainer).firstMatch
    }

    private func waitForChapterMode(timeout: TimeInterval = 15) -> Bool {
        // iOS 26 SwiftUI flattens inner view identifiers: the outer ZStack's
        // txtReaderContainer identifier propagates to the UITextView, so inner
        // Text elements like txtChapterTitleOverlay are not independently accessible.
        // Instead, detect chapter mode via the accessibilityValue of the container,
        // which encodes "chapterMode:true" when isChapterMode is true (same pattern
        // as restoredOffset:N used in Bug #160 tests).
        let container = txtReaderTextView()
        guard container.waitForExistence(timeout: 5) else { return false }
        let predicate = NSPredicate(format: "value CONTAINS 'chapterMode:true'")
        let expect = XCTNSPredicateExpectation(predicate: predicate, object: container)
        return XCTWaiter().wait(for: [expect], timeout: timeout) == .completed
    }

    /// Feature #62: opens `HighlightsSheet` (Notes bottom-chrome button)
    /// and selects the Highlights filter chip.
    private func openHighlightsTab() {
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        if !annotationsButton.waitForExistence(timeout: 2) {
            txtReaderTextView().tap()
        }
        XCTAssertTrue(
            annotationsButton.waitForHittable(timeout: 10),
            "Notes button should be hittable (chrome visible)"
        )
        annotationsButton.tap()

        let panel = app.otherElements[AccessibilityID.highlightsSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5), "HighlightsSheet should appear")

        let highlightsFilter = app.buttons[AccessibilityID.highlightsSheetFilterHighlights]
        XCTAssertTrue(highlightsFilter.waitForExistence(timeout: 3), "Highlights filter chip should exist")
        highlightsFilter.tap()
    }

    private func assertHighlightPresent(file: StaticString = #filePath, line: UInt = #line) {
        let emptyState = app.otherElements[AccessibilityID.highlightsEmptyState]
        let gone = NSPredicate(format: "exists == false")
        let expect = XCTNSPredicateExpectation(predicate: gone, object: emptyState)
        let result = XCTWaiter().wait(for: [expect], timeout: 5)
        XCTAssertEqual(
            result, .completed,
            "Highlights tab should show an entry (empty-state gone) — chapter-mode highlight not persisted",
            file: file, line: line
        )
    }

    // MARK: - Feature #48 Verification

    /// Core acceptance criterion (b): long-press a word in War and Peace Chapter I →
    /// Highlight menu → tap → Highlights tab shows an entry → close → reopen →
    /// highlight still present (survives PersistenceActor round-trip).
    func testChapterModeHighlightCreatedAndPersistsAfterRelaunch() {
        // 1. Open War and Peace
        tapBook(titled: "War and Peace", in: app)

        // 2. Wait for txt reader to appear (loading indicator or content)
        let loadingOrContent = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.txtReaderLoading).firstMatch
        let anyTxtView = app.textViews.matching(identifier: AccessibilityID.txtReaderContainer).firstMatch
        let chapterContent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'txtReaderChapterContent' OR identifier == 'txtReaderContent'")).firstMatch

        // Give reader a moment to start loading
        _ = loadingOrContent.waitForExistence(timeout: 5)
            || anyTxtView.waitForExistence(timeout: 5)
            || chapterContent.waitForExistence(timeout: 5)

        // 3. Wait for chapter mode to activate — txtChapterTitleOverlay is the signal
        XCTAssertTrue(
            waitForChapterMode(),
            "Chapter-mode overlay should appear; war-and-peace.txt has CHAPTER markers. " +
            "Reader state: loading=\(loadingOrContent.exists) txtView=\(anyTxtView.exists) chapterContent=\(chapterContent.exists)"
        )

        // 3. Wait for content to load — loading spinner disappears
        let loading = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.txtReaderLoading).firstMatch
        if loading.exists {
            XCTAssertTrue(
                loading.waitForDisappearance(timeout: 10),
                "Loading indicator should disappear once chapter content loads"
            )
        }

        let textView = txtReaderTextView()
        XCTAssertTrue(
            textView.waitForExistence(timeout: 15),
            "TXT reader text view should exist in chapter mode"
        )

        // 4. Long-press to select a word in the upper third of the visible text
        let pressCoord = textView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        pressCoord.press(forDuration: 1.5)

        // 5. Locate Highlight action in the edit menu
        var highlightElement: XCUIElement = app.menuItems["Highlight"]
        if !highlightElement.waitForExistence(timeout: 4) {
            highlightElement = app.buttons["Highlight"]
        }
        guard highlightElement.waitForExistence(timeout: 4) else {
            XCTFail(
                "Highlight action should appear after long-press in chapter mode. " +
                "If missing, text was not selected or the edit menu did not present."
            )
            return
        }

        // 6. Tap Highlight — HighlightCoordinator translates chapter-local offset
        //    to global offset via makeLocatorForTXT, then calls PersistenceActor.addHighlight
        highlightElement.tap()

        // 7. Open Annotations panel → Highlights tab
        openHighlightsTab()

        // 8. Verify highlight created
        assertHighlightPresent()

        // 9. Terminate app to simulate a real relaunch — this is the persistence test.
        // The AnnotationsPanelView sheet has no close button; swipe-dismiss is unreliable
        // under XCUITest. Terminating and relaunching with keepExisting seed is the
        // canonical way to assert data survived the PersistenceActor disk-backed store.
        app.terminate()

        // 10. Relaunch keeping existing data (disk-backed SwiftData store persists across sessions)
        app = launchApp(seed: .keepExisting, resetPreferences: false)

        // Wait for library grid before attempting reopen
        let libraryOnRelaunch = app.otherElements.matching(identifier: "libraryGrid").firstMatch
        _ = libraryOnRelaunch.waitForExistence(timeout: 10)

        // 11. Reopen War and Peace
        tapBook(titled: "War and Peace", in: app)

        XCTAssertTrue(
            waitForChapterMode(timeout: 15),
            "Chapter-mode overlay should appear on reopen after terminate"
        )
        let loadingOnRelaunch = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.txtReaderLoading).firstMatch
        if loadingOnRelaunch.exists {
            _ = loadingOnRelaunch.waitForDisappearance(timeout: 10)
        }

        // 12. Open Highlights tab on second launch
        openHighlightsTab()

        // 13. Highlight must still be present — this is the persistence assertion
        assertHighlightPresent()
    }
}
