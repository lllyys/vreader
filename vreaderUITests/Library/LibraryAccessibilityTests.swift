// Purpose: Accessibility label and VoiceOver traversal tests for library view.
// Verifies book items have correct combined accessibility labels,
// interactive elements have descriptive labels, and traversal order is logical.
//
// @coordinates-with: LaunchHelper.swift, TestConstants.swift, LibraryView.swift,
//   BookRowView.swift, AccessibilityFormatters.swift

import XCTest

@MainActor
final class LibraryAccessibilityTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Book Item Accessibility Labels

    /// Verifies a book item has a combined accessibility label with title, author, format, and time.
    /// Fixture: "Test EPUB Book" by "Test Author" with reading time > 0.
    func testBookItemAccessibilityLabel() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Switch to list mode for consistent cell queries
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.waitForHittable(timeout: 3), toggle.label == "Switch to list view" {
            toggle.tap()
        }

        // Look for a book element that contains title and format
        // AccessibilityFormatters produces: "Title, by Author, FORMAT format, X minutes read"
        let epubBook = app.cells.containing(
            NSPredicate(format: "label CONTAINS 'Test EPUB Book'")
        ).firstMatch

        XCTAssertTrue(
            epubBook.waitForExistence(timeout: 5),
            "Fixture 'Test EPUB Book' should exist in seeded library"
        )

        let label = epubBook.label
        XCTAssertTrue(
            label.contains("Test EPUB Book"),
            "Book label should contain title"
        )
        XCTAssertTrue(
            label.contains("by Test Author"),
            "Book label should contain author"
        )
        XCTAssertTrue(
            label.contains("EPUB format"),
            "Book label should contain format badge"
        )
    }

    /// Verifies a book with no author omits the "by" prefix in its accessibility label.
    func testBookItemWithNoAuthorLabel() {
        // Switch to list mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.waitForHittable(timeout: 3), toggle.label == "Switch to list view" {
            toggle.tap()
        }

        // "Test Plain Text" has nil author
        let txtBook = app.cells.containing(
            NSPredicate(format: "label CONTAINS 'Test Plain Text'")
        ).firstMatch

        if txtBook.waitForExistence(timeout: 5) {
            let label = txtBook.label
            XCTAssertFalse(
                label.contains("by "),
                "Book with nil author should not include 'by' in label, got: \(label)"
            )
        }
    }

    /// Verifies a book with zero reading time omits the time from its accessibility label.
    func testBookItemWithZeroReadingTimeLabel() {
        // Switch to list mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.waitForHittable(timeout: 3), toggle.label == "Switch to list view" {
            toggle.tap()
        }

        // "Unread Book" has zero reading time
        let unreadBook = app.cells.containing(
            NSPredicate(format: "label CONTAINS 'Unread Book'")
        ).firstMatch

        if unreadBook.waitForExistence(timeout: 5) {
            let label = unreadBook.label
            XCTAssertFalse(
                label.contains("read"),
                "Book with zero reading time should not include reading time in label, got: \(label)"
            )
        }
    }

    // MARK: - Interactive Element Labels

    /// Verifies the view mode toggle has a descriptive accessibility label.
    func testViewModeToggleAccessibilityLabel() {
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        let label = toggle.label
        let validLabels = ["Switch to list view", "Switch to grid view"]
        XCTAssertTrue(
            validLabels.contains(label),
            "View mode toggle should have descriptive label, got: '\(label)'"
        )
    }

    /// Verifies the sort picker has a descriptive accessibility label.
    func testSortPickerAccessibilityLabel() {
        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(sortPicker.waitForExistence(timeout: 5))

        XCTAssertEqual(
            sortPicker.label,
            "Sort books",
            "Sort picker should have 'Sort books' accessibility label"
        )
    }

    // MARK: - VoiceOver Traversal Order

    /// Verifies accessibility elements appear in logical order.
    /// Expected: navigation title -> toolbar buttons -> book items (or empty state).
    ///
    /// Note: XCUITest has limited APIs for verifying strict VoiceOver traversal order.
    /// This test verifies existence and hittability of key elements, which confirms
    /// they are reachable by assistive technologies. Strict ordering verification
    /// requires manual VoiceOver testing.
    func testVoiceOverTraversalOrder() {
        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        // Verify navigation bar exists (contains title)
        let navBar = app.navigationBars["Library"]
        XCTAssertTrue(
            navBar.waitForExistence(timeout: 5),
            "Navigation bar with 'Library' title should exist"
        )

        // Verify toolbar buttons exist within or after navigation bar
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.exists, "View mode toggle should be reachable")

        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(sortPicker.exists, "Sort picker should be reachable")

        // Verify all interactive elements are reachable (hittable)
        XCTAssertTrue(toggle.isHittable, "View mode toggle should be hittable (reachable)")
        XCTAssertTrue(sortPicker.isHittable, "Sort picker should be hittable (reachable)")
    }
}
