// Purpose: UI tests for the Collections sidebar surface (feature #34).
// Verifies the sheet presents from the library toolbar, exposes the
// "All Books" filter and the New Collection entry point, and dismisses
// cleanly via Done. Each test starts with seed: .books so the library
// has fixture rows but no collections — the sheet renders in its
// empty-state shape (no collection / tag / series sections present).
//
// @coordinates-with: vreader/Views/Library/CollectionSidebar.swift,
//   vreader/Views/LibraryView.swift, vreader/Models/CollectionRecord.swift

import XCTest

@MainActor
final class CollectionSidebarTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func openCollectionsSidebar() {
        let toolbarButton = app.buttons["collectionsToolbarButton"]
        XCTAssertTrue(
            toolbarButton.waitForHittable(timeout: 5),
            "Collections toolbar button should be hittable"
        )
        toolbarButton.tap()
    }

    // MARK: - Sheet Presentation

    func testCollectionsSheetOpens() {
        openCollectionsSidebar()

        // The sheet is a NavigationStack with title "Filter".
        let title = app.navigationBars["Filter"]
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "Collections sidebar should present with navigation title 'Filter'"
        )
    }

    // MARK: - Default Filter Row

    func testCollectionsShowsAllBooksFilter() {
        openCollectionsSidebar()

        let allBooks = app.buttons["filterAllBooks"]
        XCTAssertTrue(
            allBooks.waitForExistence(timeout: 5),
            "filterAllBooks row should be present in the sidebar"
        )
        XCTAssertTrue(
            allBooks.isHittable,
            "filterAllBooks row should be hittable so the user can return to the unfiltered view"
        )
    }

    // MARK: - New Collection Entry Point

    func testCollectionsShowsNewCollectionButton() {
        openCollectionsSidebar()

        let newCollection = app.buttons["newCollectionButton"]
        XCTAssertTrue(
            newCollection.waitForExistence(timeout: 5),
            "newCollectionButton should be present in the sidebar empty state"
        )
        XCTAssertTrue(
            newCollection.isHittable,
            "newCollectionButton should be hittable"
        )
    }

    // MARK: - Inline Add Field

    func testCollectionsNewCollectionExposesTextField() {
        openCollectionsSidebar()

        let newCollection = app.buttons["newCollectionButton"]
        XCTAssertTrue(newCollection.waitForHittable(timeout: 5))
        newCollection.tap()

        // Tapping flips the row into an inline TextField + Add button.
        let textField = app.textFields["newCollectionTextField"]
        XCTAssertTrue(
            textField.waitForExistence(timeout: 3),
            "newCollectionTextField should appear after tapping newCollectionButton"
        )

        let addButton = app.buttons["addCollectionButton"]
        XCTAssertTrue(
            addButton.waitForExistence(timeout: 3),
            "addCollectionButton should appear alongside the text field"
        )
        // Add button is gated on a non-empty trimmed name — with no
        // input it must be disabled so the user cannot create a blank
        // collection.
        XCTAssertFalse(
            addButton.isEnabled,
            "addCollectionButton should be disabled until a non-empty name is typed"
        )
    }

    // MARK: - Done Dismisses

    func testCollectionsSheetDismisses() {
        openCollectionsSidebar()

        let doneButton = app.buttons["filterDoneButton"]
        XCTAssertTrue(
            doneButton.waitForHittable(timeout: 5),
            "filterDoneButton should be hittable"
        )
        doneButton.tap()

        // After dismiss, the library should be visible again and the
        // navigation bar 'Filter' should be gone.
        let title = app.navigationBars["Filter"]
        XCTAssertTrue(
            title.waitForDisappearance(timeout: 5),
            "Sidebar should dismiss after Done"
        )

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library should be visible after dismissing the sidebar"
        )
    }

    // MARK: - Accessibility Audit

    func testCollectionsSheetAccessibilityAudit() {
        openCollectionsSidebar()

        let title = app.navigationBars["Filter"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
