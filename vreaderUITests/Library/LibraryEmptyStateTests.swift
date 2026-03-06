// Purpose: Tests for library empty state layout and element presence.
// Verifies the empty state container, import button, navigation title,
// and accessibility audit compliance when no books are seeded.
//
// @coordinates-with: LaunchHelper.swift, TestConstants.swift, LibraryView.swift

import XCTest

final class LibraryEmptyStateTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .empty)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Element Presence

    /// Verifies all empty state elements are present: icon, title, description, and import button.
    func testEmptyStateShowsAllElements() {
        let emptyState = app.otherElements[AccessibilityID.emptyLibraryState]
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 5),
            "Empty state container should exist when library is empty"
        )

        // Title text
        let title = app.staticTexts["Your Library is Empty"]
        XCTAssertTrue(title.exists, "Empty state title should be visible")

        // Description text
        let description = app.staticTexts["Import books to start reading. Supports EPUB, PDF, and TXT formats."]
        XCTAssertTrue(description.exists, "Empty state description should be visible")

        // Import button
        let importButton = app.buttons[AccessibilityID.importBooksButton]
        XCTAssertTrue(importButton.exists, "Import Books button should be visible")
    }

    /// Verifies the Import Books button is hittable (visible, enabled, tappable).
    func testImportButtonIsHittable() {
        let importButton = app.buttons[AccessibilityID.importBooksButton]
        XCTAssertTrue(
            importButton.waitForHittable(timeout: 5),
            "Import Books button should be hittable"
        )
    }

    /// Verifies the navigation title is "Library".
    func testNavigationTitleIsLibrary() {
        let navTitle = app.navigationBars["Library"]
        XCTAssertTrue(
            navTitle.waitForExistence(timeout: 5),
            "Navigation title should be 'Library'"
        )
    }

    /// Runs iOS 17 accessibility audit on the empty state.
    func testEmptyStateAccessibilityAudit() {
        let emptyState = app.otherElements[AccessibilityID.emptyLibraryState]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
