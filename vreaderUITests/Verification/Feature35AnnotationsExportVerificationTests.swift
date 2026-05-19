// Purpose: Verification tests for Feature #35 — annotations export.
// Confirms the Export button exists in `HighlightsSheet`'s trailing
// slot and is hittable. Live share-sheet observation is XCUI-limited
// (system-presented activity views are outside the app process), so
// this exercises the trigger surface only.
//
// Feature #62: the annotations panel was split — the export action now
// lives in `HighlightsSheet` (opened by the Notes bottom-chrome button).
// The legacy Import button is GONE: the committed `HighlightsSheetV3`
// design has no import affordance, so import is deferred to
// needs-design #963. The former import-button test is replaced by an
// assertion that no import button ships.
//
// Seed: `.epubFixture` (`mini-epub3.epub`) — a real, openable EPUB.
// `HighlightsSheet` opens from the reader Notes bottom-chrome button,
// which only renders once a book's content loads; the `.books` seed
// (metadata-only fixtures, no backing file — Bug #209 / #214) cannot
// reach the chrome.
//
// @coordinates-with: HighlightsSheet.swift, HighlightsSheet+Export.swift,
//   AnnotationExporter.swift, TestSeeder.swift, LaunchHelper.swift

import XCTest

@MainActor
final class Feature35AnnotationsExportVerificationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .epubFixture, resetPreferences: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Opens the seeded EPUB book and waits for the reader chrome. The
    /// card tap is retried for the library `LazyVGrid` layout race.
    @discardableResult
    private func openSeededBook() -> Bool {
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

    /// Feature #62: the export action moved to `HighlightsSheet`, opened
    /// by the Notes bottom-chrome button. The chrome auto-hides on load;
    /// a content tap reveals it so the Notes button becomes hittable.
    private func openHighlightsSheet() throws -> XCUIElement {
        XCTAssertTrue(openSeededBook(), "Seeded mini-epub3 EPUB should open into the reader")

        let button = app.buttons[AccessibilityID.readerAnnotationsButton]
        if !button.waitForExistence(timeout: 3) {
            app.tap()   // reveal the auto-hidden chrome
        }
        XCTAssertTrue(
            button.waitForHittable(timeout: 10),
            "Reader Notes button should be hittable (chrome visible)"
        )
        button.tap()

        let panel = app.otherElements[AccessibilityID.highlightsSheet]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "HighlightsSheet should appear"
        )
        return panel
    }

    // MARK: - Feature #35 Verification

    /// Verifies the Export button exists in `HighlightsSheet`'s trailing slot.
    func test_verify_feature_35_export_button_is_visible() throws {
        _ = try openHighlightsSheet()

        let exportButton = app.buttons[AccessibilityID.annotationsExportButton]
        XCTAssertTrue(
            exportButton.waitForExistence(timeout: 5),
            "Export button should exist in HighlightsSheet's trailing slot"
        )

        // The button should be hittable. Whether or not it actually has
        // annotations to export is orthogonal to button presence.
        XCTAssertTrue(
            exportButton.isHittable,
            "Export button should be hittable"
        )
    }

    /// Verifies that NO import button ships — feature #62 / needs-design
    /// #963 defers the import affordance; `HighlightsSheet` shows only
    /// the designed Share/export button.
    func test_verify_feature_35_no_import_button_pending_design_963() throws {
        _ = try openHighlightsSheet()

        // Confirm the export button IS present (sanity — the sheet
        // loaded with its trailing affordance).
        XCTAssertTrue(
            app.buttons[AccessibilityID.annotationsExportButton].waitForExistence(timeout: 5),
            "Export button should exist"
        )

        // The legacy `annotationsImportButton` identifier must NOT
        // resolve — no import affordance ships pending needs-design #963.
        let importButton = app.buttons["annotationsImportButton"]
        XCTAssertFalse(
            importButton.exists,
            "No import button should ship — import is deferred to needs-design #963"
        )
    }
}
