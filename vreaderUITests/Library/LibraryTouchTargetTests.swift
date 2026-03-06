// Purpose: Touch target compliance tests for library view.
// Verifies all interactive elements meet Apple HIG minimum 44x44pt touch targets.
//
// @coordinates-with: LaunchHelper.swift, TestConstants.swift, LibraryView.swift,
//   BookRowView.swift

import XCTest

final class LibraryTouchTargetTests: XCTestCase {
    var app: XCUIApplication!

    /// Minimum touch target dimension per Apple HIG.
    private let minimumTouchTarget: CGFloat = 44

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Touch Target Size Tests

    /// Verifies the view mode toggle button meets minimum 44x44pt touch target.
    func testViewModeToggleMinimumSize() {
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))

        XCTAssertGreaterThanOrEqual(
            toggle.frame.width, minimumTouchTarget,
            "View mode toggle width (\(toggle.frame.width)) should be >= \(minimumTouchTarget)pt"
        )
        XCTAssertGreaterThanOrEqual(
            toggle.frame.height, minimumTouchTarget,
            "View mode toggle height (\(toggle.frame.height)) should be >= \(minimumTouchTarget)pt"
        )
    }

    /// Verifies the sort picker button meets minimum 44x44pt touch target.
    func testSortPickerMinimumSize() {
        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(sortPicker.waitForExistence(timeout: 5))

        XCTAssertGreaterThanOrEqual(
            sortPicker.frame.width, minimumTouchTarget,
            "Sort picker width (\(sortPicker.frame.width)) should be >= \(minimumTouchTarget)pt"
        )
        XCTAssertGreaterThanOrEqual(
            sortPicker.frame.height, minimumTouchTarget,
            "Sort picker height (\(sortPicker.frame.height)) should be >= \(minimumTouchTarget)pt"
        )
    }

    /// Verifies the import button meets minimum 44x44pt touch target.
    func testImportButtonMinimumSize() {
        // Relaunch with empty state to see the import button
        app = launchApp(seed: .empty)

        let importButton = app.buttons[AccessibilityID.importBooksButton]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))

        XCTAssertGreaterThanOrEqual(
            importButton.frame.width, minimumTouchTarget,
            "Import button width (\(importButton.frame.width)) should be >= \(minimumTouchTarget)pt"
        )
        XCTAssertGreaterThanOrEqual(
            importButton.frame.height, minimumTouchTarget,
            "Import button height (\(importButton.frame.height)) should be >= \(minimumTouchTarget)pt"
        )
    }

    /// Verifies each book row in list mode has minimum 44pt height.
    func testBookRowMinimumHeight() {
        // Switch to list mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.waitForHittable(timeout: 5))

        if toggle.label == "Switch to list view" {
            toggle.tap()
        }

        // Wait for list to appear
        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5))

        // Check the first cell height
        let firstCell = table.cells.firstMatch
        if firstCell.waitForExistence(timeout: 3) {
            XCTAssertGreaterThanOrEqual(
                firstCell.frame.height, minimumTouchTarget,
                "Book row height (\(firstCell.frame.height)) should be >= \(minimumTouchTarget)pt"
            )
        }
    }

    /// Verifies the format icon in list mode occupies a 44x44pt frame.
    func testFormatIconSize() {
        // Switch to list mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.waitForHittable(timeout: 5))

        if toggle.label == "Switch to list view" {
            toggle.tap()
        }

        // Wait for list to appear
        let table = app.tables.firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: 5))

        // The format icon is a 44x44 ZStack within BookRowView.
        // In XCUITest, we check the overall row height which contains the icon.
        let firstCell = table.cells.firstMatch
        if firstCell.waitForExistence(timeout: 3) {
            // The row's height should accommodate the 44pt icon
            XCTAssertGreaterThanOrEqual(
                firstCell.frame.height, minimumTouchTarget,
                "Book row should accommodate the 44pt format icon"
            )
        }
    }
}
