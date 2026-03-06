// WI-UI-6: Reader Settings Sheet — Presentation and Dismissal
//
// Tests verify the settings sheet presents from the reader toolbar,
// shows the correct title, and can be dismissed.

import XCTest

final class ReaderSettingsSheetTests: XCTestCase {
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

    private func openSettingsSheet() {
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 5), "Settings button should be hittable")
        settingsButton.tap()
    }

    // MARK: - Tests

    func testSettingsSheetPresents() {
        navigateToFirstBook()
        openSettingsSheet()

        let settingsPanel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(
            settingsPanel.waitForExistence(timeout: 5),
            "Settings panel should appear after tapping settings button"
        )
    }

    func testSettingsSheetTitle() {
        navigateToFirstBook()
        openSettingsSheet()

        let title = app.navigationBars["Reading Settings"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "Settings sheet should show 'Reading Settings' title"
        )
    }

    func testSettingsSheetDismiss() {
        navigateToFirstBook()
        openSettingsSheet()

        let settingsPanel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(settingsPanel.waitForExistence(timeout: 5))

        // Swipe down to dismiss
        settingsPanel.swipeDown()

        // After dismissal, reader should be visible again
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 5),
            "Reader chrome should be visible after dismissing settings sheet"
        )
    }
}
