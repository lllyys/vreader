// WI-UI-8: PDF Reader Container — Placeholder State
//
// Tests verify the PDF reader shows its placeholder when navigating
// to a PDF book. The real PDFKit integration is not wired yet.

import XCTest

@MainActor
final class PDFReaderPlaceholderTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testPDFPlaceholderExists() {
        tapBook(titled: "Test PDF Document", in: app)

        let placeholder = app.staticTexts[AccessibilityID.pdfReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "PDF reader placeholder should appear when opening a PDF book"
        )
    }
}
