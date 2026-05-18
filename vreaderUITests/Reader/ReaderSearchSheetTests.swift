// WI-UI-6: Reader Search Sheet — Presentation and Dismissal
//
// Tests verify the search sheet presents from the reader toolbar
// and can be dismissed.
//
// Feature #63 WI-1: the v2 re-skin replaced the system `.searchable`
// bar + `NavigationStack` `Done` toolbar with a custom in-sheet bar.
// The dismiss affordance is now the "Cancel" button
// (`searchCancelButton`), not "Done".

import XCTest

@MainActor
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

    private func openSearchSheet() {
        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        XCTAssertTrue(searchButton.waitForHittable(timeout: 5), "Search button should be hittable")
        searchButton.tap()
    }

    // MARK: - Tests

    func testSearchSheetPresents() {
        tapFirstBook(in: app)
        openSearchSheet()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(
            searchSheet.waitForExistence(timeout: 5),
            "Search sheet should appear after tapping search button"
        )
    }

    func testSearchSheetDismiss() {
        tapFirstBook(in: app)
        openSearchSheet()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(searchSheet.waitForExistence(timeout: 5))

        // Feature #63 WI-1: the re-skinned sheet's custom bar has a
        // "Cancel" button (`searchCancelButton`) in place of the old
        // NavigationStack "Done" toolbar button.
        let cancelButton = app.buttons[AccessibilityID.searchCancelButton]
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
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
