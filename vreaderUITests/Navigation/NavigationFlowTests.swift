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
        XCTAssertTrue(navigateToFirstBook(), "Should navigate to reader")

        // Open annotations panel
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        XCTAssertTrue(annotationsButton.waitForHittable(timeout: 3),
                      "Annotations button should be hittable")
        annotationsButton.tap()

        // Verify annotations panel appears
        let annotationsPanel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(annotationsPanel.waitForExistence(timeout: 5),
                      "Annotations panel should appear")

        // Switch to a different tab (e.g., Highlights)
        let highlightsTab = app.buttons["Highlights"]
        if highlightsTab.waitForExistence(timeout: 3) {
            highlightsTab.tap()
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
        // Step 1: Library -> Reader
        XCTAssertTrue(navigateToFirstBook(), "Should navigate to reader")

        // Step 2: Reader -> Settings sheet
        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 3))
        settingsButton.tap()

        let settingsPanel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(settingsPanel.waitForExistence(timeout: 5),
                      "Settings panel should appear")

        // Step 3: Dismiss settings
        settingsPanel.swipeDown()

        // Step 4: Reader -> Annotations panel
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        XCTAssertTrue(annotationsButton.waitForHittable(timeout: 5),
                      "Annotations button should be hittable after settings dismiss")
        annotationsButton.tap()

        let annotationsPanel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(annotationsPanel.waitForExistence(timeout: 5),
                      "Annotations panel should appear")

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
