// WI-UI-9: TXT Reader Container — Placeholder State
//
// Tests verify the TXT reader shows its placeholder when navigating
// to a TXT book. The real TextKit integration is not wired yet.

import XCTest

@MainActor
final class TXTReaderPlaceholderTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tests

    func testTXTPlaceholderExists() {
        tapBook(titled: "Test Plain Text", in: app)

        let placeholder = app.staticTexts[AccessibilityID.txtReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "TXT reader placeholder should appear when opening a TXT book"
        )
    }

    func testTXTPlaceholderAccessibilityAudit() {
        tapBook(titled: "Test Plain Text", in: app)

        // Wait for reader to load
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
