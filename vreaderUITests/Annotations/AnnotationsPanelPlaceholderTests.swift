// Feature #62: the unified 4-tab annotations panel was split into
// `TOCSheet` (Contents + Bookmarks) + `HighlightsSheet` (the review
// filters). The legacy `ContentUnavailableView` placeholders were
// replaced by the designed `AnnotationsEmptyStateView` (custom SVG art
// + per-surface copy). These tests verify each split sheet's empty
// states are reachable. (Was WI-UI-11 — the unified panel's placeholders.)
//
// Seed: `.epubFixture` (`mini-epub3.epub`) — a real, openable EPUB that
// carries no annotations, so every annotations surface lands on its
// designed empty state. The `.books` seed cannot be used: its fixtures
// are metadata-only (no backing file — "The file could not be found",
// Bug #209 / #214), so the reader bottom chrome that opens these sheets
// never renders.

import XCTest

@MainActor
final class AnnotationsPanelPlaceholderTests: XCTestCase {
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
    /// card tap is retried for the library `LazyVGrid` layout race.
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

    private func openTOCSheet() -> XCUIElement {
        XCTAssertTrue(openSeededBook(), "Seeded EPUB should open")
        let button = ensureChromeVisible(anchorButton: AccessibilityID.readerContentsButton)
        XCTAssertTrue(button.waitForHittable(timeout: 10), "Contents button should be hittable")
        button.tap()
        let sheet = app.otherElements[AccessibilityID.tocSheet]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "TOCSheet should appear")
        return sheet
    }

    private func openHighlightsSheet() -> XCUIElement {
        XCTAssertTrue(openSeededBook(), "Seeded EPUB should open")
        let button = ensureChromeVisible(anchorButton: AccessibilityID.readerAnnotationsButton)
        XCTAssertTrue(button.waitForHittable(timeout: 10), "Notes button should be hittable")
        button.tap()
        let sheet = app.otherElements[AccessibilityID.highlightsSheet]
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "HighlightsSheet should appear")
        return sheet
    }

    // MARK: - TOCSheet empty states

    func testTOCSheetBookmarksTabShowsEmptyState() {
        _ = openTOCSheet()
        app.buttons[AccessibilityID.tocSheetBookmarksTab].tap()
        // The seeded fixture has no bookmarks — the designed empty state
        // shows. `AnnotationsEmptyStateView` carries its identifier on a
        // `.accessibilityElement(children: .contain)` container, which
        // surfaces as an `otherElements` element — query by that type.
        XCTAssertTrue(
            app.otherElements[AccessibilityID.bookmarkEmptyState]
                .waitForExistence(timeout: 5),
            "TOCSheet Bookmarks tab should show the bookmark empty state"
        )
    }

    // MARK: - HighlightsSheet empty states

    func testHighlightsSheetAllFilterShowsEmptyState() {
        _ = openHighlightsSheet()
        app.buttons[AccessibilityID.highlightsSheetFilterAll].tap()
        // The seeded fixture has no annotations — the designed empty
        // state shows.
        XCTAssertTrue(
            app.otherElements[AccessibilityID.highlightsEmptyState]
                .waitForExistence(timeout: 5),
            "HighlightsSheet All filter should show the empty state"
        )
    }

    func testHighlightsSheetBookmarksFilterShowsEmptyState() {
        _ = openHighlightsSheet()
        app.buttons[AccessibilityID.highlightsSheetFilterBookmarks].tap()
        // The Bookmarks chip is empty by design (the real bookmark
        // surface is TOCSheet's Bookmarks tab).
        XCTAssertTrue(
            app.otherElements[AccessibilityID.highlightsBookmarksEmptyState]
                .waitForExistence(timeout: 5),
            "HighlightsSheet Bookmarks filter should show the bookmarks empty state"
        )
    }

    // MARK: - Accessibility Audit

    func testAnnotationsSheetsAccessibilityAudit() {
        let sheet = openHighlightsSheet()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        // `.elementDetection` is excluded for this screen: the
        // `AnnotationsEmptyStateView` art (`EmptyHighlightsArt`) is a
        // decorative SVG-path illustration whose stylized "text-line"
        // bars trip the audit's pixel-based text detector. The audit
        // reports the issue with `element == nil` — i.e. there is NO
        // accessible control missing a label; it is purely decorative
        // pixels (the art is also `.accessibilityHidden`). Every real
        // text element on the sheet (chip labels/counts, title,
        // empty-state copy) is a proper `StaticText`. The other audit
        // types still run.
        auditCurrentScreen(app: app, excluding: .elementDetection)
    }
}
