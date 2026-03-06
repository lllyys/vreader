// WI-UI-6: Reader Annotations Panel — Presentation, Tabs, and Dismissal
//
// Tests verify the annotations panel sheet presents from the reader toolbar,
// has the expected segmented tab picker, supports tab switching, and dismisses.

import XCTest

@MainActor
final class ReaderAnnotationsPanelTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func openAnnotationsPanel() {
        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        XCTAssertTrue(annotationsButton.waitForHittable(timeout: 5), "Annotations button should be hittable")
        annotationsButton.tap()
    }

    // MARK: - Tests

    func testAnnotationsPanelPresents() {
        tapFirstBook(in: app)
        openAnnotationsPanel()

        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "Annotations panel sheet should appear after tapping annotations button"
        )
    }

    func testAnnotationsPanelHasTabs() {
        tapFirstBook(in: app)
        openAnnotationsPanel()

        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        // Check for the segmented picker tabs
        let bookmarksTab = app.buttons["Bookmarks"]
        let contentsTab = app.buttons["Contents"]
        let highlightsTab = app.buttons["Highlights"]
        let notesTab = app.buttons["Notes"]

        XCTAssertTrue(bookmarksTab.waitForExistence(timeout: 3), "Bookmarks tab should exist")
        XCTAssertTrue(contentsTab.waitForExistence(timeout: 3), "Contents tab should exist")
        XCTAssertTrue(highlightsTab.waitForExistence(timeout: 3), "Highlights tab should exist")
        XCTAssertTrue(notesTab.waitForExistence(timeout: 3), "Notes tab should exist")
    }

    func testAnnotationsPanelTabSwitching() {
        tapFirstBook(in: app)
        openAnnotationsPanel()

        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        // Tap each tab and verify the panel stays visible
        let tabs = ["Bookmarks", "Contents", "Highlights", "Notes"]
        for tabName in tabs {
            let tab = app.buttons[tabName]
            XCTAssertTrue(tab.waitForExistence(timeout: 3), "\(tabName) tab should exist")
            tab.tap()

            // Panel should still be visible after switching
            XCTAssertTrue(
                panel.waitForExistence(timeout: 3),
                "Panel should remain visible after switching to \(tabName) tab"
            )
        }
    }

    func testAnnotationsPanelDismiss() {
        tapFirstBook(in: app)
        openAnnotationsPanel()

        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        // Swipe down to dismiss
        panel.swipeDown()

        // Reader chrome should reappear
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 5),
            "Reader chrome should be visible after dismissing annotations panel"
        )
    }
}
