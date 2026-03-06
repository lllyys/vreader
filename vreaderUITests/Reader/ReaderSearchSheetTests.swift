// WI-UI-6: Reader Search Sheet — Presentation and Dismissal
//
// Tests verify the search sheet presents from the reader toolbar
// and can be dismissed.

import XCTest

final class ReaderSearchSheetTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func navigateToFirstBook() {
        let firstBook = app.cells.firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5), "Expected at least one book in the library")
        firstBook.tap()
    }

    private func openSearchSheet() {
        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        XCTAssertTrue(searchButton.waitForHittable(timeout: 5), "Search button should be hittable")
        searchButton.tap()
    }

    // MARK: - Tests

    func testSearchSheetPresents() {
        navigateToFirstBook()
        openSearchSheet()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(
            searchSheet.waitForExistence(timeout: 5),
            "Search sheet should appear after tapping search button"
        )
    }

    func testSearchSheetDismiss() {
        navigateToFirstBook()
        openSearchSheet()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(searchSheet.waitForExistence(timeout: 5))

        // The search sheet has a "Done" button in the toolbar
        let doneButton = app.buttons["Done"]
        if doneButton.waitForExistence(timeout: 3) {
            doneButton.tap()
        } else {
            // Fallback: swipe down to dismiss
            searchSheet.swipeDown()
        }

        // Reader chrome should reappear
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 5),
            "Reader chrome should be visible after dismissing search sheet"
        )
    }
}
