// WI-UI-6: Reader Settings Sheet — Presentation and Dismissal
//
// Tests verify the settings sheet presents from the reader toolbar,
// shows the correct title, and can be dismissed.

import XCTest

@MainActor
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

    private func openSettingsSheet() {
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 5), "Settings button should be hittable")
        settingsButton.tap()
    }

    // MARK: - Tests

    func testSettingsSheetPresents() {
        tapFirstBook(in: app)
        openSettingsSheet()

        let settingsPanel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(
            settingsPanel.waitForExistence(timeout: 5),
            "Settings panel should appear after tapping settings button"
        )
    }

    func testSettingsSheetTitle() {
        tapFirstBook(in: app)
        openSettingsSheet()

        let title = app.navigationBars["Reading Settings"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "Settings sheet should show 'Reading Settings' title"
        )
    }

    func testSettingsSheetDismiss() {
        tapFirstBook(in: app)
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
