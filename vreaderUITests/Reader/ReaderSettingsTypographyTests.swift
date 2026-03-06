// WI-UI-7: Reader Settings Panel — Typography Controls
//
// Tests verify the typography controls in the settings panel:
// font size slider, line spacing slider, font family picker,
// CJK spacing toggle, and their accessibility properties.

import XCTest

final class ReaderSettingsTypographyTests: XCTestCase {
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
        let firstBook = app.cells.firstMatch
        XCTAssertTrue(firstBook.waitForExistence(timeout: 5), "Expected at least one book in the library")
        firstBook.tap()

        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(settingsButton.waitForHittable(timeout: 5), "Settings button should be hittable")
        settingsButton.tap()

        let settingsPanel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(settingsPanel.waitForExistence(timeout: 5), "Settings panel should appear")
    }

    // MARK: - Font Size Slider

    func testFontSizeSliderExists() {
        navigateToFirstBookAndOpenSettings()

        let slider = app.sliders["Font size"]
        XCTAssertTrue(
            slider.waitForExistence(timeout: 3),
            "Font size slider should exist in settings panel"
        )
    }

    func testFontSizeSliderAccessibilityLabel() {
        navigateToFirstBookAndOpenSettings()

        // The slider should be findable by its accessibility label
        let slider = app.sliders["Font size"]
        XCTAssertTrue(
            slider.waitForExistence(timeout: 3),
            "Slider with 'Font size' accessibility label should exist"
        )
    }

    // MARK: - Line Spacing Slider

    func testLineSpacingSliderExists() {
        navigateToFirstBookAndOpenSettings()

        let slider = app.sliders["Line spacing"]
        XCTAssertTrue(
            slider.waitForExistence(timeout: 3),
            "Line spacing slider should exist in settings panel"
        )
    }

    // MARK: - Font Family Picker

    func testFontFamilyPickerExists() {
        navigateToFirstBookAndOpenSettings()

        // The segmented picker should be accessible with its label
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(
            picker.waitForExistence(timeout: 3),
            "Font family segmented picker should exist in settings panel"
        )
    }

    func testFontFamilySegments() {
        navigateToFirstBookAndOpenSettings()

        // Verify the three font family segments exist
        let systemButton = app.buttons["System"]
        let serifButton = app.buttons["Serif"]
        let monospaceButton = app.buttons["Monospace"]

        XCTAssertTrue(systemButton.waitForExistence(timeout: 3), "System segment should exist")
        XCTAssertTrue(serifButton.waitForExistence(timeout: 3), "Serif segment should exist")
        XCTAssertTrue(monospaceButton.waitForExistence(timeout: 3), "Monospace segment should exist")
    }

    // MARK: - CJK Toggle

    func testCJKToggleExists() {
        navigateToFirstBookAndOpenSettings()

        let toggle = app.switches["CJK character spacing"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 3),
            "CJK spacing toggle should exist in settings panel"
        )
    }

    func testCJKToggleFooterText() {
        navigateToFirstBookAndOpenSettings()

        let footerText = app.staticTexts["Adds extra spacing between CJK characters for improved readability."]
        XCTAssertTrue(
            footerText.waitForExistence(timeout: 3),
            "CJK toggle footer explanation text should be visible"
        )
    }

    // MARK: - Accessibility Audit

    func testSettingsPanelAccessibilityAudit() {
        navigateToFirstBookAndOpenSettings()
        auditCurrentScreen(app: app)
    }
}
