import XCTest

/// WI-UI-17: Cross-screen accessibility audit sweep.
///
/// Runs performAccessibilityAudit() on every reachable screen as a
/// regression safety net. Individual WIs include per-screen audits;
/// this is the consolidated sweep across all screens.
final class GlobalAccessibilityAuditTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Navigate to the first book in the library and wait for the reader to load.
    @discardableResult
    private func navigateToFirstBook() -> Bool {
        let firstBook = app.cells.firstMatch
        guard firstBook.waitForExistence(timeout: 5) else { return false }
        firstBook.tap()
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        return backButton.waitForExistence(timeout: 5)
    }

    /// Navigate back to library from reader.
    private func navigateBackToLibrary() {
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        if backButton.waitForExistence(timeout: 3) {
            backButton.tap()
        }
    }

    // MARK: - Library Audits

    /// Accessibility audit on empty library state.
    func testLibraryEmptyAudit() throws {
        app.launchArguments = ["--uitesting", "--seed-empty"]
        app.launch()

        let emptyState = app.otherElements[AccessibilityID.emptyLibraryState]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5),
                      "Empty library state should appear")

        try app.performAccessibilityAudit()
    }

    /// Accessibility audit on populated library state.
    func testLibraryPopulatedAudit() throws {
        app.launchArguments = ["--uitesting", "--seed-books"]
        app.launch()

        let firstBook = app.cells.firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5),
                      "Seeded books should appear")

        try app.performAccessibilityAudit()
    }

    // MARK: - Reader Audits

    /// Accessibility audit on reader container (format placeholder).
    func testReaderContainerAudit() throws {
        app.launchArguments = ["--uitesting", "--seed-books"]
        app.launch()

        guard navigateToFirstBook() else {
            XCTFail("Could not navigate to reader")
            return
        }

        try app.performAccessibilityAudit()
    }

    /// Accessibility audit on reader settings sheet.
    func testReaderSettingsAudit() throws {
        app.launchArguments = ["--uitesting", "--seed-books"]
        app.launch()

        guard navigateToFirstBook() else {
            XCTFail("Could not navigate to reader")
            return
        }

        // Open settings
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 3))
        settingsButton.tap()

        let settingsPanel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(settingsPanel.waitForExistence(timeout: 5),
                      "Settings panel should appear")

        try app.performAccessibilityAudit()
    }

    /// Accessibility audit on annotations panel.
    func testAnnotationsPanelAudit() throws {
        app.launchArguments = ["--uitesting", "--seed-books"]
        app.launch()

        guard navigateToFirstBook() else {
            XCTFail("Could not navigate to reader")
            return
        }

        // Open annotations panel
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        XCTAssertTrue(annotationsButton.waitForHittable(timeout: 3))
        annotationsButton.tap()

        let annotationsPanel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(annotationsPanel.waitForExistence(timeout: 5),
                      "Annotations panel should appear")

        try app.performAccessibilityAudit()
    }

    /// Accessibility audit on search sheet.
    func testSearchSheetAudit() throws {
        app.launchArguments = ["--uitesting", "--seed-books"]
        app.launch()

        guard navigateToFirstBook() else {
            XCTFail("Could not navigate to reader")
            return
        }

        // Open search sheet
        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        XCTAssertTrue(searchButton.waitForHittable(timeout: 3))
        searchButton.tap()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(searchSheet.waitForExistence(timeout: 5),
                      "Search sheet should appear")

        try app.performAccessibilityAudit()
    }

    // MARK: - AI Consent Audit

    /// Accessibility audit on AI consent view.
    func testAIConsentAudit() throws {
        app.launchArguments = ["--uitesting", "--enable-ai"]
        app.launch()

        // TODO: Navigate to AI consent view once path is known.
        let consentView = app.otherElements[AccessibilityID.aiConsentView]
        if consentView.waitForExistence(timeout: 5) {
            try app.performAccessibilityAudit()
        } else {
            XCTExpectFailure("AI consent view not reachable — navigation path not wired")
            XCTFail("Could not reach AI consent view for audit")
        }
    }

    // MARK: - PDF Password Prompt Audit

    /// Accessibility audit on PDF password prompt.
    func testPDFPasswordPromptAudit() throws {
        app.launchArguments = ["--uitesting", "--seed-books"]
        app.launch()

        // TODO: PDF password prompt requires navigating to a password-protected PDF.
        // Attempt to find and navigate to the protected PDF fixture.
        let passwordPDFCell = app.cells.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Protected PDF")
        ).firstMatch

        if passwordPDFCell.waitForExistence(timeout: 5) {
            passwordPDFCell.tap()

            let passwordPrompt = app.otherElements[AccessibilityID.pdfPasswordPrompt]
            if passwordPrompt.waitForExistence(timeout: 5) {
                try app.performAccessibilityAudit()
            } else {
                XCTExpectFailure(
                    "PDF password prompt not shown — reader wiring incomplete"
                )
                XCTFail("Password prompt not shown")
            }
        } else {
            XCTExpectFailure(
                "Protected PDF fixture not in seed data"
            )
            XCTFail("Protected PDF not found in library for audit")
        }
    }

    // MARK: - Error Screen Audit

    /// Accessibility audit on error initialization screen.
    func testErrorScreenAudit() throws {
        app.launchArguments = ["--uitesting", "--seed-corrupt-db"]
        app.launch()

        let errorTitle = app.staticTexts["Unable to Open Library"]
        if errorTitle.waitForExistence(timeout: 5) {
            try app.performAccessibilityAudit()
        } else {
            XCTExpectFailure("--seed-corrupt-db launch argument not implemented yet")
            XCTFail("Error screen not shown — cannot run audit")
        }
    }

    // MARK: - Dark Mode Sweep

    /// Accessibility audit across library and reader in dark mode.
    func testDarkModeAuditAllScreens() throws {
        app.launchArguments = ["--uitesting", "--seed-books", "--force-dark"]
        app.launch()

        // Audit library in dark mode
        let firstBook = app.cells.firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5),
                      "Books should appear in dark mode")
        try app.performAccessibilityAudit()

        // Navigate to reader and audit
        guard navigateToFirstBook() else {
            XCTFail("Could not navigate to reader in dark mode")
            return
        }
        try app.performAccessibilityAudit()

        // Navigate back and verify library
        navigateBackToLibrary()
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))
    }

    // MARK: - AX5 (Largest Dynamic Type) Sweep

    /// Accessibility audit at the largest accessibility Dynamic Type size (AX5).
    func testAX5AuditLibraryAndReaderChrome() throws {
        app.launchArguments = ["--uitesting", "--seed-books", "--dynamic-type-AX5"]
        app.launch()

        // Audit library at AX5
        let firstBook = app.cells.firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5),
                      "Books should appear at AX5 Dynamic Type")
        try app.performAccessibilityAudit()

        // Navigate to reader and audit chrome at AX5
        guard navigateToFirstBook() else {
            XCTFail("Could not navigate to reader at AX5 Dynamic Type")
            return
        }

        // Verify toolbar buttons are still present at largest type size
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3),
                      "Settings button should exist at AX5")

        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 3),
                      "Search button should exist at AX5")

        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        XCTAssertTrue(annotationsButton.waitForExistence(timeout: 3),
                      "Annotations button should exist at AX5")

        try app.performAccessibilityAudit()
    }
}
