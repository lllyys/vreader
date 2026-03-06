// WI-UI-10: Search View — Placeholder State
//
// Tests verify the search sheet opens from the reader toolbar,
// shows its placeholder content, and can be dismissed.
// The full SearchView with FTS5 is not mounted yet.

import XCTest

@MainActor
final class SearchSheetPlaceholderTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func navigateToFirstBookAndOpenSearch() {
        tapFirstBook(in: app)

        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        XCTAssertTrue(searchButton.waitForHittable(timeout: 5), "Search button should be hittable")
        searchButton.tap()
    }

    // MARK: - Tests

    func testSearchSheetOpens() {
        navigateToFirstBookAndOpenSearch()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(
            searchSheet.waitForExistence(timeout: 5),
            "Search sheet should appear after tapping search button in reader toolbar"
        )
    }

    func testSearchSheetDismisses() {
        navigateToFirstBookAndOpenSearch()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(searchSheet.waitForExistence(timeout: 5))

        // The placeholder search sheet has a "Done" button
        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 3) {
            doneButton.tap()
        } else {
            // Fallback: swipe down
            searchSheet.swipeDown()
        }

        // Verify reader chrome is visible again
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 5),
            "Reader chrome should be visible after dismissing search sheet"
        )
    }

    func testSearchSheetAccessibilityAudit() {
        navigateToFirstBookAndOpenSearch()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(searchSheet.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
