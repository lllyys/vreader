// Purpose: UI tests for the OPDS catalog browser surface (feature #36).
// Verifies the catalogs sheet presents from the library toolbar globe
// icon, surfaces the toolbar Add Catalog entry point, and dismisses
// cleanly via Done. Assertions stay state-invariant so the suite is
// robust whether the user has zero catalogs (empty-state shape) or
// any catalogs already saved — OPDS catalogs are persisted in
// UserDefaults under "opds.savedCatalogs" and that store is NOT
// reset by `--uitesting` (which only swaps the SwiftData model store
// for an in-memory container).
//
// @coordinates-with: vreader/Views/OPDS/OPDSCatalogListView.swift,
//   vreader/Views/LibraryView.swift, vreader/Services/OPDS/OPDSClient.swift

import XCTest

@MainActor
final class OPDSCatalogListTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func openOPDSCatalogs() {
        let toolbarButton = app.buttons["opdsCatalogsToolbarButton"]
        XCTAssertTrue(
            toolbarButton.waitForHittable(timeout: 5),
            "OPDS catalogs toolbar button should be hittable"
        )
        toolbarButton.tap()
    }

    // MARK: - Sheet Presentation

    func testOPDSCatalogsSheetOpens() {
        openOPDSCatalogs()

        let title = app.navigationBars["OPDS Catalogs"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "OPDS catalogs sheet should present with navigation title 'OPDS Catalogs'"
        )
    }

    // MARK: - Toolbar Add Catalog (state-invariant)

    func testOPDSToolbarAddCatalogButton() {
        openOPDSCatalogs()

        // The toolbar `+` button is always present, regardless of
        // whether there are saved catalogs — the empty state's
        // prominent button is the call-to-action; this is the
        // discoverable secondary entry.
        let toolbarAdd = app.buttons["opdsAddCatalog"]
        XCTAssertTrue(
            toolbarAdd.waitForHittable(timeout: 5),
            "Toolbar 'Add catalog' (+) button should be hittable"
        )
    }

    // MARK: - Done Dismisses

    func testOPDSCatalogsSheetDismisses() {
        openOPDSCatalogs()

        let doneButton = app.buttons["opdsCatalogsDoneButton"]
        XCTAssertTrue(
            doneButton.waitForHittable(timeout: 5),
            "Done button should be hittable"
        )
        doneButton.tap()

        let title = app.navigationBars["OPDS Catalogs"]
        XCTAssertTrue(
            title.waitForDisappearance(timeout: 5),
            "OPDS sheet should dismiss after Done"
        )

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library should be visible after dismissing the OPDS sheet"
        )
    }

    // MARK: - Accessibility Audit

    func testOPDSCatalogsAccessibilityAudit() {
        openOPDSCatalogs()

        let title = app.navigationBars["OPDS Catalogs"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }

    // MARK: - Empty State (with --reset-preferences, bug #152 / GH #426)

    /// Verifies the empty-state shape is reachable in a deterministic
    /// way using the `--reset-preferences` launch arg (bug #152 fix).
    /// Without this flag the test would flake based on residual
    /// UserDefaults state from prior simulator sessions, which is why
    /// the rest of this suite uses state-invariant assertions only.
    func testOPDSEmptyStateWithResetPreferences() {
        // Re-launch with the new opt-in flag so `opds.savedCatalogs`
        // is wiped before the OPDS view ever reads it.
        app = launchApp(seed: .books, resetPreferences: true)

        let toolbarButton = app.buttons["opdsCatalogsToolbarButton"]
        XCTAssertTrue(toolbarButton.waitForHittable(timeout: 5))
        toolbarButton.tap()

        let emptyHeading = app.staticTexts["No OPDS Catalogs"]
        XCTAssertTrue(
            emptyHeading.waitForExistence(timeout: 5),
            "Empty state heading should appear when OPDS catalogs are wiped via --reset-preferences"
        )

        let emptyDescription = app.staticTexts["Add an OPDS catalog server to browse and download books."]
        XCTAssertTrue(
            emptyDescription.waitForExistence(timeout: 3),
            "Empty state descriptive copy should render alongside the heading"
        )

        // The empty-state's prominent Add Catalog button is queried by
        // its label rather than its accessibilityIdentifier — iOS 26.4
        // SwiftUI propagates the outer VStack's `opdsEmptyState`
        // identifier down to descendant elements, shadowing
        // `opdsAddCatalogEmpty` on the inner Button. Same propagation
        // pattern as bug #150 (txtReaderContainer on UITextView).
        // Querying by label text is robust to that quirk and still
        // proves the call-to-action is reachable to the user.
        let addCatalogPredicate = NSPredicate(format: "label == %@", "Add Catalog")
        let addCatalogButton = app.buttons.matching(addCatalogPredicate).firstMatch
        XCTAssertTrue(
            addCatalogButton.waitForExistence(timeout: 3),
            "Empty-state Add Catalog button should be reachable when catalogs UserDefaults is wiped"
        )
        XCTAssertTrue(
            addCatalogButton.isHittable,
            "Empty-state Add Catalog button should be hittable"
        )
    }
}
