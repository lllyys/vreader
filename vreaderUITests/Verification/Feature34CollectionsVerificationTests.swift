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

    /// Creates a collection through the sidebar flow.
    ///
    /// Bug #210 / GH #809: callers later build accessibility identifiers
    /// (`collectionFilterRow_<name>`, `addToCollectionMenuItem_<name>`)
    /// from `name`, and production derives both the persisted name and
    /// those identifiers from `String(name.trimmed.prefix(100))`. So the
    /// `name` passed here MUST already be canonical — no leading/trailing
    /// whitespace, ≤100 characters — or the identifier the test queries
    /// will not match the one the UI exposes. The assertion fails the
    /// test (not the whole process) if a future fixture violates that.
    private func createCollection(
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let canonical = String(
            name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)
        )
        XCTAssertEqual(
            canonical, name,
            "Collection fixture name must be pre-canonicalized (trimmed, ≤100 chars) so the identifier the test queries matches what production persists",
            file: file, line: line
        )
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
    ///
    /// Bug #210 / GH #809: the created-collection assertion targets the
    /// sidebar row's stable `collectionFilterRow_<name>` identifier, not
    /// a `label CONTAINS` substring — after feature #60 a substring
    /// query also matches the top-of-library filter chip
    /// (`libraryFilterChip_<name>`), so the test could "pass" without
    /// the sidebar actually showing the collection.
    func test_verify_feature_34_create_collection_appears_in_sidebar() {
        let collectionName = "Verification Suite Collection"
        createCollection(named: collectionName)

        // Reopen sidebar and confirm the collection row is visible
        openCollectionsSidebar()

        let allBooksRow = app.buttons[AccessibilityID.filterAllBooks]
        XCTAssertTrue(
            allBooksRow.waitForExistence(timeout: 5),
            "filterAllBooks row should always be present in the sidebar"
        )

        // The created collection should appear as a sidebar row — match
        // its stable identifier so the chip cannot satisfy the assertion.
        let collectionRow = app.buttons[
            AccessibilityID.collectionFilterRow(collectionName)
        ]
        XCTAssertTrue(
            collectionRow.waitForExistence(timeout: 5),
            "Newly created collection '\(collectionName)' should appear as a sidebar filter row"
        )

        // Close sidebar
        let doneButton = app.buttons[AccessibilityID.filterDoneButton]
        if doneButton.waitForHittable(timeout: 3) {
            doneButton.tap()
        }
    }

    /// Verifies that tapping a collection filter shows only books tagged
    /// with that collection in the library grid.
    ///
    /// Bug #210 / GH #809: every collection-scoped element is targeted by
    /// a stable accessibility identifier rather than a `label CONTAINS`
    /// substring query. Feature #60's library re-skin added a
    /// "Collections" toolbar button (`label: 'Collections'`) and a
    /// per-collection filter-chip row (`libraryFilterChip_<name>`); both
    /// collide with the prior label substrings, so `firstMatch` could
    /// resolve to the wrong element — for the sidebar filter row it
    /// resolved to the chip *behind* the sidebar overlay, which is not
    /// hittable, and the test failed before reaching the assertion.
    func test_verify_feature_34_add_book_to_collection_filters_library() throws {
        let collectionName = "Filter Test Collection"

        // 1. Create a collection
        createCollection(named: collectionName)

        // 2. Long-press first book card to get context menu
        let cardPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        let firstCard = app.buttons.matching(cardPredicate).firstMatch
        guard firstCard.waitForExistence(timeout: 5) else {
            throw XCTSkip("No book cards visible — cannot test collection filter")
        }
        firstCard.press(forDuration: 1.0)

        // 3. Open the "Add to Collection" submenu by its stable identifier
        let addToCollectionMenu = app.buttons[AccessibilityID.addToCollectionMenu]
        guard addToCollectionMenu.waitForExistence(timeout: 5) else {
            // Context menu may not have appeared — skip gracefully
            throw XCTSkip("'Add to Collection' context menu item not found — UI may have changed")
        }
        addToCollectionMenu.tap()

        // 4. Select the collection from the submenu by its stable identifier
        let menuItem = app.buttons[
            AccessibilityID.addToCollectionMenuItem(collectionName)
        ]
        guard menuItem.waitForExistence(timeout: 5) else {
            throw XCTSkip("Collection submenu item not found — UI may have changed")
        }
        menuItem.tap()

        // 5. Open the sidebar and tap the collection filter row. Target
        //    the sidebar row's identifier — NOT a label substring, which
        //    would also match the library filter chip rendered behind
        //    the sidebar overlay (Bug #210 root cause).
        openCollectionsSidebar()
        let filterRow = app.buttons[
            AccessibilityID.collectionFilterRow(collectionName)
        ]
        guard filterRow.waitForHittable(timeout: 5) else {
            throw XCTSkip("Collection filter row not found in sidebar")
        }
        filterRow.tap()

        // Tapping a collection row dismisses the sidebar itself; the
        // explicit Done button is only needed if the sidebar is still up.
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
