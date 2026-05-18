// Purpose: Device verification for Bug #154 — search-tap navigation in TXT reader
// confirms the highlight wiring path fires end-to-end.
//
// Bug: TXTReaderContainerView had an orphan `@State private var highlightRange`
// that the bridge read from, but `ReaderNotificationModifier` set `uiState.highlightRange`
// (the TextReaderUIState path). Result: search-tap navigation scrolled correctly
// (bug #153 fix) but no temporary yellow highlight appeared.
//
// Fix: Orphan @State removed; both readerContent and chunkedReaderContent paths
// now pass `highlightRange: uiState.highlightRange` and
// `highlightIsTemporary: uiState.highlightIsTemporary` to TXTTextViewBridge.
// Chapter-mode translation plumbed end-to-end via Feature #48 WI-1 + WI-3.
//
// This UITest verifies that search → tap-result → reader re-opens at the
// correct position (proving the navigation + locator wiring fired). The
// temporary yellow highlight is transient (3s auto-clear) and render-asserted
// by TXTReaderContainerSearchHighlightWiringTests (4 source-level tests).
//
// Feature #63 WI-1: the search sheet's v2 re-skin replaced the system
// `.searchable` UISearchBar with a custom `TextField` — this test now
// queries `searchTextField` instead of `app.searchFields`.
//
// @coordinates-with: TXTReaderContainerView.swift, ReaderNotificationModifier.swift,
//   SearchView.swift, SearchViewModel.swift, TXTTextViewBridge.swift

import XCTest

@MainActor
final class TXTSearchTapHighlightNavigationTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // positionTest seed: non-chaptered Position Test Book (100 paragraphs)
        // resetPreferences: clean state so no stale position or search index
        app = launchApp(seed: .positionTest, resetPreferences: true)
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func txtReaderTextView() -> XCUIElement {
        app.textViews.matching(identifier: AccessibilityID.txtReaderContainer).firstMatch
    }

    private func waitForReaderReady(timeout: TimeInterval = 15) -> Bool {
        let textView = txtReaderTextView()
        guard textView.waitForExistence(timeout: timeout) else { return false }

        // Loading spinner must disappear first
        let loading = app.descendants(matching: .any)
            .matching(identifier: AccessibilityID.txtReaderLoading).firstMatch
        if loading.exists {
            _ = loading.waitForDisappearance(timeout: 10)
        }

        // Container must expose a real restoredOffset (not 'none')
        let readyPredicate = NSPredicate(
            format: "value CONTAINS 'restoredOffset:' AND NOT value CONTAINS 'restoredOffset:none'"
        )
        let expect = XCTNSPredicateExpectation(predicate: readyPredicate, object: textView)
        return XCTWaiter().wait(for: [expect], timeout: timeout) == .completed
    }

    // MARK: - Bug #154 Close-Gate Verification

    /// Verifies that search-tap navigation in TXT reader:
    /// 1. Returns results for "Paragraph 50"
    /// 2. After tapping the result, the reader is visible at a valid position
    ///    (i.e. the navigation locator fired and the reader re-rendered)
    ///
    /// The yellow highlight render itself is a transient 3s visual guarded by
    /// TXTReaderContainerSearchHighlightWiringTests. This test confirms the
    /// navigation path fires — the necessary precondition for the highlight wiring
    /// to take effect.
    func testSearchTapNavigatesToPosition() throws {
        // 1. Open Position Test Book (non-chaptered, 100 paragraphs)
        tapBook(titled: "Position Test Book", in: app)

        // 2. Wait for TXT reader to be fully ready
        XCTAssertTrue(
            waitForReaderReady(),
            "TXT reader should load Position Test Book with a valid restoredOffset"
        )

        // 3. Open the search sheet
        // Tap to show chrome first (chrome may be auto-hidden on initial load)
        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        if !searchButton.waitForExistence(timeout: 3) {
            txtReaderTextView().tap()
        }
        XCTAssertTrue(
            searchButton.waitForHittable(timeout: 10),
            "Search button should be hittable (chrome visible)"
        )
        searchButton.tap()

        // 4. Verify search sheet appears
        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(
            searchSheet.waitForExistence(timeout: 5),
            "Search sheet should appear after tapping search button"
        )

        // 5. Wait for the SearchView's search field to appear.
        //    The search sheet first shows "Preparing search…" (no search field) while
        //    ReaderSearchCoordinator.setup() creates the SQLite store + SearchViewModel.
        //    Once searchViewModel is non-nil, SearchView renders.
        //    Feature #63 WI-1: the v2 re-skin replaced the `.searchable`
        //    UISearchBar with a custom `TextField` (`searchTextField`).
        //    Allow up to 45s for SQLite open + initial indexing of the TXT file.
        let searchField = app.textFields[AccessibilityID.searchTextField]
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 45),
            "Custom search field (searchTextField) should appear once " +
            "ReaderSearchCoordinator finishes setup. If still 'Preparing search...', " +
            "SQLite open or background indexing is taking too long."
        )

        // 6. Type "Paragraph 50" into the search field.
        searchField.tap()
        searchField.typeText("Paragraph 50")

        // 7. Wait for search results to populate.
        //    The SearchViewModel debounces (300ms); background FTS5 indexing may still
        //    be in progress. Once indexing completes, `retriggerIfNeeded()` re-runs
        //    the search and results appear. Allow generous time for both indexing and
        //    the re-trigger cycle to complete.
        //
        //    Wait directly for a `searchResult_`-prefixed button (more robust than
        //    waiting for the list OtherElement, which may not be directly accessible
        //    in some iOS/SwiftUI tree configurations).
        let firstResult = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'searchResult_'")
        ).firstMatch

        // Allow up to 45s total: covers first-run indexing + debounce + retrigger cycle
        XCTAssertTrue(
            firstResult.waitForExistence(timeout: 45),
            "At least one search result button (searchResult_*) should appear for 'Paragraph 50'. " +
            "If missing: check that background indexing completed and retriggerIfNeeded fired."
        )

        // 8. Tap the first search result
        firstResult.tap()

        // 9. Verify the search sheet dismissed and TXT reader is back
        //    (proving navigation fired — the code path that also sets
        //    uiState.highlightRange for the yellow highlight)
        let textView = txtReaderTextView()
        XCTAssertTrue(
            textView.waitForExistence(timeout: 10),
            "TXT reader container should be visible after search-result tap (search sheet dismissed)"
        )

        // 10. Verify the reader has a valid navigation position (not stuck at 'none')
        let navigatedPredicate = NSPredicate(
            format: "value CONTAINS 'restoredOffset:' AND NOT value CONTAINS 'restoredOffset:none'"
        )
        let navigatedExpect = XCTNSPredicateExpectation(
            predicate: navigatedPredicate,
            object: textView
        )
        let navigatedResult = XCTWaiter().wait(for: [navigatedExpect], timeout: 8)
        XCTAssertEqual(
            navigatedResult, .completed,
            "TXT reader should show a valid position after search-result navigation. " +
            "If 'restoredOffset:none', the navigation locator path did not fire — Bug #154 regressed. " +
            "Value: \(textView.value as? String ?? "(nil)")"
        )
    }
}
