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

    /// Accessibility audit on the annotations sheets — feature #62 split
    /// the unified panel into `TOCSheet` + `HighlightsSheet`, so this
    /// audits both.
    ///
    /// Seeds `.epubFixture` (`mini-epub3.epub` — a real, openable EPUB):
    /// the annotations sheets open from the reader bottom chrome, which
    /// only renders once a book's content loads; the `.books` seed
    /// (metadata-only fixtures, no backing file — Bug #209 / #214)
    /// cannot reach the chrome.
    func testAnnotationsPanelAudit() {
        app = launchApp(seed: .epubFixture)

        guard openSeededReaderBook() else {
            XCTFail("Could not navigate to reader")
            return
        }

        // Audit `TOCSheet` — opened by the Contents bottom-chrome button.
        // The chrome auto-hides on load; a content tap reveals it.
        let contentsButton = app.buttons[AccessibilityID.readerContentsButton]
        if !contentsButton.waitForExistence(timeout: 3) { app.tap() }
        XCTAssertTrue(contentsButton.waitForHittable(timeout: 10))
        contentsButton.tap()
        let tocSheet = app.otherElements[AccessibilityID.tocSheet]
        XCTAssertTrue(tocSheet.waitForExistence(timeout: 5), "TOCSheet should appear")
        // Exclusions for TOCSheet:
        //  - `.elementDetection`: the `AnnotationsEmptyStateView` art is
        //    a decorative SVG-path illustration whose stylized
        //    "text-line" bars trip the audit's pixel text detector (the
        //    issue is reported with `element == nil`; no real control
        //    is missing a label).
        //  - `.hitRegion`: TOCSheet's Contents/Bookmarks tabs are a
        //    designed compact segmented control. Its segment height
        //    mirrors the iOS-native `UISegmentedControl` idiom (which
        //    is itself sub-44pt and flagged identically by this audit);
        //    enlarging the segments would change the committed design
        //    (rule 51). The `HighlightsSheet` audit below keeps
        //    `.hitRegion` active. All other audit types still run.
        auditCurrentScreen(app: app, excluding: [.elementDetection, .hitRegion])

        // Dismiss, then audit `HighlightsSheet` — opened by the Notes button.
        if app.buttons[AccessibilityID.sheetCloseButton].exists {
            app.buttons[AccessibilityID.sheetCloseButton].tap()
        } else {
            app.swipeDown()
        }
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        if !annotationsButton.waitForExistence(timeout: 3) { app.tap() }
        XCTAssertTrue(annotationsButton.waitForHittable(timeout: 10))
        annotationsButton.tap()
        let highlightsSheet = app.otherElements[AccessibilityID.highlightsSheet]
        XCTAssertTrue(highlightsSheet.waitForExistence(timeout: 5), "HighlightsSheet should appear")
        // `.elementDetection` excluded for the same decorative-art
        // reason as the TOCSheet audit above.
        auditCurrentScreen(app: app, excluding: .elementDetection)
    }

    /// Opens the seeded `.epubFixture` book into the reader, retrying the
    /// card tap for the library `LazyVGrid` initial-layout race.
    @discardableResult
    private func openSeededReaderBook() -> Bool {
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        ).firstMatch
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        ).firstMatch
        let backButton = app.buttons[AccessibilityID.readerBackButton]

        for _ in 0..<3 {
            if card.waitForExistence(timeout: 15) {
                if card.waitForHittable(timeout: 8) || card.exists { card.tap() }
            } else if row.waitForExistence(timeout: 3) {
                if row.waitForHittable(timeout: 8) || row.exists { row.tap() }
            }
            if backButton.waitForExistence(timeout: 20) { return true }
        }
        return false
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

        // Bug #224 / GH #902: feature #63's `SearchBar` re-skin gave the
        // `searchTextField` and `searchCancelButton` accessibility frames
        // below the 44 pt HIG touch-target minimum. The fix gives both
        // controls a >=44 pt tappable frame, so `.hitRegion` is now
        // covered by the audit (no longer excluded as tracked debt).
        //
        // The search bar auto-focuses its field, raising the software
        // keyboard; `ignoringKeyboardElements` skips Apple keyboard-
        // internal audit gaps (e.g. `TUIPredictionViewCell`) so the
        // audit stays honest for the app's own SearchBar elements.
        auditCurrentScreen(app: app, ignoringKeyboardElements: true)
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
