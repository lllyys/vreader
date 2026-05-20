// Feature #62: the unified 4-tab annotations panel was split into two
// sheets — `TOCSheet` (Contents + Bookmarks) opened by the Contents
// bottom-chrome button, and `HighlightsSheet` (All / Highlights / Notes
// / Bookmarks review filters) opened by the Notes button. These tests
// verify both sheets present, carry their expected segments, support
// segment switching, and dismiss. (Was WI-UI-6 — the unified panel.)
//
// Seed: `.epubFixture` (`mini-epub3.epub`) — a real, openable EPUB. The
// reader bottom chrome (the Contents / Notes buttons) only renders once
// a book's content loads, so the `.books` seed (metadata-only fixtures,
// no backing file — "The file could not be found", Bug #209 / #214)
// cannot reach the chrome. `.epubFixture` opens a real reader.

import XCTest

@MainActor
final class ReaderAnnotationsPanelTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .epubFixture)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    /// Opens the seeded EPUB book and waits for the reader chrome. The
    /// card tap is retried because a first tap can land before the
    /// library `LazyVGrid` finishes its initial layout pass.
    @discardableResult
    private func openSeededBook() -> Bool {
        let card = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookCard_'")
        ).firstMatch
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'bookRow_'")
        ).firstMatch
        let backButton = app.buttons[AccessibilityID.readerBackButton]

        for _ in 0..<3 {
            if card.waitForExistence(timeout: 15) {
                if card.waitForHittable(timeout: 8) || card.exists { card.tap() }
            } else if row.waitForExistence(timeout: 3) {
                if row.waitForHittable(timeout: 8) || row.exists { row.tap() }
            }
            if backButton.waitForExistence(timeout: 20) { return true }
        }
        return false
    }

    /// Makes the reader bottom chrome visible — it auto-hides on load;
    /// a content tap toggles it back on.
    private func ensureChromeVisible(anchorButton id: String) -> XCUIElement {
        let button = app.buttons[id]
        if !button.waitForExistence(timeout: 3) {
            app.tap()
        }
        return button
    }

    /// Opens `TOCSheet` via the Contents bottom-chrome button.
    private func openTOCSheet() -> XCUIElement {
        let button = ensureChromeVisible(anchorButton: AccessibilityID.readerContentsButton)
        XCTAssertTrue(button.waitForHittable(timeout: 10), "Contents button should be hittable")
        button.tap()
        let sheet = app.otherElements[AccessibilityID.tocSheet]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "TOCSheet should appear")
        return sheet
    }

    /// Opens `HighlightsSheet` via the Notes bottom-chrome button.
    private func openHighlightsSheet() -> XCUIElement {
        let button = ensureChromeVisible(anchorButton: AccessibilityID.readerAnnotationsButton)
        XCTAssertTrue(button.waitForHittable(timeout: 10), "Notes button should be hittable")
        button.tap()
        let sheet = app.otherElements[AccessibilityID.highlightsSheet]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "HighlightsSheet should appear")
        return sheet
    }

    // MARK: - TOCSheet

    func testTOCSheetPresents() {
        XCTAssertTrue(openSeededBook(), "Seeded EPUB should open")
        _ = openTOCSheet()
    }

    func testTOCSheetHasContentsAndBookmarksTabs() {
        XCTAssertTrue(openSeededBook(), "Seeded EPUB should open")
        _ = openTOCSheet()

        XCTAssertTrue(
            app.buttons[AccessibilityID.tocSheetContentsTab].waitForExistence(timeout: 3),
            "TOCSheet should have a Contents tab"
        )
        XCTAssertTrue(
            app.buttons[AccessibilityID.tocSheetBookmarksTab].waitForExistence(timeout: 3),
            "TOCSheet should have a Bookmarks tab"
        )
    }

    func testTOCSheetTabSwitching() {
        XCTAssertTrue(openSeededBook(), "Seeded EPUB should open")
        let sheet = openTOCSheet()

        for tab in [AccessibilityID.tocSheetContentsTab, AccessibilityID.tocSheetBookmarksTab] {
            let segment = app.buttons[tab]
            XCTAssertTrue(segment.waitForExistence(timeout: 3), "\(tab) should exist")
            segment.tap()
            XCTAssertTrue(
                sheet.waitForExistence(timeout: 3),
                "TOCSheet should remain visible after switching to \(tab)"
            )
        }
    }

    func testTOCSheetDismiss() {
        XCTAssertTrue(openSeededBook(), "Seeded EPUB should open")
        let sheet = openTOCSheet()
        sheet.swipeDown()
        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 5),
            "Reader chrome should be visible after dismissing TOCSheet"
        )
    }

    // MARK: - HighlightsSheet

    func testHighlightsSheetPresents() {
        XCTAssertTrue(openSeededBook(), "Seeded EPUB should open")
        _ = openHighlightsSheet()
    }

    func testHighlightsSheetHasFourFilterChips() {
        XCTAssertTrue(openSeededBook(), "Seeded EPUB should open")
        _ = openHighlightsSheet()

        let chips = [
            AccessibilityID.highlightsSheetFilterAll,
            AccessibilityID.highlightsSheetFilterHighlights,
            AccessibilityID.highlightsSheetFilterNotes,
            AccessibilityID.highlightsSheetFilterBookmarks,
        ]
        for chip in chips {
            XCTAssertTrue(
                app.buttons[chip].waitForExistence(timeout: 3),
                "HighlightsSheet should have the \(chip) filter chip"
            )
        }
    }

    func testHighlightsSheetFilterSwitching() {
        XCTAssertTrue(openSeededBook(), "Seeded EPUB should open")
        let sheet = openHighlightsSheet()

        let chips = [
            AccessibilityID.highlightsSheetFilterAll,
            AccessibilityID.highlightsSheetFilterHighlights,
            AccessibilityID.highlightsSheetFilterNotes,
            AccessibilityID.highlightsSheetFilterBookmarks,
        ]
        for chip in chips {
            let filter = app.buttons[chip]
            XCTAssertTrue(filter.waitForExistence(timeout: 3), "\(chip) should exist")
            filter.tap()
            XCTAssertTrue(
                sheet.waitForExistence(timeout: 3),
                "HighlightsSheet should remain visible after selecting \(chip)"
            )
        }
    }

    func testHighlightsSheetDismiss() {
        XCTAssertTrue(openSeededBook(), "Seeded EPUB should open")
        let sheet = openHighlightsSheet()
        sheet.swipeDown()
        XCTAssertTrue(
            app.buttons[AccessibilityID.readerBackButton].waitForExistence(timeout: 5),
            "Reader chrome should be visible after dismissing HighlightsSheet"
        )
    }
}
