// WI-UI-7: Reader Settings Panel — Theme Picker
//
// Tests verify the theme picker section within the settings panel:
// three theme circles (light, sepia, dark), their touch targets,
// selection state, and accessibility labels.

import XCTest

@MainActor
final class ReaderSettingsThemeTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func navigateToFirstBookAndOpenSettings() {
        tapFirstBook(in: app)

        // Wait for reader chrome to fully load before interacting
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5), "Reader should load before opening settings")

        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 5), "Settings button should be hittable")
        settingsButton.tap()

        let settingsPanel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(settingsPanel.waitForExistence(timeout: 5), "Settings panel should appear")
    }

    // MARK: - Theme Circle Presence

    func testThemeCirclesPresent() {
        navigateToFirstBookAndOpenSettings()

        // ReaderSettingsPanel renders three theme circles with accessibility labels
        let lightTheme = app.buttons["light theme"]
        let sepiaTheme = app.buttons["sepia theme"]
        let darkTheme = app.buttons["dark theme"]

        XCTAssertTrue(lightTheme.waitForExistence(timeout: 3), "Light theme circle should exist")
        XCTAssertTrue(sepiaTheme.waitForExistence(timeout: 3), "Sepia theme circle should exist")
        XCTAssertTrue(darkTheme.waitForExistence(timeout: 3), "Dark theme circle should exist")
    }

    // MARK: - Touch Targets

    func testThemeCircleTouchTargets() {
        navigateToFirstBookAndOpenSettings()

        let themeButtons = ["light theme", "sepia theme", "dark theme"]
        for label in themeButtons {
            let button = app.buttons[label]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "\(label) button should exist")

            let frame = button.frame
            XCTAssertGreaterThanOrEqual(
                frame.width, 44,
                "\(label) button width should be >= 44pt for touch target compliance"
            )
            XCTAssertGreaterThanOrEqual(
                frame.height, 44,
                "\(label) button height should be >= 44pt for touch target compliance"
            )
        }
    }

    // MARK: - Selection

    func testThemeCircleSelection() {
        navigateToFirstBookAndOpenSettings()

        let themes = ["light theme", "sepia theme", "dark theme"]
        for theme in themes {
            let button = app.buttons[theme]
            XCTAssertTrue(button.waitForExistence(timeout: 3), "\(theme) button should exist")
            button.tap()

            // After tapping, the button should still exist (panel should not dismiss)
            XCTAssertTrue(
                button.waitForExistence(timeout: 3),
                "Theme button should remain after tapping \(theme)"
            )

            // Verify the tapped theme is now selected
            XCTAssertTrue(
                button.isSelected,
                "\(theme) button should be selected after tapping"
            )
        }
    }

    // MARK: - Accessibility Labels

    func testThemeCircleAccessibilityLabels() {
        navigateToFirstBookAndOpenSettings()

        // Verify buttons are findable by their accessibility labels
        XCTAssertTrue(
            app.buttons["light theme"].waitForExistence(timeout: 3),
            "Should find button with label 'light theme'"
        )
        XCTAssertTrue(
            app.buttons["sepia theme"].waitForExistence(timeout: 3),
            "Should find button with label 'sepia theme'"
        )
        XCTAssertTrue(
            app.buttons["dark theme"].waitForExistence(timeout: 3),
            "Should find button with label 'dark theme'"
        )
    }
}
