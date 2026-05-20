// Purpose: Device verification for Feature #12 — Auto-generate TOC for MD files.
// Exercises the UI gesture path previously deferred: open .md file → TOC panel
// shows headings → tap heading → panel dismisses (navigation fired).
//
// Feature: MD reader automatically extracts ATX headings (# through ######) from
// Markdown text via TOCBuilder.forMD and displays them in the annotations panel
// "Contents" tab. Tapping a heading navigates to that position and dismisses the panel.
//
// Seed: --seed-md-toc writes a real MD file with 5 headings to ImportedBooks/
// via TestSeeder.seedMDWithTOC.
//
// @coordinates-with: MDReaderContainerView.swift, TOCListView.swift,
//   TOCBuilder.swift, AnnotationsPanelView.swift, TestSeeder.swift

import XCTest

@MainActor
final class MDTOCVerificationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .mdTOC, resetPreferences: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func waitForMDReaderReady(timeout: TimeInterval = 15) -> Bool {
        // Reader is ready when: back button exists (we're in the reader) AND loading is gone
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        guard backButton.waitForExistence(timeout: timeout) else { return false }

        let loading = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.mdReaderLoading).firstMatch
        if loading.exists {
            _ = loading.waitForDisappearance(timeout: timeout)
        }
        return true
    }

    // MARK: - Feature #12 Close-Gate Verification

    /// Verifies that the MD reader's TOC:
    /// 1. Extracts headings from the fixture and shows them in the Contents panel
    ///    (tocEmptyState absent = at least one heading extracted)
    /// 2. Tap a TOC row dismisses the panel (handleNavigate fired = navigation wired)
    func testMDTOCShowsHeadingsAndNavigatesOnTap() throws {
        // 1. Open the MD TOC fixture book
        tapBook(titled: "Test Markdown TOC", in: app)

        // 2. Wait for MD reader to finish loading
        XCTAssertTrue(
            waitForMDReaderReady(),
            "MD reader should load 'Test Markdown TOC' within timeout"
        )

        // 3. Show chrome (may be auto-hidden after initial load).
        //    Feature #62: the TOC now lives in `TOCSheet`, opened by the
        //    bottom-chrome Contents button.
        let contentsButton = app.buttons[AccessibilityID.readerContentsButton]
        if !contentsButton.waitForExistence(timeout: 3) {
            // Tap center of screen to toggle chrome visibility
            app.tap()
        }
        XCTAssertTrue(
            contentsButton.waitForHittable(timeout: 10),
            "Contents button should be hittable (reader chrome visible)"
        )

        // 4. Open the TOC sheet (`TOCSheet`) — opens on the Contents tab.
        contentsButton.tap()

        let panel = app.otherElements[AccessibilityID.tocSheet]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "TOC sheet should appear after tapping the Contents button"
        )

        // 5. Verify TOC has entries — tocEmptyState must NOT exist
        //    (its absence means TOCBuilder.forMD extracted at least one heading)
        let emptyState = app.otherElements[AccessibilityID.tocEmptyState]
        let notEmptyPredicate = NSPredicate(format: "exists == false")
        let emptyStateGone = XCTNSPredicateExpectation(predicate: notEmptyPredicate, object: emptyState)
        let waitResult = XCTWaiter().wait(for: [emptyStateGone], timeout: 5)
        XCTAssertEqual(
            waitResult, .completed,
            "TOC should have entries (tocEmptyState absent). " +
            "If tocEmptyState is present, TOCBuilder.forMD failed to extract headings from the fixture. " +
            "Check that the MD file was written with valid ATX headings (#, ##, ###)."
        )

        // 6. Find the first tocRow-* button (any heading in the list)
        let firstTOCRow = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'tocRow-'")
        ).firstMatch
        XCTAssertTrue(
            firstTOCRow.waitForExistence(timeout: 5),
            "At least one tocRow-* button should be visible in the TOC list"
        )

        // 7. Tap the first TOC row — triggers handleNavigate which calls onNavigate + onDismiss
        firstTOCRow.tap()

        // 8. Assert the panel dismissed — proves handleNavigate fired (navigation wired correctly)
        XCTAssertTrue(
            panel.waitForDisappearance(timeout: 5),
            "Annotations panel should dismiss after tapping a TOC row. " +
            "Dismiss proves AnnotationsPanelView.handleNavigate fired (calls onDismiss after onNavigate). " +
            "If panel stays open, the TOC row's onNavigate closure was not wired."
        )

        // 9. Assert back button still exists (reader didn't crash / pop on navigation)
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 5),
            "MD reader back button should still be visible after TOC navigation (no crash on navigate)"
        )
    }
}
