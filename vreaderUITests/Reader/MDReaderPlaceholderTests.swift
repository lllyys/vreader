// WI-UI-9: MD Reader Container — Placeholder State
//
// Tests verify the MD reader shows its placeholder when navigating
// to a Markdown book. The real attributed string rendering is not wired yet.

import XCTest

final class MDReaderPlaceholderTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func navigateToMDBook() {
        let mdCell = app.cells.containing(.staticText, identifier: "Test Markdown").firstMatch
        if mdCell.waitForExistence(timeout: 5) {
            mdCell.tap()
        } else {
            // Fallback: tap first available book
            let firstBook = app.cells.firstMatch
            XCTAssertTrue(firstBook.waitForExistence(timeout: 5))
            firstBook.tap()
        }
    }

    // MARK: - Tests

    func testMDPlaceholderExists() {
        navigateToMDBook()

        let placeholder = app.staticTexts[AccessibilityID.mdReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "MD reader placeholder should appear when opening a Markdown book"
        )
    }

    func testMDPlaceholderAccessibilityAudit() {
        navigateToMDBook()

        // Wait for reader to load
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
