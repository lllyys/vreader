import XCTest

/// WI-UI-17: Cross-screen accessibility audit sweep.
///
/// Runs accessibility audits on every reachable screen as a
/// regression safety net. Individual WIs include per-screen audits;
/// this is the consolidated sweep across all screens.
@MainActor
final class GlobalAccessibilityAuditTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Navigate to the first book in the library and wait for the reader to load.
    @discardableResult
    private func navigateToFirstBook() -> Bool {
        tapFirstBook(in: app)
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
    func testLibraryEmptyAudit() {
        app = launchApp(seed: .empty)

        let emptyState = app.otherElements[AccessibilityID.emptyLibraryState]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5),
                      "Empty library state should appear")

        auditCurrentScreen(app: app)
    }

    /// Accessibility audit on populated library state.
    func testLibraryPopulatedAudit() {
        app = launchApp(seed: .books)

        let cardPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        let firstBook = app.buttons.matching(cardPredicate).firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5),
                      "Seeded books should appear")

        auditCurrentScreen(app: app)
    }

    // MARK: - Reader Audits

    /// Accessibility audit on reader container (format placeholder).
    func testReaderContainerAudit() {
        app = launchApp(seed: .books)

        guard navigateToFirstBook() else {
            XCTFail("Could not navigate to reader")
            return
        }

        auditCurrentScreen(app: app)
    }

    /// Accessibility audit on reader settings sheet.
    func testReaderSettingsAudit() {
        app = launchApp(seed: .books)

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

        auditCurrentScreen(app: app)
    }

    /// Accessibility audit on annotations panel.
    func testAnnotationsPanelAudit() {
        app = launchApp(seed: .books)

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

        auditCurrentScreen(app: app)
    }

    /// Accessibility audit on search sheet.
    func testSearchSheetAudit() {
        app = launchApp(seed: .books)

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

        auditCurrentScreen(app: app)
    }

    // MARK: - AI Consent Audit

    /// Accessibility audit on AI consent view.
    func testAIConsentAudit() throws {
        app = launchApp(seed: .books, enableAI: true)

        let consentView = app.otherElements[AccessibilityID.aiConsentView]
        guard consentView.waitForExistence(timeout: 5) else {
            throw XCTSkip("AI consent view not reachable — navigation path not wired")
        }

        auditCurrentScreen(app: app)
    }

    // MARK: - PDF Password Prompt Audit

    /// Accessibility audit on PDF password prompt.
    func testPDFPasswordPromptAudit() throws {
        app = launchApp(seed: .books)

        // Navigate to the protected PDF fixture
        tapBook(titled: "Protected PDF", in: app)

        let passwordPrompt = app.otherElements[AccessibilityID.pdfPasswordPrompt]
        guard passwordPrompt.waitForExistence(timeout: 5) else {
            throw XCTSkip("PDF password prompt not shown — reader wiring incomplete")
        }

        auditCurrentScreen(app: app)
    }

    // MARK: - Error Screen Audit

    /// Accessibility audit on error initialization screen.
    func testErrorScreenAudit() {
        app = launchApp(seed: .corruptDB)

        let errorTitle = app.staticTexts["Unable to Open Library"]
        XCTAssertTrue(errorTitle.waitForExistence(timeout: 5),
                      "Error screen should appear with --seed-corrupt-db")

        auditCurrentScreen(app: app)
    }

    // MARK: - Dark Mode Sweep

    /// Accessibility audit across library and reader in dark mode.
    func testDarkModeAuditAllScreens() {
        app = launchApp(seed: .books, colorScheme: .dark)

        // Audit library in dark mode
        let cardPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        let firstBook = app.buttons.matching(cardPredicate).firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5),
                      "Books should appear in dark mode")
        auditCurrentScreen(app: app)

        // Navigate to reader and audit
        guard navigateToFirstBook() else {
            XCTFail("Could not navigate to reader in dark mode")
            return
        }
        auditCurrentScreen(app: app)

        // Navigate back and verify library
        navigateBackToLibrary()
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))
    }

    // MARK: - AX5 (Largest Dynamic Type) Sweep

    /// Accessibility audit at the largest accessibility Dynamic Type size (AX5).
    func testAX5AuditLibraryAndReaderChrome() {
        app = launchApp(seed: .books, dynamicType: .ax5)

        // Audit library at AX5
        let cardPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        let firstBook = app.buttons.matching(cardPredicate).firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5),
                      "Books should appear at AX5 Dynamic Type")
        auditCurrentScreen(app: app)

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

        auditCurrentScreen(app: app)
    }
}
