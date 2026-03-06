// Purpose: Delete confirmation dialog tests for library view.
// Verifies context menu delete, swipe-to-delete, alert content,
// cancel behavior, and book removal.
//
// @coordinates-with: LaunchHelper.swift, TestConstants.swift, LibraryView.swift

import XCTest

@MainActor
final class DeleteConfirmationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Switches to list mode and waits for list rows to appear.
    private func switchToListMode() {
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        guard toggle.waitForHittable(timeout: 5) else { return }

        if toggle.label == "Switch to list view" {
            toggle.tap()
            let switched = NSPredicate(format: "label == 'Switch to grid view'")
            let expectation = XCTNSPredicateExpectation(predicate: switched, object: toggle)
            _ = XCTWaiter.wait(for: [expectation], timeout: 3)
        }
    }

    /// Finds the first book row element in list mode.
    private func findFirstRow() -> XCUIElement? {
        // In SwiftUI List, NavigationLink items appear as buttons with bookRow_ identifiers
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        let row = app.buttons.matching(rowPredicate).firstMatch
        return row.waitForExistence(timeout: 5) ? row : nil
    }

    /// Returns the count of book rows in the library.
    private func bookRowCount() -> Int {
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        return app.buttons.matching(rowPredicate).count
    }

    // MARK: - Context Menu Delete (Grid Mode)

    /// Verifies long press on a book card reveals context menu with Delete option,
    /// and tapping Delete shows the confirmation alert.
    func testContextMenuDeleteShowsAlert() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Ensure grid mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.waitForHittable(timeout: 3), toggle.label == "Switch to grid view" {
            toggle.tap()
        }

        // Find the first book card in the grid
        let cardPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        let firstCard = app.buttons.matching(cardPredicate).firstMatch
        guard firstCard.waitForHittable(timeout: 5) else {
            XCTFail("No book card found in grid mode")
            return
        }

        // Long press for context menu
        firstCard.press(forDuration: 1.0)

        // Context menu should show Delete option
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(
            deleteButton.waitForExistence(timeout: 3),
            "Context menu should show 'Delete' option"
        )

        // Tap Delete to trigger alert
        deleteButton.tap()

        // Verify confirmation alert appears
        let alert = app.alerts["Delete Book"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 3),
            "Delete confirmation alert should appear"
        )
    }

    /// Verifies the delete confirmation alert contains the expected message.
    func testAlertContainsBookTitle() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        switchToListMode()

        guard let firstRow = findFirstRow() else {
            XCTFail("No book row found in list mode")
            return
        }

        // Swipe to reveal delete action
        firstRow.swipeLeft()

        let deleteAction = app.buttons["Delete"]
        guard deleteAction.waitForHittable(timeout: 3) else {
            XCTFail("Delete action not found after swipe")
            return
        }
        deleteAction.tap()

        // Verify alert exists and contains "This cannot be undone."
        let alert = app.alerts["Delete Book"]
        guard alert.waitForExistence(timeout: 3) else {
            XCTFail("Delete confirmation alert did not appear")
            return
        }

        let messagePredicate = NSPredicate(format: "label CONTAINS 'This cannot be undone'")
        let message = alert.staticTexts.matching(messagePredicate).firstMatch
        XCTAssertTrue(
            message.waitForExistence(timeout: 3),
            "Alert message should contain 'This cannot be undone'"
        )
    }

    /// Verifies Cancel dismisses the alert without removing the book.
    func testCancelDismissesAlert() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        switchToListMode()

        let initialCount = bookRowCount()
        XCTAssertGreaterThan(initialCount, 0, "At least one book should exist")

        guard let firstRow = findFirstRow() else {
            XCTFail("No book row found in list mode")
            return
        }

        // Trigger delete alert
        firstRow.swipeLeft()

        let deleteAction = app.buttons["Delete"]
        guard deleteAction.waitForHittable(timeout: 3) else {
            XCTFail("Delete action not found after swipe")
            return
        }
        deleteAction.tap()

        let alert = app.alerts["Delete Book"]
        guard alert.waitForExistence(timeout: 3) else {
            XCTFail("Delete confirmation alert did not appear")
            return
        }

        // Tap Cancel
        let cancelButton = alert.buttons["Cancel"]
        XCTAssertTrue(cancelButton.exists, "Alert should have Cancel button")
        cancelButton.tap()

        // Alert should dismiss
        XCTAssertTrue(
            alert.waitForDisappearance(timeout: 3),
            "Alert should dismiss after Cancel"
        )

        // Book count should not change
        let finalCount = bookRowCount()
        XCTAssertEqual(
            initialCount, finalCount,
            "Book count should not change after Cancel"
        )
    }

    /// Verifies Delete action removes the book from the list.
    func testDeleteRemovesBookFromList() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        switchToListMode()

        guard let firstRow = findFirstRow() else {
            XCTFail("No book row found in list mode")
            return
        }

        // Capture the identifier of the row to be deleted
        let deletedIdentifier = firstRow.identifier
        XCTAssertFalse(deletedIdentifier.isEmpty, "Row should have an identifier")

        // Trigger delete
        firstRow.swipeLeft()

        let deleteAction = app.buttons["Delete"]
        guard deleteAction.waitForHittable(timeout: 3) else {
            XCTFail("Delete action not found after swipe")
            return
        }
        deleteAction.tap()

        let alert = app.alerts["Delete Book"]
        guard alert.waitForExistence(timeout: 3) else {
            XCTFail("Delete confirmation alert did not appear")
            return
        }

        let confirmDelete = alert.buttons["Delete"]
        XCTAssertTrue(confirmDelete.exists, "Alert should have Delete button")
        confirmDelete.tap()

        // Wait for alert to dismiss
        _ = alert.waitForDisappearance(timeout: 3)

        // Verify the specific deleted row no longer exists
        let deletedRow = app.buttons[deletedIdentifier]
        XCTAssertTrue(
            deletedRow.waitForDisappearance(timeout: 5),
            "Deleted book row should no longer exist"
        )
    }

    // MARK: - Swipe-to-Delete (List Mode)

    /// Verifies swiping left on a book row reveals a Delete button and shows the alert.
    func testSwipeToDeleteShowsAlert() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        switchToListMode()

        guard let firstRow = findFirstRow() else {
            XCTFail("No book row found in list mode")
            return
        }

        // Swipe left to reveal delete action
        firstRow.swipeLeft()

        // Delete button should appear
        let deleteButton = app.buttons["Delete"]
        XCTAssertTrue(
            deleteButton.waitForExistence(timeout: 3),
            "Swipe should reveal Delete button"
        )

        // Tap to show alert
        deleteButton.tap()

        let alert = app.alerts["Delete Book"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 3),
            "Delete confirmation alert should appear after swipe-to-delete"
        )

        // Dismiss the alert to clean up
        let cancelButton = alert.buttons["Cancel"]
        if cancelButton.exists {
            cancelButton.tap()
        }
    }

    // MARK: - Edge Cases

    /// Verifies deleting the last book transitions to empty state.
    func testDeleteLastBookShowsEmptyState() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        switchToListMode()

        // Delete all books one by one (max 20 iterations to prevent infinite loop)
        var maxIterations = 20
        while bookRowCount() > 0, maxIterations > 0 {
            maxIterations -= 1

            guard let row = findFirstRow(), row.waitForHittable(timeout: 3) else { break }

            row.swipeLeft()

            let deleteAction = app.buttons["Delete"]
            guard deleteAction.waitForHittable(timeout: 3) else { break }
            deleteAction.tap()

            let alert = app.alerts["Delete Book"]
            guard alert.waitForExistence(timeout: 3) else { break }

            let confirmDelete = alert.buttons["Delete"]
            guard confirmDelete.exists else { break }
            confirmDelete.tap()

            // Wait for deletion to complete
            _ = alert.waitForDisappearance(timeout: 3)
            _ = row.waitForDisappearance(timeout: 3)
        }

        // After deleting all books, empty state should appear
        let emptyState = app.otherElements[AccessibilityID.emptyLibraryState]
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 5),
            "Empty state should appear after deleting all books"
        )
    }
}
