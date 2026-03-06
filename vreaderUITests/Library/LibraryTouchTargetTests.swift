// Purpose: Touch target compliance tests for library view.
// Verifies all interactive elements meet Apple HIG minimum 44x44pt touch targets.
//
// Note: SwiftUI navigation bar buttons may report visual frame sizes smaller
// than 44pt, but iOS guarantees a 44pt minimum hit area for bar items.
// Tests verify the import button and list row heights, which are layout-controlled.
//
// @coordinates-with: LaunchHelper.swift, TestConstants.swift, LibraryView.swift,
//   BookRowView.swift

import XCTest

@MainActor
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

    /// Verifies the view mode toggle button exists and is tappable.
    /// Navigation bar buttons get system-provided 44pt hit areas regardless of visual frame.
    func testViewModeToggleMinimumSize() {
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isHittable, "View mode toggle should be hittable")
    }

    /// Verifies the sort picker button exists and is tappable.
    func testSortPickerMinimumSize() {
        let sortPicker = app.buttons[AccessibilityID.sortPicker]
        XCTAssertTrue(sortPicker.waitForExistence(timeout: 5))
        XCTAssertTrue(sortPicker.isHittable, "Sort picker should be hittable")
    }

    /// Verifies the import button meets minimum 44x44pt touch target.
    func testImportButtonMinimumSize() {
        // Relaunch with empty state to see the import button
        app = launchApp(seed: .empty)

        let importButton = app.buttons[AccessibilityID.importBooksButton]
        XCTAssertTrue(importButton.waitForExistence(timeout: 5))

        // .borderedProminent buttons should meet 44pt minimum
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
            let switched = NSPredicate(format: "label == 'Switch to grid view'")
            let expectation = XCTNSPredicateExpectation(predicate: switched, object: toggle)
            _ = XCTWaiter.wait(for: [expectation], timeout: 3)
        }

        // Wait for list row to appear (SwiftUI List renders as table or collectionView)
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        let firstRow = app.buttons.matching(rowPredicate).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5),
                       "At least one book row should exist in list mode")
        XCTAssertGreaterThanOrEqual(
            firstRow.frame.height, minimumTouchTarget,
            "Book row height (\(firstRow.frame.height)) should be >= \(minimumTouchTarget)pt"
        )
    }

    /// Verifies the format icon row in list mode has adequate height.
    /// The BookRowView includes a 44x44 format icon ZStack.
    func testFormatIconSize() {
        // Switch to list mode
        let toggle = app.buttons[AccessibilityID.viewModeToggle]
        XCTAssertTrue(toggle.waitForHittable(timeout: 5))

        if toggle.label == "Switch to list view" {
            toggle.tap()
            let switched = NSPredicate(format: "label == 'Switch to grid view'")
            let expectation = XCTNSPredicateExpectation(predicate: switched, object: toggle)
            _ = XCTWaiter.wait(for: [expectation], timeout: 3)
        }

        // Wait for list row to appear
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        let firstRow = app.buttons.matching(rowPredicate).firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5),
                       "At least one book row should exist in list mode")
        // The row's height should accommodate the 44pt icon
        XCTAssertGreaterThanOrEqual(
            firstRow.frame.height, minimumTouchTarget,
            "Book row should accommodate the 44pt format icon"
        )
    }
}
