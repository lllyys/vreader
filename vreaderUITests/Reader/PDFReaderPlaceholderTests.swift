// WI-UI-8: PDF Reader Container — Placeholder State
//
// Tests verify the PDF reader shows its placeholder when navigating
// to a PDF book. The real PDFKit integration is not wired yet.

import XCTest

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
        // Navigate to a PDF book
        let pdfCell = app.cells.containing(.staticText, identifier: "Test PDF Document").firstMatch
        if pdfCell.waitForExistence(timeout: 5) {
            pdfCell.tap()
        } else {
            // Fallback: tap first book and hope it's PDF
            let firstBook = app.cells.firstMatch
            XCTAssertTrue(firstBook.waitForExistence(timeout: 5))
            firstBook.tap()
        }

        let placeholder = app.staticTexts[AccessibilityID.pdfReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "PDF reader placeholder should appear when opening a PDF book"
        )
    }
}
