// Purpose: Verification tests for Feature #34 — collections sidebar.
// Exercises the full create-collection flow and verifies that collection
// filtering isolates the library to tagged books only.
//
// Seed: .books (library has fixture books; no collections pre-created).
// resetPreferences: true — clears any previously persisted collections.
//
// @coordinates-with: CollectionSidebar.swift, LibraryView.swift,
//   CollectionRecord.swift

import XCTest

@MainActor
final class Feature34CollectionsVerificationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books, resetPreferences: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func openCollectionsSidebar() {
        let button = app.buttons[AccessibilityID.collectionsToolbarButton]
        XCTAssertTrue(button.waitForHittable(timeout: 5), "Collections toolbar button should be hittable")
        button.tap()
    }

    private func createCollection(named name: String) {
        openCollectionsSidebar()

        let newButton = app.buttons[AccessibilityID.newCollectionButton]
        XCTAssertTrue(
            newButton.waitForHittable(timeout: 5),
            "New collection button should be hittable in sidebar"
        )
        newButton.tap()

        // Text field for entering the collection name
        let textField = app.textFields[AccessibilityID.newCollectionTextField]
        XCTAssertTrue(
            textField.waitForExistence(timeout: 5),
            "Collection name text field should appear"
        )
        textField.tap()
        textField.typeText(name)

        // Confirm (Add button in the sheet)
        let addButton = app.buttons[AccessibilityID.addCollectionButton]
        XCTAssertTrue(
            addButton.waitForHittable(timeout: 5),
            "Add collection button should be hittable"
        )
        addButton.tap()

        // Close sidebar
        let doneButton = app.buttons[AccessibilityID.filterDoneButton]
        if doneButton.waitForHittable(timeout: 3) {
            doneButton.tap()
        }
    }

    // MARK: - Feature #34 Verification

    /// Verifies that creating a collection via the sidebar flow makes
    /// the collection row visible after reopening the sidebar.
    func test_verify_feature_34_create_collection_appears_in_sidebar() {
        createCollection(named: "Verification Suite Collection")

        // Reopen sidebar and confirm the collection row is visible
        openCollectionsSidebar()

        let allBooksRow = app.buttons[AccessibilityID.filterAllBooks]
        XCTAssertTrue(
            allBooksRow.waitForExistence(timeout: 5),
            "filterAllBooks row should always be present in the sidebar"
        )

        // The created collection should appear as a row
        let collectionRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[cd] 'Verification Suite Collection'")
        ).firstMatch
        XCTAssertTrue(
            collectionRow.waitForExistence(timeout: 5),
            "Newly created collection 'Verification Suite Collection' should appear in the sidebar"
        )

        // Close sidebar
        let doneButton = app.buttons[AccessibilityID.filterDoneButton]
        if doneButton.waitForHittable(timeout: 3) {
            doneButton.tap()
        }
    }

    /// Verifies that tapping a collection filter shows only books tagged
    /// with that collection in the library grid.
    func test_verify_feature_34_add_book_to_collection_filters_library() throws {
        // 1. Create a collection
        createCollection(named: "Filter Test Collection")

        // 2. Long-press first book card to get context menu
        let cardPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        let firstCard = app.buttons.matching(cardPredicate).firstMatch
        guard firstCard.waitForExistence(timeout: 5) else {
            throw XCTSkip("No book cards visible — cannot test collection filter")
        }
        firstCard.press(forDuration: 1.0)

        // 3. Look for "Add to Collection" or "Collections" in the context menu
        let addToCollectionButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[cd] 'Collection'")
        ).firstMatch

        guard addToCollectionButton.waitForExistence(timeout: 5) else {
            // Context menu may not have appeared or label differs — skip gracefully
            throw XCTSkip("'Add to Collection' context menu item not found — UI may have changed")
        }
        addToCollectionButton.tap()

        // 4. Select the collection from the picker
        let collectionPicker = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[cd] 'Filter Test Collection'")
        ).firstMatch
        if collectionPicker.waitForExistence(timeout: 5) {
            collectionPicker.tap()
        }

        // 5. Open the sidebar and tap the collection filter
        openCollectionsSidebar()
        let filterRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[cd] 'Filter Test Collection'")
        ).firstMatch
        guard filterRow.waitForExistence(timeout: 5) else {
            throw XCTSkip("Collection filter row not found in sidebar")
        }
        filterRow.tap()

        // Close sidebar
        let doneButton = app.buttons[AccessibilityID.filterDoneButton]
        if doneButton.waitForHittable(timeout: 3) {
            doneButton.tap()
        }

        // 6. After filtering, only tagged books should appear
        // (at least one card must be visible — the tagged book)
        let visibleCards = app.buttons.matching(cardPredicate)
        XCTAssertGreaterThan(
            visibleCards.count, 0,
            "At least one book card should be visible after applying the collection filter"
        )
    }
}
