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

        // Bug #224 / GH #902: feature #63's `SearchBar` re-skin gave the
        // `searchTextField` and `searchCancelButton` accessibility frames
        // below the 44 pt HIG touch-target minimum. The fix gives both
        // controls a >=44 pt tappable frame, so `.hitRegion` is now
        // covered by the audit (no longer excluded as tracked debt).
        //
        // The search bar auto-focuses its field, raising the software
        // keyboard; `ignoringKeyboardElements` skips Apple keyboard-
        // internal audit gaps (e.g. `TUIPredictionViewCell`) so the
        // audit stays honest for the app's own SearchBar elements.
        auditCurrentScreen(app: app, ignoringKeyboardElements: true)
    }
}
