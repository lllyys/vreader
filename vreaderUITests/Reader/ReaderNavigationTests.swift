// WI-UI-6: Reader Container View — Navigation and Chrome
//
// Tests verify reader navigation from library, toolbar button presence,
// accessibility labels, and basic back-navigation.
// All reader content is placeholder text in the current app state.

import XCTest

@MainActor
final class ReaderNavigationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Navigation to Format Readers

    func testNavigateToEPUBReader() {
        tapBook(titled: "Test EPUB Book", in: app)
        let placeholder = app.staticTexts[AccessibilityID.epubReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "EPUB reader placeholder should appear after tapping an EPUB book"
        )
    }

    func testNavigateToPDFReader() {
        tapBook(titled: "Test PDF Document", in: app)
        let placeholder = app.staticTexts[AccessibilityID.pdfReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "PDF reader placeholder should appear after tapping a PDF book"
        )
    }

    func testNavigateToTXTReader() {
        tapBook(titled: "Test Plain Text", in: app)
        let placeholder = app.staticTexts[AccessibilityID.txtReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "TXT reader placeholder should appear after tapping a TXT book"
        )
    }

    func testNavigateToMDReader() {
        tapBook(titled: "Test Markdown", in: app)
        let placeholder = app.staticTexts[AccessibilityID.mdReaderPlaceholder]
        XCTAssertTrue(
            placeholder.waitForExistence(timeout: 5),
            "MD reader placeholder should appear after tapping an MD book"
        )
    }

    // MARK: - Back Navigation

    func testBackButtonReturnsToLibrary() {
        tapFirstBook(in: app)

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
        tapFirstBook(in: app)

        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]

        XCTAssertTrue(searchButton.waitForExistence(timeout: 5), "Search button should exist")
        XCTAssertTrue(annotationsButton.waitForExistence(timeout: 5), "Annotations button should exist")
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button should exist")
    }

    func testToolbarButtonAccessibilityLabels() {
        tapFirstBook(in: app)

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
        tapFirstBook(in: app)

        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]

        XCTAssertTrue(searchButton.waitForHittable(timeout: 5), "Search button should be hittable")
        XCTAssertTrue(annotationsButton.waitForHittable(timeout: 5), "Annotations button should be hittable")
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 5), "Settings button should be hittable")
    }

    // MARK: - Accessibility

    func testReaderChromeAccessibilityAudit() {
        tapFirstBook(in: app)

        // Wait for reader to fully load
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
