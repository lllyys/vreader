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

    // MARK: - Helpers

    /// Finds a book card by label substring, scrolling down to load lazy elements.
    private func findCard(labelContaining text: String) -> XCUIElement? {
        let predicate = NSPredicate(format: "label CONTAINS[cd] %@", text)
        let scrollTarget = app.scrollViews.firstMatch

        for _ in 0..<6 {
            let match = app.buttons.matching(predicate).firstMatch
            if match.exists { return match }
            if scrollTarget.exists {
                scrollTarget.swipeUp()
            } else {
                app.swipeUp()
            }
        }
        return nil
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

        guard let plainTextBook = findCard(labelContaining: "Test Plain Text") else {
            XCTFail("Fixture 'Test Plain Text' should exist in seeded library")
            return
        }

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

        guard let unreadBook = findCard(labelContaining: "Unread Book") else {
            XCTFail("Fixture 'Unread Book' should exist in seeded library")
            return
        }

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

        let screenWidth = app.windows.firstMatch.frame.width

        // May need scrolling in LazyVGrid to find the long-title fixture
        guard let longTitleBook = findCard(labelContaining: "A Very Long Book Title") else {
            XCTFail("Fixture 'A Very Long Book Title' should exist in seeded library")
            return
        }

        XCTAssertLessThanOrEqual(
            longTitleBook.frame.maxX,
            screenWidth,
            "Long title should not extend beyond screen width"
        )
    }
}
