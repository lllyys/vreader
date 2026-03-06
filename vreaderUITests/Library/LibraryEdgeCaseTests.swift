// Purpose: Edge case tests for library view.
// Covers single book display, nil author, zero reading time,
// and long title truncation.
//
// @coordinates-with: LaunchHelper.swift, TestConstants.swift, LibraryView.swift,
//   BookRowView.swift, BookCardView.swift

import XCTest

@MainActor
final class LibraryEdgeCaseTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Verifies a single book displays correctly (no scrolling needed).
    func testSingleBookDisplay() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library view should appear with seeded books"
        )

        // At minimum, with seeded data, at least one book should exist.
        // We verify the library is not empty.
        let emptyState = app.otherElements[AccessibilityID.emptyLibraryState]
        XCTAssertFalse(emptyState.exists, "Library should not show empty state with seeded data")
    }

    /// Verifies books with nil author do not show an author line.
    /// Fixture: "Test Plain Text" has nil author.
    func testBookWithNilAuthorHidesAuthorLine() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Switch to list mode for easier text inspection
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.waitForHittable(timeout: 3), toggle.label == "Switch to list view" {
            toggle.tap()
        }

        // The book "Test Plain Text" has nil author.
        // Its accessibility label should NOT contain "by" prefix.
        // We check that a book element exists whose label does NOT include "by".
        let plainTextBook = app.cells.containing(
            NSPredicate(format: "label CONTAINS 'Test Plain Text'")
        ).firstMatch

        XCTAssertTrue(
            plainTextBook.waitForExistence(timeout: 5),
            "Fixture 'Test Plain Text' should exist in seeded library"
        )

        let label = plainTextBook.label
        // Accessibility label for nil-author books omits "by Author" segment
        XCTAssertFalse(
            label.contains("by "),
            "Book with nil author should not have 'by' in accessibility label, got: \(label)"
        )
    }

    /// Verifies books with zero reading time do not show a reading time label.
    /// Fixture: "Unread Book" has readingTime = 0.
    func testBookWithZeroReadingTimeHidesLabel() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Switch to list mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.waitForHittable(timeout: 3), toggle.label == "Switch to list view" {
            toggle.tap()
        }

        // "Unread Book" has zero reading time.
        // Its accessibility label should not contain "read" time description.
        let unreadBook = app.cells.containing(
            NSPredicate(format: "label CONTAINS 'Unread Book'")
        ).firstMatch

        XCTAssertTrue(
            unreadBook.waitForExistence(timeout: 5),
            "Fixture 'Unread Book' should exist in seeded library"
        )

        let label = unreadBook.label
        // AccessibilityFormatters.accessibleReadingTime returns nil for 0 seconds
        XCTAssertFalse(
            label.contains("minute") || label.contains("hour"),
            "Book with zero reading time should not show time in label, got: \(label)"
        )
    }

    /// Verifies books with very long titles truncate without layout breaks.
    /// Fixture: "A Very Long Book Title That Should Definitely Trigger Truncation..."
    func testLongTitleTruncation() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // The long-title fixture should exist in the library.
        // Key check: the app doesn't crash, and the element's frame fits within screen width.
        let screenWidth = app.windows.firstMatch.frame.width

        // Find any element containing the truncated title
        let longTitleBook = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS 'A Very Long Book Title'")
        ).firstMatch

        XCTAssertTrue(
            longTitleBook.waitForExistence(timeout: 5),
            "Fixture 'A Very Long Book Title' should exist in seeded library"
        )

        XCTAssertLessThanOrEqual(
            longTitleBook.frame.maxX,
            screenWidth,
            "Long title should not extend beyond screen width"
        )
    }
}
