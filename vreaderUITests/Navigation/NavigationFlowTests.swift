import XCTest

/// WI-UI-15: Full navigation flow integration tests.
///
/// Verifies end-to-end navigation: library -> reader -> settings -> back,
/// reader -> annotations -> tab switch -> dismiss, and edge cases like
/// rapid navigation and reduce-motion transitions.
@MainActor
final class NavigationFlowTests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
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

    /// Relaunches with the `.epubFixture` seed and opens the seeded book
    /// into the reader. Feature #62: the annotations sheets open from the
    /// reader bottom chrome, which only renders once a book's content
    /// loads — the class-default `.books` seed's fixtures are
    /// metadata-only (no backing file, "The file could not be found",
    /// Bug #209 / #214), so the reader never finishes loading and the
    /// chrome's Notes button never becomes hittable. The card tap is
    /// retried for the library `LazyVGrid` initial-layout race.
    @discardableResult
    private func openSeededReaderBook() -> Bool {
        app.terminate()
        app = launchApp(seed: .epubFixture)

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

    /// Reveals the auto-hidden reader chrome (a content tap toggles it
    /// on) and returns the bottom-chrome button for `id`.
    private func chromeButton(_ id: String) -> XCUIElement {
        let button = app.buttons[id]
        if !button.waitForExistence(timeout: 3) {
            app.tap()
        }
        return button
    }

    // MARK: - Library to Reader and Back

    /// Tap book -> verify reader appears -> tap back -> verify library returns.
    func testLibraryToReaderAndBack() throws {
        // Navigate to reader
        XCTAssertTrue(navigateToFirstBook(), "Should navigate to reader")

        // Verify reader chrome is present
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 3),
                      "Reader settings button should be visible")

        // Navigate back
        navigateBackToLibrary()

        // Verify library is visible again
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5),
                      "Library view should reappear after navigating back")
    }

    // MARK: - Reader Settings Round Trip

    /// Reader -> tap settings -> verify sheet -> dismiss -> verify reader.
    func testReaderSettingsRoundTrip() throws {
        XCTAssertTrue(navigateToFirstBook(), "Should navigate to reader")

        // Open settings sheet
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 3),
                      "Settings button should be hittable")
        settingsButton.tap()

        // Verify settings sheet appears
        let settingsPanel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(settingsPanel.waitForExistence(timeout: 5),
                      "Reader settings panel should appear")

        let settingsTitle = app.staticTexts["Reading Settings"]
        XCTAssertTrue(settingsTitle.waitForExistence(timeout: 3),
                      "Settings panel should show 'Reading Settings' title")

        // Dismiss by swiping down
        settingsPanel.swipeDown()

        // Verify reader is still visible after dismissal
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5),
                      "Reader should be visible after dismissing settings")
    }

    // MARK: - Reader Annotations Round Trip

    /// Reader -> tap annotations -> verify panel -> switch tab -> dismiss -> verify reader.
    func testReaderAnnotationsRoundTrip() throws {
        XCTAssertTrue(openSeededReaderBook(), "Should navigate to reader")

        // Feature #62: the Notes bottom-chrome button opens `HighlightsSheet`.
        let annotationsButton = chromeButton(AccessibilityID.readerAnnotationsButton)
        XCTAssertTrue(annotationsButton.waitForHittable(timeout: 10),
                      "Notes button should be hittable")
        annotationsButton.tap()

        // Verify HighlightsSheet appears
        let annotationsPanel = app.otherElements[AccessibilityID.highlightsSheet]
        XCTAssertTrue(annotationsPanel.waitForExistence(timeout: 5),
                      "HighlightsSheet should appear")

        // Switch to a different filter (e.g., Highlights)
        let highlightsFilter = app.buttons[AccessibilityID.highlightsSheetFilterHighlights]
        if highlightsFilter.waitForExistence(timeout: 3) {
            highlightsFilter.tap()
        }

        // Dismiss by swiping down
        annotationsPanel.swipeDown()

        // Verify reader is still visible
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5),
                      "Reader should be visible after dismissing annotations panel")
    }

    // MARK: - Full Navigation Round Trip

    /// Library -> book -> settings -> dismiss -> annotations -> dismiss -> back -> library.
    func testFullNavigationRoundTrip() throws {
        // Step 1: Library -> Reader (`.epubFixture` — the annotations
        // sheet in Step 4 needs a real, openable book; see
        // `openSeededReaderBook`).
        XCTAssertTrue(openSeededReaderBook(), "Should navigate to reader")

        // Step 2: Reader -> Settings sheet
        let settingsButton = chromeButton(AccessibilityID.readerSettingsButton)
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 10))
        settingsButton.tap()

        let settingsPanel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(settingsPanel.waitForExistence(timeout: 5),
                      "Settings panel should appear")

        // Step 3: Dismiss settings
        settingsPanel.swipeDown()

        // Step 4: Reader -> HighlightsSheet (the Notes bottom-chrome button)
        let annotationsButton = chromeButton(AccessibilityID.readerAnnotationsButton)
        XCTAssertTrue(annotationsButton.waitForHittable(timeout: 10),
                      "Notes button should be hittable after settings dismiss")
        annotationsButton.tap()

        let annotationsPanel = app.otherElements[AccessibilityID.highlightsSheet]
        XCTAssertTrue(annotationsPanel.waitForExistence(timeout: 5),
                      "HighlightsSheet should appear")

        // Step 5: Dismiss annotations
        annotationsPanel.swipeDown()

        // Step 6: Reader -> Library
        navigateBackToLibrary()

        // Step 7: Verify library
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5),
                      "Library view should reappear after full round trip")
    }

    // MARK: - Rapid Back Navigation

    /// Tap book then immediately tap back — tests resilience to rapid navigation.
    func testRapidBackNavigation() throws {
        tapFirstBook(in: app)

        // Immediately try to tap back (before reader fully loads)
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        if backButton.waitForExistence(timeout: 2) {
            backButton.tap()
        } else {
            // If back button hasn't appeared yet, try the navigation bar back
            let navBackButton = app.navigationBars.buttons.firstMatch
            if navBackButton.waitForExistence(timeout: 2) {
                navBackButton.tap()
            }
        }

        // After rapid back-navigation, the library should return.
        // Wait long enough for any transition to settle.
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 10),
                      "Library view should reappear after rapid back navigation")
    }

    // MARK: - Reduce Motion Transitions

    /// With reduce motion enabled, navigation transitions complete without animation.
    func testReduceMotionTransitions() throws {
        // Relaunch with reduce motion flag
        app.terminate()
        app = launchApp(seed: .books, reduceMotion: true)

        // Full round trip with reduce motion
        XCTAssertTrue(navigateToFirstBook(), "Should navigate to reader with reduce motion")

        // Open and dismiss settings
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 3))
        settingsButton.tap()

        let settingsPanel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(settingsPanel.waitForExistence(timeout: 5),
                      "Settings should appear with reduce motion")
        settingsPanel.swipeDown()

        // Navigate back
        navigateBackToLibrary()

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5),
                      "Library should appear after reduce-motion round trip")
    }
}
