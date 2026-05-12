// Purpose: UI tests for Feature #28 — TXT native-mode Chinese conversion picker gate.
// Verifies the Chinese conversion picker in ReaderSettingsPanel is ENABLED for TXT
// books in native reading mode, and DISABLED for PDF books (format gate).
//
// @coordinates-with: ReaderSettingsPanel.swift, ReaderContainerView.swift,
//   vreaderTests/Views/Reader/ReaderSettingsPanelChineseConversionGateTests.swift

import XCTest

@MainActor
final class ChineseConversionPickerGateTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Opens a book by title, waits for the reader chrome, taps the settings
    /// button, and waits for the settings panel to appear.
    private func openSettingsPanelForBook(titled title: String) {
        tapBook(titled: title, in: app)

        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(
            settingsButton.waitForHittable(timeout: 10),
            "Reader settings button should be hittable after opening '\(title)'"
        )
        settingsButton.tap()

        let panel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "Reader settings panel should appear after tapping the gear button"
        )
    }

    /// Scrolls the settings panel until an element with the given label
    /// exists (or fails after 8 swipes). SwiftUI Form lazily renders
    /// sections as they scroll into view.
    @discardableResult
    private func scrollPanelUntilLabelExists(_ label: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@", label)
        let target = app.descendants(matching: .any).matching(predicate).firstMatch

        let scroll = app.scrollViews.firstMatch
        for _ in 0..<8 {
            if target.exists { return target }
            if scroll.exists { scroll.swipeUp() } else { app.swipeUp() }
        }
        return target
    }

    // MARK: - TXT Book Gate (should be ENABLED)

    /// Feature #28 core acceptance criterion:
    /// The Chinese conversion picker must be enabled for TXT books
    /// in Native reading mode.
    func testChineseConversionPickerEnabledForTXTBook() {
        openSettingsPanelForBook(titled: "Test Plain Text")

        // Scroll until we find the "Chinese Text" picker label.
        let pickerLabel = scrollPanelUntilLabelExists("Chinese text conversion")
        XCTAssertTrue(
            pickerLabel.waitForExistence(timeout: 5),
            "Chinese text conversion picker should exist in settings panel"
        )

        // The enabled footer text appears when the gate is open.
        let enabledFooter = app.staticTexts[
            "Convert Chinese text between Simplified and Traditional scripts."
        ]
        XCTAssertTrue(
            enabledFooter.waitForExistence(timeout: 3),
            "Enabled footer should appear for TXT book — gate should be OPEN"
        )
    }

    /// Verifies the picker segment options are accessible and interactive
    /// for a TXT book.
    func testChineseConversionPickerSegmentsAccessibleForTXTBook() {
        openSettingsPanelForBook(titled: "Test Plain Text")

        scrollPanelUntilLabelExists("Chinese text conversion")

        // All three segments should exist.
        let noneSegment = app.buttons["None"]
        let simpToTradSegment = app.buttons["Simp → Trad"]
        let tradToSimpSegment = app.buttons["Trad → Simp"]

        XCTAssertTrue(
            noneSegment.waitForExistence(timeout: 3),
            "None segment should exist"
        )
        XCTAssertTrue(
            simpToTradSegment.waitForExistence(timeout: 2),
            "Simp → Trad segment should exist"
        )
        XCTAssertTrue(
            tradToSimpSegment.waitForExistence(timeout: 2),
            "Trad → Simp segment should exist"
        )

        // The picker should be hittable (not disabled) for TXT native mode.
        XCTAssertTrue(
            noneSegment.isHittable || simpToTradSegment.isHittable || tradToSimpSegment.isHittable,
            "At least one segment should be hittable — picker must not be disabled for TXT native mode"
        )
    }

    // NOTE: PDF disabled-gate coverage lives in unit tests.
    // ReaderSettingsPanelChineseConversionGateTests covers all 13 gate combinations
    // including the PDF format-unsupported path (testPDFReturnsFmtUnsupported and
    // testPDFInUnifiedReturnsFmtUnsupported). UI-level PDF verification is omitted
    // here because seed-only PDF books have no actual file and the error state
    // suppresses the reader chrome, making the settings button unreachable.
}
