// Purpose: Dynamic Type scaling tests for library view.
// Verifies layout integrity across xSmall, default, xxxLarge, and AX5 sizes.
// Checks for element overflow and accessibility audit compliance.
//
// @coordinates-with: LaunchHelper.swift, TestConstants.swift, LibraryView.swift

import XCTest

final class LibraryDynamicTypeTests: XCTestCase {
    var app: XCUIApplication!

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Layout at Different Sizes

    /// Verifies all critical elements are present at xSmall Dynamic Type.
    func testLayoutAtXSmall() {
        app = launchApp(seed: .books, dynamicType: .xSmall)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library view should appear at xSmall Dynamic Type"
        )

        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.exists, "View mode toggle should be present at xSmall")

        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(sortPicker.exists, "Sort picker should be present at xSmall")
    }

    /// Verifies all critical elements are present at default Dynamic Type.
    func testLayoutAtDefault() {
        app = launchApp(seed: .books, dynamicType: .default)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library view should appear at default Dynamic Type"
        )

        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.exists, "View mode toggle should be present at default")

        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(sortPicker.exists, "Sort picker should be present at default")
    }

    /// Verifies all critical elements are present at xxxLarge Dynamic Type.
    func testLayoutAtXXXLarge() {
        app = launchApp(seed: .books, dynamicType: .xxxLarge)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library view should appear at xxxLarge Dynamic Type"
        )

        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.exists, "View mode toggle should be present at xxxLarge")

        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(sortPicker.exists, "Sort picker should be present at xxxLarge")
    }

    /// Verifies all critical elements are present at AX5 (largest accessibility size).
    func testLayoutAtAX5() {
        app = launchApp(seed: .books, dynamicType: .ax5)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(
            libraryView.waitForExistence(timeout: 5),
            "Library view should appear at AX5 Dynamic Type"
        )

        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.exists, "View mode toggle should be present at AX5")

        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(sortPicker.exists, "Sort picker should be present at AX5")
    }

    // MARK: - Overflow Detection

    /// Verifies no elements extend beyond screen width at AX5.
    func testNoElementOverflowAtAX5() {
        app = launchApp(seed: .books, dynamicType: .ax5)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        let screenWidth = app.windows.firstMatch.frame.width

        // Check toolbar buttons
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        if toggle.exists {
            XCTAssertLessThanOrEqual(
                toggle.frame.maxX, screenWidth,
                "View mode toggle should not overflow screen width at AX5"
            )
        }

        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        if sortPicker.exists {
            XCTAssertLessThanOrEqual(
                sortPicker.frame.maxX, screenWidth,
                "Sort picker should not overflow screen width at AX5"
            )
        }
    }

    // MARK: - Accessibility Audit

    /// Runs accessibility audit at AX5 Dynamic Type size.
    func testAccessibilityAuditAtAX5() {
        app = launchApp(seed: .books, dynamicType: .ax5)

        let libraryView = app.otherElements[AccessibilityID.libraryView]
        XCTAssertTrue(libraryView.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
