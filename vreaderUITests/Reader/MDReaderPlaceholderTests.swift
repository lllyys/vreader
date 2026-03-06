// WI-UI-9: MD Reader Container — Placeholder State
//
// Tests verify the MD reader shows its placeholder when navigating
// to a Markdown book. The real attributed string rendering is not wired yet.

import XCTest

@MainActor
final class MDReaderPlaceholderTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Tests

    func testMDPlaceholderExists() {
        tapBook(titled: "Test Markdown", in: app)

        let placeholder = app.staticTexts[AccessibilityID.mdReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "MD reader placeholder should appear when opening a Markdown book"
        )
    }

    func testMDPlaceholderAccessibilityAudit() {
        tapBook(titled: "Test Markdown", in: app)

        // Wait for reader to load
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
