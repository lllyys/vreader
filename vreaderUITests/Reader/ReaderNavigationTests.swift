// WI-UI-6: Reader Container View — Navigation and Chrome
//
// Tests verify reader navigation from library, toolbar button presence,
// accessibility labels, and basic back-navigation.
// All reader content is placeholder text in the current app state.

import XCTest

final class ReaderNavigationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Navigates to the first book in the library.
    /// Assumes seeded books are present.
    private func navigateToFirstBook() {
        let firstBook = app.cells.firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5), "Expected at least one book in the library")
        firstBook.tap()
    }

    /// Navigates to a book whose cell contains the given text.
    /// Falls back to first book if no match found.
    private func navigateToBook(containing text: String) {
        let cell = app.cells.containing(.staticText, identifier: text).firstMatch
        if cell.waitForExistence(timeout: 5) {
            cell.tap()
        } else {
            // Fallback: tap first book
            navigateToFirstBook()
        }
    }

    // MARK: - Navigation to Format Readers

    func testNavigateToEPUBReader() {
        navigateToBook(containing: "Test EPUB Book")
        let placeholder = app.staticTexts[AccessibilityID.epubReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "EPUB reader placeholder should appear after tapping an EPUB book"
        )
    }

    func testNavigateToPDFReader() {
        navigateToBook(containing: "Test PDF Document")
        let placeholder = app.staticTexts[AccessibilityID.pdfReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "PDF reader placeholder should appear after tapping a PDF book"
        )
    }

    func testNavigateToTXTReader() {
        navigateToBook(containing: "Test Plain Text")
        let placeholder = app.staticTexts[AccessibilityID.txtReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "TXT reader placeholder should appear after tapping a TXT book"
        )
    }

    func testNavigateToMDReader() {
        navigateToBook(containing: "Test Markdown")
        let placeholder = app.staticTexts[AccessibilityID.mdReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "MD reader placeholder should appear after tapping an MD book"
        )
    }

    // MARK: - Back Navigation

    func testBackButtonReturnsToLibrary() {
        navigateToFirstBook()

        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 5),
            "Back button should exist in reader toolbar"
        )
        backButton.tap()

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library view should reappear after tapping back"
        )
    }

    // MARK: - Toolbar Buttons

    func testToolbarButtonsExist() {
        navigateToFirstBook()

        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]

        XCTAssertTrue(searchButton.waitForExistence(timeout: 5), "Search button should exist")
        XCTAssertTrue(annotationsButton.waitForExistence(timeout: 5), "Annotations button should exist")
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button should exist")
    }

    func testToolbarButtonAccessibilityLabels() {
        navigateToFirstBook()

        let searchButton = app.buttons["Search in book"]
        let annotationsButton = app.buttons["Bookmarks and annotations"]
        let settingsButton = app.buttons["Reading settings"]

        XCTAssertTrue(
            searchButton.waitForExistence(timeout: 5),
            "Search button should have label 'Search in book'"
        )
        XCTAssertTrue(
            annotationsButton.waitForExistence(timeout: 5),
            "Annotations button should have label 'Bookmarks and annotations'"
        )
        XCTAssertTrue(
            settingsButton.waitForExistence(timeout: 5),
            "Settings button should have label 'Reading settings'"
        )
    }

    func testAllToolbarButtonsHittable() {
        navigateToFirstBook()

        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]

        XCTAssertTrue(searchButton.waitForHittable(timeout: 5), "Search button should be hittable")
        XCTAssertTrue(annotationsButton.waitForHittable(timeout: 5), "Annotations button should be hittable")
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 5), "Settings button should be hittable")
    }

    // MARK: - Accessibility

    func testReaderChromeAccessibilityAudit() {
        navigateToFirstBook()

        // Wait for reader to fully load
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
