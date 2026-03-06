// Purpose: Tests for library populated state layout and element presence.
// Verifies book items, view mode toggle, sort picker, grid/list switching,
// and sort menu options when books are seeded.
//
// @coordinates-with: LaunchHelper.swift, TestConstants.swift, LibraryView.swift,
//   BookCardView.swift, BookRowView.swift

import XCTest

@MainActor
final class LibraryPopulatedTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Element Presence

    /// Verifies the populated library shows book items and not the empty state.
    func testPopulatedStateShowsBooks() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library view should appear"
        )

        // Empty state should NOT be visible
        let emptyState = app.otherElements[AccessibilityID.emptyLibraryState]
        XCTAssertFalse(emptyState.exists, "Empty state should not appear when books are seeded")
    }

    /// Verifies the view mode toggle button exists.
    func testViewModeToggleExists() {
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5),
            "View mode toggle should exist in toolbar"
        )
    }

    /// Verifies the sort picker button exists.
    func testSortPickerExists() {
        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(
            sortPicker.waitForExistence(timeout: 5),
            "Sort picker should exist in toolbar"
        )
    }

    /// Verifies grid mode shows BookCardView items.
    func testGridModeShowsCards() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // In grid mode (default), check for card-style elements.
        // Cards should have accessibility labels from AccessibilityFormatters.
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        // If currently in list mode, switch to grid
        if toggle.label == "Switch to grid view" {
            toggle.tap()
            // Wait for toggle label to update
            let predicate = NSPredicate(format: "label == 'Switch to list view'")
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
            _ = XCTWaiter.wait(for: [expectation], timeout: 3)
        }

        // Verify at least one book element exists in the scroll view
        let scrollViews = app.scrollViews
        XCTAssertTrue(scrollViews.firstMatch.waitForExistence(timeout: 5),
                       "Grid mode should show a scroll view with book cards")

        // Verify at least one book card element exists
        let cardPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        let card = app.buttons.matching(cardPredicate).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5),
                       "At least one book card should exist in grid mode")
    }

    /// Verifies list mode shows BookRowView items.
    func testListModeShowsRows() {
        // Switch to list mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.waitForHittable(timeout: 5))

        // Ensure we are in grid mode first, then switch
        if toggle.label == "Switch to list view" {
            toggle.tap()
            // Wait for toggle label to update
            let predicate = NSPredicate(format: "label == 'Switch to grid view'")
            let expectation = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
            _ = XCTWaiter.wait(for: [expectation], timeout: 3)
        }

        // Verify list elements appear (SwiftUI List may be table or collectionView)
        let table = app.tables.firstMatch
        let collection = app.collectionViews.firstMatch
        let listFound = table.waitForExistence(timeout: 3) || collection.waitForExistence(timeout: 3)
        XCTAssertTrue(listFound,
                       "List mode should show a table/list with book rows")

        // Verify book rows exist via identifier pattern
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        let row = app.buttons.matching(rowPredicate).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                       "At least one book row should exist in list mode")
    }

    // MARK: - Interactions

    /// Verifies tapping the view mode toggle switches between grid and list layouts.
    func testViewModeToggleSwitchesLayout() {
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.waitForHittable(timeout: 5))

        let initialLabel = toggle.label

        // Tap to switch
        toggle.tap()

        // Verify label changed
        let expectedLabel = initialLabel == "Switch to list view"
            ? "Switch to grid view"
            : "Switch to list view"

        let predicate = NSPredicate(format: "label == %@", expectedLabel)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: toggle)
        let result = XCTWaiter.wait(for: [expectation], timeout: 3)
        XCTAssertEqual(result, .completed,
                       "Toggle label should change from '\(initialLabel)' to '\(expectedLabel)'")
    }

    /// Verifies the sort picker shows all sort options when tapped.
    func testSortPickerShowsAllOptions() {
        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(sortPicker.waitForHittable(timeout: 5))

        sortPicker.tap()

        // Verify sort options appear in the menu
        let titleOption = app.buttons["Title"]
        XCTAssertTrue(
            titleOption.waitForExistence(timeout: 3),
            "Sort menu should show 'Title' option"
        )

        let dateAddedOption = app.buttons["Date Added"]
        XCTAssertTrue(dateAddedOption.exists, "Sort menu should show 'Date Added' option")

        let lastReadOption = app.buttons["Last Read"]
        XCTAssertTrue(lastReadOption.exists, "Sort menu should show 'Last Read' option")

        let readingTimeOption = app.buttons["Reading Time"]
        XCTAssertTrue(readingTimeOption.exists, "Sort menu should show 'Reading Time' option")
    }

    /// Runs iOS 17 accessibility audit on the populated state.
    func testPopulatedStateAccessibilityAudit() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
