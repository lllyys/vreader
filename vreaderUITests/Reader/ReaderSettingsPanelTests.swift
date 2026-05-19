// Purpose: UI tests for the Reader Settings Panel surface. Verifies the
// panel opens from the reader chrome's settings button and renders its
// standard sections, and — post feature #54 WI-4 — that the removed
// Reading Mode picker and Tap Zones section are absent.
//
// @coordinates-with: vreader/Views/Reader/ReaderSettingsPanel.swift,
//   vreader/Views/Reader/ReaderChromeBar.swift,
//   vreader/Views/Reader/ReaderContainerView.swift

import XCTest

@MainActor
final class ReaderSettingsPanelTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // `.warAndPeace` is a real-file TXT fixture that opens into a
        // working reader. The `.books` seed inserts metadata-only
        // BookRecords with no backing file, so opening one fails with
        // "The file could not be found" and the reader chrome never
        // renders (Bug #209 / GH #804) — the panel is then unreachable.
        app = launchApp(seed: .warAndPeace, resetPreferences: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Opens the first available book and taps the reader chrome's
    /// settings (gear) button. Returns once the
    /// `readerSettingsPanel` element exists.
    private func openReaderSettingsPanel() {
        tapFirstBook(in: app)

        let settingsButton = app.buttons[AccessibilityID.readerSettingsButton]
        XCTAssertTrue(
            settingsButton.waitForHittable(timeout: 10),
            "Reader settings button should be hittable once a book is open"
        )
        settingsButton.tap()

        let panel = app.otherElements[AccessibilityID.readerSettingsPanel]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "Reader settings panel should appear after tapping the gear button"
        )
    }

    /// Scrolls the settings panel until an element matching the given
    /// accessibility label exists, or fails after 6 swipes. SwiftUI
    /// Form lazily renders sections, so deeper rows are only added to
    /// the accessibility tree once scrolled into view.
    @discardableResult
    private func scrollPanelUntilLabelExists(_ label: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@", label)
        let target = app.descendants(matching: .any).matching(predicate).firstMatch

        let scrollSurface = app.scrollViews.firstMatch
        for _ in 0..<6 {
            if target.exists { return target }
            if scrollSurface.exists {
                scrollSurface.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        return target
    }

    // MARK: - Panel Presentation

    func testReaderSettingsPanelOpens() {
        openReaderSettingsPanel()

        // Standard sections should render — sanity check that the
        // panel actually populated and isn't a stub.
        let themeHeading = app.staticTexts["Theme"]
        XCTAssertTrue(
            themeHeading.waitForExistence(timeout: 3),
            "Theme section header should render in the reader settings panel"
        )
    }

    // MARK: - Removed controls (feature #54 WI-4)

    /// Feature #54 WI-4 removed the Unified-only Tap Zones configuration
    /// section. The panel must no longer surface it — even after
    /// scrolling the whole panel.
    func testReaderSettingsHasNoTapZonesSection() {
        openReaderSettingsPanel()

        let header = scrollPanelUntilLabelExists("Tap Zones")
        XCTAssertFalse(
            header.exists,
            "Tap Zones section must be gone — feature #54 WI-4 removed it"
        )
    }

    /// Feature #54 WI-4 removed the Native/Unified Reading Mode picker.
    /// Neither the section nor its "Native" / "Unified" options render.
    func testReaderSettingsHasNoReadingModePicker() {
        openReaderSettingsPanel()

        // The picker is gone, so neither tag option ("Native" / "Unified")
        // should appear in the panel's accessibility tree.
        let nativeOption = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Native"))
            .firstMatch
        XCTAssertFalse(
            nativeOption.waitForExistence(timeout: 3),
            "Reading Mode picker must be gone — feature #54 WI-4 removed it"
        )
        let unifiedOption = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Unified"))
            .firstMatch
        XCTAssertFalse(
            unifiedOption.exists,
            "Reading Mode picker 'Unified' option must be gone — feature #54 WI-4"
        )
    }

    // MARK: - Accessibility Audit

    func testReaderSettingsPanelAccessibilityAudit() {
        openReaderSettingsPanel()

        auditCurrentScreen(app: app)
    }
}
