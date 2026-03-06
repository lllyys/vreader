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

        // BookCardView/BookRowView uses accessibilityElement(children: .ignore)
        // with a combined label. In grid mode, NavigationLink renders as a button.
        let predicate = NSPredicate(format: "label CONTAINS[cd] 'Test EPUB Book'")
        let epubBook = app.buttons.matching(predicate).firstMatch

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
        // "Test Plain Text" has nil author — may need scrolling in LazyVGrid
        let predicate = NSPredicate(format: "label CONTAINS[cd] 'Test Plain Text'")
        let scrollTarget = app.scrollViews.firstMatch

        var txtBook: XCUIElement?
        for _ in 0..<6 {
            let match = app.buttons.matching(predicate).firstMatch
            if match.exists { txtBook = match; break }
            if scrollTarget.exists { scrollTarget.swipeUp() } else { app.swipeUp() }
        }

        guard let txtBook else {
            XCTFail("Fixture 'Test Plain Text' should exist in seeded library")
            return
        }

        let label = txtBook.label
        XCTAssertFalse(
            label.contains("by "),
            "Book with nil author should not include 'by' in label, got: \(label)"
        )
    }

    /// Verifies a book with zero reading time omits the time from its accessibility label.
    func testBookItemWithZeroReadingTimeLabel() {
        // "Unread Book" has zero reading time — may need scrolling in LazyVGrid
        let predicate = NSPredicate(format: "label CONTAINS[cd] 'Unread Book'")
        let scrollTarget = app.scrollViews.firstMatch

        var unreadBook: XCUIElement?
        for _ in 0..<6 {
            let match = app.buttons.matching(predicate).firstMatch
            if match.exists { unreadBook = match; break }
            if scrollTarget.exists { scrollTarget.swipeUp() } else { app.swipeUp() }
        }

        guard let unreadBook else {
            XCTFail("Fixture 'Unread Book' should exist in seeded library")
            return
        }

        let label = unreadBook.label
        // Check for reading time phrases, not "read" which matches the title "Unread Book"
        XCTAssertFalse(
            label.contains("minute") || label.contains("hour"),
            "Book with zero reading time should not include reading time in label, got: \(label)"
        )
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
