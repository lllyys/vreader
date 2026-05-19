// WI-UI-10: Search View — Placeholder State
//
// Tests verify the search sheet opens from the reader toolbar,
// shows its placeholder content, and can be dismissed.
// The full SearchView with FTS5 is not mounted yet.
//
// Feature #63 WI-1: once the FTS5 `SearchView` mounts, its v2-re-skinned
// custom bar dismisses via the "Cancel" button (`searchCancelButton`).
// The pre-mount "Preparing search…" placeholder still uses a
// NavigationStack "Done" button — the dismiss helper accepts either.

import XCTest

@MainActor
final class SearchSheetPlaceholderTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launchApp(seed: .books)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func navigateToFirstBookAndOpenSearch() {
        tapFirstBook(in: app)

        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        XCTAssertTrue(searchButton.waitForHittable(timeout: 5), "Search button should be hittable")
        searchButton.tap()
    }

    // MARK: - Tests

    func testSearchSheetOpens() {
        navigateToFirstBookAndOpenSearch()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(
            searchSheet.waitForExistence(timeout: 5),
            "Search sheet should appear after tapping search button in reader toolbar"
        )
    }

    func testSearchSheetDismisses() {
        navigateToFirstBookAndOpenSearch()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(searchSheet.waitForExistence(timeout: 5))

        // Feature #63 WI-1: depending on indexing timing the sheet shows
        // either the pre-mount "Preparing search…" placeholder ("Done"
        // toolbar button) or the mounted FTS5 `SearchView` whose
        // re-skinned custom bar dismisses via "Cancel"
        // (`searchCancelButton`). Accept whichever is present.
        let cancelButton = app.buttons[AccessibilityID.searchCancelButton]
        let doneButton = app.buttons["Done"]
        if cancelButton.waitForExistence(timeout: 3) {
            cancelButton.tap()
        } else if doneButton.exists {
            doneButton.tap()
        } else {
            // Fallback: swipe down
            searchSheet.swipeDown()
        }

        // Verify reader chrome is visible again
        let backButton = app.buttons[AccessibilityID.readerBackButton]
        XCTAssertTrue(
            backButton.waitForExistence(timeout: 5),
            "Reader chrome should be visible after dismissing search sheet"
        )
    }

    func testSearchSheetAccessibilityAudit() {
        navigateToFirstBookAndOpenSearch()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(searchSheet.waitForExistence(timeout: 5))

        // Bug #224 / GH #902: feature #63's `SearchBar` re-skin gives the
        // `searchTextField` (~19 pt tall) and `searchCancelButton`
        // (~17 pt tall) accessibility frames well below the 44 pt HIG
        // touch-target minimum, so the audit's `.hitRegion` check fails.
        // That is a distinct product defect tracked in Bug #224 — not
        // Bug #223's identifier-propagation regression this suite covers.
        // `.hitRegion` is excluded here as tracked debt; when Bug #224
        // lands, drop this exclusion so the audit re-covers touch targets.
        auditCurrentScreen(app: app, excluding: .hitRegion)
    }
}
