// WI-UI-9: TXT Reader Container — Placeholder State
//
// Tests verify the TXT reader shows its placeholder when navigating
// to a TXT book. The real TextKit integration is not wired yet.

import XCTest

final class TXTReaderPlaceholderTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func navigateToTXTBook() {
        let txtCell = app.cells.containing(.staticText, identifier: "Test Plain Text").firstMatch
        if txtCell.waitForExistence(timeout: 5) {
            txtCell.tap()
        } else {
            // Fallback: tap first available book
            let firstBook = app.cells.firstMatch
            XCTAssertTrue(firstBook.waitForExistence(timeout: 5))
            firstBook.tap()
        }
    }

    // MARK: - Tests

    func testTXTPlaceholderExists() {
        navigateToTXTBook()

        let placeholder = app.staticTexts[AccessibilityID.txtReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "TXT reader placeholder should appear when opening a TXT book"
        )
    }

    func testTXTPlaceholderAccessibilityAudit() {
        navigateToTXTBook()

        // Wait for reader to load
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
