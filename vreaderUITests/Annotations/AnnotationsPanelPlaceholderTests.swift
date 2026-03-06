// WI-UI-11: Annotations Panel — Placeholder States
//
// Tests verify the annotations panel opens, has four tabs
// (Bookmarks, Contents, Highlights, Notes), and each tab
// shows a ContentUnavailableView placeholder.

import XCTest

@MainActor
final class AnnotationsPanelPlaceholderTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func navigateToFirstBookAndOpenAnnotations() {
        tapFirstBook(in: app)

        let annotationsButton = app.buttons[AccessibilityID.readerAnnotationsButton]
        XCTAssertTrue(annotationsButton.waitForHittable(timeout: 5), "Annotations button should be hittable")
        annotationsButton.tap()
    }

    /// Taps a tab in the segmented picker by its label text.
    private func selectTab(_ tabName: String) {
        let tab = app.buttons[tabName]
        XCTAssertTrue(tab.waitForExistence(timeout: 3), "\(tabName) tab should exist")
        tab.tap()
    }

    // MARK: - Panel Presentation

    func testAnnotationsPanelOpens() {
        navigateToFirstBookAndOpenAnnotations()

        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(
            panel.waitForExistence(timeout: 5),
            "Annotations panel should appear after tapping annotations button"
        )
    }

    // MARK: - Tab Count

    func testAnnotationsPanelHasFourTabs() {
        navigateToFirstBookAndOpenAnnotations()

        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        let expectedTabs = ["Bookmarks", "Contents", "Highlights", "Notes"]
        for tabName in expectedTabs {
            let tab = app.buttons[tabName]
            XCTAssertTrue(
                tab.waitForExistence(timeout: 3),
                "Tab '\(tabName)' should exist in the annotations panel"
            )
        }
    }

    // MARK: - Individual Tab Placeholders

    func testBookmarksTabShowsPlaceholder() {
        navigateToFirstBookAndOpenAnnotations()

        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        selectTab("Bookmarks")

        // Bookmarks tab should show placeholder text
        let placeholderText = app.staticTexts["Bookmarks will appear here once the reader is fully wired."]
        XCTAssertTrue(
            placeholderText.waitForExistence(timeout: 3),
            "Bookmarks tab should show placeholder description"
        )
    }

    func testContentsTabShowsPlaceholder() {
        navigateToFirstBookAndOpenAnnotations()

        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        selectTab("Contents")

        let placeholderText = app.staticTexts["Table of contents will appear here once the reader is fully wired."]
        XCTAssertTrue(
            placeholderText.waitForExistence(timeout: 3),
            "Contents tab should show placeholder description"
        )
    }

    func testHighlightsTabShowsPlaceholder() {
        navigateToFirstBookAndOpenAnnotations()

        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        selectTab("Highlights")

        let placeholderText = app.staticTexts["Highlights will appear here once the reader is fully wired."]
        XCTAssertTrue(
            placeholderText.waitForExistence(timeout: 3),
            "Highlights tab should show placeholder description"
        )
    }

    func testNotesTabShowsPlaceholder() {
        navigateToFirstBookAndOpenAnnotations()

        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        selectTab("Notes")

        let placeholderText = app.staticTexts["Notes will appear here once the reader is fully wired."]
        XCTAssertTrue(
            placeholderText.waitForExistence(timeout: 3),
            "Notes tab should show placeholder description"
        )
    }

    // MARK: - Accessibility Audit

    func testAnnotationsPanelAccessibilityAudit() {
        navigateToFirstBookAndOpenAnnotations()

        let panel = app.otherElements[AccessibilityID.annotationsPanelSheet]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        auditCurrentScreen(app: app)
    }
}
