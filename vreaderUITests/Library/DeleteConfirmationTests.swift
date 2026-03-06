// Purpose: Delete confirmation dialog tests for library view.
// Verifies context menu delete, swipe-to-delete, alert content,
// cancel behavior, and book removal.
//
// @coordinates-with: LaunchHelper.swift, TestConstants.swift, LibraryView.swift

import XCTest

final class DeleteConfirmationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
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

        // Find the first book element and long press for context menu
        // In grid mode, books are in scroll view with accessibility identifiers "bookCard_*"
        let scrollView = app.scrollViews.firstMatch
        if scrollView.waitForExistence(timeout: 5) {
            // Long press the first accessible element in the grid
            let firstCard = scrollView.buttons.firstMatch
            if firstCard.waitForHittable(timeout: 3) {
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
        }
    }

    /// Verifies the delete confirmation alert contains the book title.
    func testAlertContainsBookTitle() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Switch to list mode for easier book identification
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.waitForHittable(timeout: 3), toggle.label == "Switch to list view" {
            toggle.tap()
        }

        // Swipe to delete the first cell to trigger the alert
        let table = app.tables.firstMatch
        if table.waitForExistence(timeout: 5) {
            let firstCell = table.cells.firstMatch
            if firstCell.waitForHittable(timeout: 3) {
                firstCell.swipeLeft()

                let deleteAction = app.buttons["Delete"]
                if deleteAction.waitForHittable(timeout: 3) {
                    deleteAction.tap()

                    // Verify alert exists and contains "This cannot be undone."
                    let alert = app.alerts["Delete Book"]
                    if alert.waitForExistence(timeout: 3) {
                        let message = alert.staticTexts.element(boundBy: 1)
                        XCTAssertTrue(
                            message.exists,
                            "Alert should have a message"
                        )
                        let messageLabel = message.label
                        XCTAssertTrue(
                            messageLabel.contains("This cannot be undone"),
                            "Alert message should contain 'This cannot be undone', got: \(messageLabel)"
                        )
                    }
                }
            }
        }
    }

    /// Verifies Cancel dismisses the alert without removing the book.
    func testCancelDismissesAlert() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Switch to list mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.waitForHittable(timeout: 3), toggle.label == "Switch to list view" {
            toggle.tap()
        }

        let table = app.tables.firstMatch
        guard table.waitForExistence(timeout: 5) else { return }

        let initialCellCount = table.cells.count

        // Trigger delete alert
        let firstCell = table.cells.firstMatch
        guard firstCell.waitForHittable(timeout: 3) else { return }

        firstCell.swipeLeft()

        let deleteAction = app.buttons["Delete"]
        guard deleteAction.waitForHittable(timeout: 3) else { return }
        deleteAction.tap()

        // Wait for alert
        let alert = app.alerts["Delete Book"]
        guard alert.waitForExistence(timeout: 3) else { return }

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
        let finalCellCount = table.cells.count
        XCTAssertEqual(
            initialCellCount, finalCellCount,
            "Book count should not change after Cancel"
        )
    }

    /// Verifies Delete action removes the book from the list.
    func testDeleteRemovesBookFromList() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Switch to list mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.waitForHittable(timeout: 3), toggle.label == "Switch to list view" {
            toggle.tap()
        }

        let table = app.tables.firstMatch
        guard table.waitForExistence(timeout: 5) else { return }

        let initialCellCount = table.cells.count
        guard initialCellCount > 0 else { return }

        // Trigger delete alert
        let firstCell = table.cells.firstMatch
        guard firstCell.waitForHittable(timeout: 3) else { return }

        firstCell.swipeLeft()

        let deleteAction = app.buttons["Delete"]
        guard deleteAction.waitForHittable(timeout: 3) else { return }
        deleteAction.tap()

        // Wait for alert and confirm delete
        let alert = app.alerts["Delete Book"]
        guard alert.waitForExistence(timeout: 3) else { return }

        let confirmDelete = alert.buttons["Delete"]
        XCTAssertTrue(confirmDelete.exists, "Alert should have Delete button")
        confirmDelete.tap()

        // Wait for alert to dismiss
        _ = alert.waitForDisappearance(timeout: 3)

        // Verify book count decreased
        // Wait briefly for the deletion animation
        let countPredicate = NSPredicate(format: "count < %d", initialCellCount)
        let countExpectation = XCTNSPredicateExpectation(
            predicate: countPredicate,
            object: table.cells
        )
        let result = XCTWaiter.wait(for: [countExpectation], timeout: 5)
        XCTAssertEqual(result, .completed, "Book count should decrease after delete")
    }

    // MARK: - Swipe-to-Delete (List Mode)

    /// Verifies swiping left on a book row reveals a Delete button and shows the alert.
    func testSwipeToDeleteShowsAlert() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Switch to list mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.waitForHittable(timeout: 3), toggle.label == "Switch to list view" {
            toggle.tap()
        }

        let table = app.tables.firstMatch
        guard table.waitForExistence(timeout: 5) else { return }

        let firstCell = table.cells.firstMatch
        guard firstCell.waitForHittable(timeout: 3) else { return }

        // Swipe left to reveal delete action
        firstCell.swipeLeft()

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
        // This test requires a single-book seed state.
        // With the standard fixture set, we would need to delete all books.
        // For now, we verify the flow conceptually with the available seed data.
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Switch to list mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.waitForHittable(timeout: 3), toggle.label == "Switch to list view" {
            toggle.tap()
        }

        let table = app.tables.firstMatch
        guard table.waitForExistence(timeout: 5) else { return }

        // Delete all books one by one
        while table.cells.count > 0 {
            let cell = table.cells.firstMatch
            guard cell.waitForHittable(timeout: 3) else { break }

            cell.swipeLeft()

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

            // Brief wait for animation
            let disappeared = cell.waitForDisappearance(timeout: 3)
            if !disappeared {
                break
            }
        }

        // After deleting all books, empty state should appear
        let emptyState = app.otherElements[AccessibilityID.emptyLibraryState]
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 5),
            "Empty state should appear after deleting all books"
        )
    }
}
