// Purpose: Dark mode rendering tests for the library view.
// Verifies app launches without crashes in both dark and light modes,
// and that key elements are present and visible in each scheme.
//
// @coordinates-with: LaunchHelper.swift, TestConstants.swift, LibraryView.swift

import XCTest

@MainActor
final class LibraryDarkModeTests: XCTestCase {
    var app: XCUIApplication!

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Dark Mode

    /// Verifies the app launches in dark mode without crashing.
    func testDarkModeLaunchDoesNotCrash() {
        app = launchApp(seed: .books, colorScheme: .dark)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library view should appear in dark mode"
        )
    }

    /// Verifies the empty state is visible and all elements present in dark mode.
    func testDarkModeEmptyStateVisible() {
        app = launchApp(seed: .empty, colorScheme: .dark)

        let emptyState = app.otherElements[AccessibilityID.emptyLibraryState]
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 5),
            "Empty state should be visible in dark mode"
        )

        let importButton = app.buttons[AccessibilityID.importBooksButton]
        XCTAssertTrue(importButton.exists, "Import button should be visible in dark mode")

        let title = app.staticTexts["Your Library is Empty"]
        XCTAssertTrue(title.exists, "Empty state title should be visible in dark mode")
    }

    /// Verifies the populated state is visible with books in dark mode.
    func testDarkModePopulatedStateVisible() {
        app = launchApp(seed: .books, colorScheme: .dark)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.exists, "View mode toggle should be visible in dark mode")

        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(sortPicker.exists, "Sort picker should be visible in dark mode")
    }

    // MARK: - Light Mode Baseline

    /// Verifies light mode as baseline for comparison.
    func testLightModeBaseline() {
        app = launchApp(seed: .books, colorScheme: .light)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library view should appear in light mode"
        )

        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.exists, "View mode toggle should be visible in light mode")

        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(sortPicker.exists, "Sort picker should be visible in light mode")
    }

    // MARK: - Accessibility Audits

    /// Runs accessibility audit in dark mode.
    func testDarkModeAccessibilityAudit() {
        app = launchApp(seed: .books, colorScheme: .dark)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }

    /// Runs accessibility audit in light mode.
    func testLightModeAccessibilityAudit() {
        app = launchApp(seed: .books, colorScheme: .light)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
