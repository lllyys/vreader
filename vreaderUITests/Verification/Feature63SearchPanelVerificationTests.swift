// Purpose: CU-free Gate-5 verification suite for Feature #63 — "Search
// results panel v2 re-skin: bring the in-reader `SearchView` onto the
// visual-identity-v2 chrome".
//
// Feature #63 (PR #854) re-skinned the in-reader search sheet: the system
// `.searchable` bar + `NavigationStack` `Done` toolbar were replaced with a
// custom in-sheet `SearchBar`, the plain `List` with a grouped
// `SearchResultsGroupedList`, and the idle / no-results states with the
// design bundle's restyled `SearchPromptView` / `SearchNoResultsView`
// (`dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx`).
//
// Why this suite exists — the C2 / C3 / C4 XCUITest gap:
//   The three migrated search-sheet suites (`ReaderSearchSheetTests`,
//   `SearchSheetPlaceholderTests`, `TXTSearchTapHighlightNavigationTests`)
//   cover sheet presentation, dismissal, the SearchBar accessibility
//   audit, and result-tap navigation — but NONE of them asserts the
//   re-skinned content states by their identifiers. The prior Gate-5
//   pass (`dev-docs/verification/feature-63-20260519.md`) verified
//   C2 (idle prompt), C3 (grouped results list) and C4 (no-results
//   state) only by manual on-device inspection + pure-function unit
//   tests (`SearchViewReskinTests.contentState`, which proves the state
//   *selector* but not that the re-skinned views actually mount). This
//   suite closes that gap with end-to-end XCUITest assertions so the
//   feature-#63 acceptance contract is fully covered by automation.
//
// What this suite verifies (feature #63 acceptance criteria C1-C5):
//   - C1 (custom in-sheet search bar): the re-skinned `searchTextField`
//     + `searchCancelButton` are present and NO legacy system search
//     field (`XCUIElementTypeSearchField`) exists — the `.searchable`
//     UISearchBar is gone.
//   - C2 (restyled idle prompt): with the sheet open and no query typed,
//     the `searchEmptyPromptView` (`SearchPromptView`) renders — not a
//     blank list, not the grouped list with a "0 matches" line.
//   - C3 (grouped results list): a query with matches mounts the
//     `searchResultsList` (`SearchResultsGroupedList`) container with at
//     least one `searchResult_*` row inside it.
//   - C4 (restyled no-results state): a non-empty query with zero
//     matches mounts the `searchNoResultsView` (`SearchNoResultsView`).
//   - C5 (behavior preserved — clear): the `searchClearButton` empties
//     the query and the sheet reverts from results/no-results back to
//     the idle `searchEmptyPromptView`. (Result-tap navigation, the
//     other half of C5, is covered by
//     `TXTSearchTapHighlightNavigationTests.testSearchTapNavigatesToPosition`.)
//
// Design / pattern notes:
//   - Drives the app entirely through the XCUITest accessibility API
//     (element queries + synthesized taps / typing) — no computer-use,
//     no DebugBridge `open` URL (which cannot reliably commit a
//     NavigationStack push in a headless `simctl openurl` session, see
//     `Feature54ReadingModeRemovalVerificationTests` header).
//   - Uses the `.epubFixture` seed (`mini-epub3.epub`): a real, openable
//     EPUB whose search hits resolve via `href` with NO dependency on
//     the TXT `segment_base_offsets` persistence path. The prior Gate-5
//     pass documented that the `war-and-peace.txt` fixture has an empty
//     `segment_base_offsets`, so TXT search hits do not resolve — an
//     independent pre-existing search-pipeline gap outside feature #63's
//     scope. The EPUB fixture sidesteps it, keeping this suite a clean
//     test of the #63 re-skin and nothing else.
//   - **Query by element TYPE, not by container identifier.** Bug #223's
//     fix added `.accessibilityElement(children: .contain)` to
//     `SearchView`'s root, collapsing `searchSheet` into one queryable
//     `otherElements` container. Inside it, SwiftUI propagates each
//     child view's `.accessibilityIdentifier` ONTO that view's leaf
//     elements rather than yielding a wrapping `Other` — confirmed by an
//     `app.debugDescription` dump of the live search sheet:
//       - `searchEmptyPromptView` (a `VStack` of two `Text`s) surfaces
//         as TWO `StaticText` elements, each carrying that identifier —
//         queried here via `app.staticTexts`.
//       - `searchNoResultsView` (an `Image` + two `Text`s) surfaces as
//         an `Image` + two `StaticText`s — queried via `app.staticTexts`.
//       - `searchTextField` is a `TextField`; `searchCancelButton` /
//         `searchClearButton` / `searchResult_*` are `Button`s — all
//         resolve as their own type.
//     This is the same "query by type" lesson the feature-#54 pilot
//     (`Feature54ReadingModeRemovalVerificationTests`) drew from Bug
//     #214 — a SwiftUI container identifier is not a reliable
//     `otherElements` handle.
//
// @coordinates-with: SearchView.swift, SearchBar.swift,
//   SearchStateViews.swift, SearchResultsGroupedList.swift,
//   ReaderContainerView+Sheets.swift, TestSeeder.swift, LaunchHelper.swift,
//   TestConstants.swift

import XCTest

@MainActor
final class Feature63SearchPanelVerificationTests: XCTestCase {

    // MARK: - Test lifecycle

    /// Launches with the `.epubFixture` seed (`mini-epub3.epub` — a real,
    /// openable EPUB) and `--reset-preferences` so the run starts from a
    /// known UserDefaults state (Bug #152).
    private func launch() -> XCUIApplication {
        launchApp(seed: .epubFixture, resetPreferences: true)
    }

    // MARK: - Helpers

    /// Opens the seeded EPUB book and waits for the reader chrome. The
    /// card tap is retried because a first tap can land before the
    /// library `LazyVGrid` finishes its initial layout pass — the same
    /// legitimate timing race handled in
    /// `Feature54ReadingModeRemovalVerificationTests.openSeededBook`.
    @discardableResult
    private func openSeededBook(in app: XCUIApplication) -> Bool {
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

    /// Taps the reader toolbar Search button and waits for the search
    /// sheet container. The reader chrome auto-hides; a content tap
    /// toggles it back on so the Search button becomes hittable. Mirrors
    /// `ensureChromeVisible` in the feature-#54 verification suite.
    ///
    /// - Returns: the `searchSheet` container element once it exists.
    @discardableResult
    private func openSearchSheet(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let searchButton = app.buttons[AccessibilityID.readerSearchButton]
        if !searchButton.waitForExistence(timeout: 3) {
            // Chrome auto-hid on initial load — a content tap reveals it.
            app.tap()
        }
        XCTAssertTrue(
            searchButton.waitForHittable(timeout: 10),
            "Reader Search button should be hittable (chrome visible)",
            file: file, line: line
        )
        searchButton.tap()

        let searchSheet = app.otherElements[AccessibilityID.searchSheet]
        XCTAssertTrue(
            searchSheet.waitForExistence(timeout: 5),
            "Search sheet should appear after tapping the Search button " +
            "— Bug #223's `.accessibilityElement(children: .contain)` fix " +
            "must make `searchSheet` resolve as a queryable container",
            file: file, line: line
        )
        return searchSheet
    }

    /// Waits for the re-skinned custom search bar's `TextField` to mount.
    /// The sheet first shows a "Preparing search…" placeholder while
    /// `ReaderSearchCoordinator.setup()` builds the SQLite store +
    /// `SearchViewModel`; once that completes, `SearchView` (with the
    /// custom `SearchBar`) renders. Allow a generous window for the
    /// SQLite open + initial fixture indexing.
    ///
    /// - Returns: the `searchTextField` element once it exists.
    private func waitForSearchField(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        let searchField = app.textFields[AccessibilityID.searchTextField]
        XCTAssertTrue(
            searchField.waitForExistence(timeout: 45),
            "Custom `searchTextField` should appear once " +
            "ReaderSearchCoordinator finishes setup (feature #63 C1 — the " +
            "v2 re-skin's custom bar replaces the `.searchable` UISearchBar)",
            file: file, line: line
        )
        return searchField
    }

    /// Types `query` into the search field. The field is tapped first to
    /// take first-responder focus, then the text is entered.
    private func enterQuery(
        _ query: String,
        into field: XCUIElement
    ) {
        field.tap()
        field.typeText(query)
    }

    /// The idle-prompt element. `SearchPromptView` is a `VStack` of two
    /// `Text`s under `.accessibilityIdentifier("searchEmptyPromptView")`;
    /// `SearchView`'s `.accessibilityElement(children: .contain)` (the Bug
    /// #223 fix) makes SwiftUI propagate that identifier onto each leaf
    /// `Text`, so the prompt surfaces as `StaticText`s — query by that
    /// type. `firstMatch` is the section label ("SEARCH THIS BOOK").
    private func idlePromptElement(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts[AccessibilityID.searchEmptyPromptView].firstMatch
    }

    /// The no-results element. `SearchNoResultsView` is an `Image` + two
    /// `Text`s under `.accessibilityIdentifier("searchNoResultsView")`;
    /// the identifier propagates onto the leaves, so the headline / sub
    /// copy surface as `StaticText`s — query by that type. `firstMatch`
    /// is the "No matches for …" headline.
    private func noResultsElement(in app: XCUIApplication) -> XCUIElement {
        app.staticTexts[AccessibilityID.searchNoResultsView].firstMatch
    }

    /// The grouped results list. `SearchResultsGroupedList` sets its
    /// identifier on a `ScrollView`, which surfaces as an
    /// `XCUIElementTypeScrollView` — query by that type.
    private func resultsListElement(in app: XCUIApplication) -> XCUIElement {
        app.scrollViews[AccessibilityID.searchResultsList]
    }

    // MARK: - C1 — custom in-sheet search bar replaces the system bar

    /// C1: the re-skinned search sheet shows the custom `SearchBar` — a
    /// `searchTextField` + a `searchCancelButton` — and the legacy system
    /// `.searchable` UISearchBar (an `XCUIElementTypeSearchField`) is
    /// gone. This is the structural half of acceptance criterion C1.
    func test_verify_feature_63_C1_custom_search_bar_replaces_system_bar() throws {
        let app = launch()
        XCTAssertTrue(
            openSeededBook(in: app),
            "The seeded mini-epub3 EPUB should open into the reader"
        )
        openSearchSheet(in: app)
        let searchField = waitForSearchField(in: app)

        // The custom bar's text field and "Cancel" button are present.
        XCTAssertTrue(
            searchField.exists,
            "C1: the custom `searchTextField` should be present in the " +
            "re-skinned search bar"
        )
        XCTAssertTrue(
            app.buttons[AccessibilityID.searchCancelButton].waitForExistence(timeout: 5),
            "C1: the custom bar's accent `searchCancelButton` should be " +
            "present — it replaces the old `NavigationStack` \"Done\" toolbar"
        )

        // The legacy system search field must NOT exist — feature #63
        // removed the `.searchable` modifier. `XCUIApplication.searchFields`
        // matches `XCUIElementTypeSearchField`, which a SwiftUI `TextField`
        // is NOT — so a non-empty `searchFields` would mean the system bar
        // regressed back in.
        XCTAssertFalse(
            app.searchFields.firstMatch.exists,
            "C1: no system `.searchable` UISearchBar (XCUIElementTypeSearchField) " +
            "should exist — the v2 re-skin replaced it with a custom `TextField`"
        )
    }

    // MARK: - C2 — restyled idle prompt on an empty query

    /// C2: with the search sheet open and NO query typed, the re-skinned
    /// idle prompt (`SearchPromptView`, id `searchEmptyPromptView`)
    /// renders. The grouped results list and the no-results state must
    /// both be absent — the idle state is neither a "0 matches" list nor
    /// a no-results splash.
    func test_verify_feature_63_C2_idle_prompt_renders_on_empty_query() throws {
        let app = launch()
        XCTAssertTrue(
            openSeededBook(in: app),
            "The seeded mini-epub3 EPUB should open into the reader"
        )
        openSearchSheet(in: app)
        // Wait for the SearchView to mount (past the "Preparing search…"
        // placeholder) — the idle prompt is part of the mounted SearchView.
        _ = waitForSearchField(in: app)

        XCTAssertTrue(
            idlePromptElement(in: app).waitForExistence(timeout: 10),
            "C2: the re-skinned `searchEmptyPromptView` (SearchPromptView) " +
            "should render on an empty query — not a blank list"
        )
        // The other content states must be absent in the idle state.
        XCTAssertFalse(
            resultsListElement(in: app).exists,
            "C2: the grouped results list must NOT be present before a " +
            "query is typed (the idle state is the prompt, not a 0-match list)"
        )
        XCTAssertFalse(
            noResultsElement(in: app).exists,
            "C2: the no-results state must NOT be present before a query " +
            "is typed"
        )
    }

    // MARK: - C3 — grouped results list for a query with matches

    /// C3: a query with matches mounts the re-skinned grouped results
    /// list (`SearchResultsGroupedList`, id `searchResultsList`) with at
    /// least one `searchResult_*` row inside it. "paragraph" appears
    /// multiple times across the EPUB fixture's two chapters, so it
    /// produces a real grouped result set whose hits resolve via `href`
    /// (no TXT `segment_base_offsets` dependency).
    func test_verify_feature_63_C3_grouped_results_list_for_matches() throws {
        let app = launch()
        XCTAssertTrue(
            openSeededBook(in: app),
            "The seeded mini-epub3 EPUB should open into the reader"
        )
        openSearchSheet(in: app)
        let searchField = waitForSearchField(in: app)

        // "paragraph" — present in both chapter1.xhtml and chapter2.xhtml
        // of the mini-epub3 fixture (it produces multiple matches).
        enterQuery("paragraph", into: searchField)

        // At least one grouped result row mounts once the debounced FTS5
        // search (+ any first-run background indexing + retrigger)
        // completes. The `searchResult_*` button identifier resolves
        // reliably (proven by `TXTSearchTapHighlightNavigationTests`).
        let firstResult = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH 'searchResult_'")
        ).firstMatch
        XCTAssertTrue(
            firstResult.waitForExistence(timeout: 45),
            "C3: at least one `searchResult_*` row should render in the " +
            "grouped results list for the query \"paragraph\". If absent: " +
            "check that background indexing completed and the search " +
            "retrigger fired."
        )

        // The re-skinned grouped list container (`SearchResultsGroupedList`
        // — a `ScrollView`) is present, confirming the rows render inside
        // the v2 grouped list rather than a plain `List`.
        XCTAssertTrue(
            resultsListElement(in: app).waitForExistence(timeout: 10),
            "C3: the re-skinned `searchResultsList` (SearchResultsGroupedList " +
            "ScrollView) should host the result rows"
        )

        // The grouped list's "{N} matches in {M} sections" count line is a
        // distinctive re-skin element — a plain `List` had no such header.
        // Its exact numbers vary with FTS5 snippet windowing, so match the
        // invariant phrasing rather than a fixed count.
        let countLine = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'match' AND label CONTAINS[c] 'section'")
        ).firstMatch
        XCTAssertTrue(
            countLine.waitForExistence(timeout: 10),
            "C3: the grouped list's \"{N} matches in {M} sections\" count " +
            "line should render — it is a re-skin element absent from the " +
            "pre-#63 plain `List`"
        )
    }

    // MARK: - C4 — restyled no-results state for a zero-match query

    /// C4: a non-empty query that finds nothing mounts the re-skinned
    /// no-results state (`SearchNoResultsView`, id `searchNoResultsView`).
    /// A gibberish token guarantees zero matches against the fixture.
    func test_verify_feature_63_C4_no_results_state_for_zero_match_query() throws {
        let app = launch()
        XCTAssertTrue(
            openSeededBook(in: app),
            "The seeded mini-epub3 EPUB should open into the reader"
        )
        openSearchSheet(in: app)
        let searchField = waitForSearchField(in: app)

        // A token that cannot appear in the fixture — guarantees the FTS5
        // search resolves to zero matches → `noResultsFound` → the
        // re-skinned no-results view.
        enterQuery("zzzznotfoundqqq", into: searchField)

        XCTAssertTrue(
            noResultsElement(in: app).waitForExistence(timeout: 45),
            "C4: the re-skinned `searchNoResultsView` (SearchNoResultsView) " +
            "should mount for a non-empty query that found nothing"
        )
        // The re-skinned headline names the query verbatim — confirms the
        // restyled `SearchNoResultsView` copy ("No matches for …"), not a
        // generic empty list.
        let noResultsHeadline = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'No matches for'")
        ).firstMatch
        XCTAssertTrue(
            noResultsHeadline.exists,
            "C4: the no-results state should show the re-skinned " +
            "\"No matches for …\" headline"
        )
        // The grouped results list must be absent — a zero-match query is
        // the no-results state, not an empty grouped list.
        XCTAssertFalse(
            resultsListElement(in: app).exists,
            "C4: the grouped results list must NOT be present for a query " +
            "that found zero matches"
        )
    }

    // MARK: - C5 — behavior preserved: the clear button empties the query

    /// C5 (clear half): the `searchClearButton` empties a non-empty query
    /// and the sheet reverts from the no-results state back to the idle
    /// `searchEmptyPromptView`. Verifies the re-skin preserved the clear
    /// behavior end-to-end. (The result-tap-navigation half of C5 is
    /// covered by `TXTSearchTapHighlightNavigationTests`.)
    func test_verify_feature_63_C5_clear_button_empties_query_to_idle_prompt() throws {
        let app = launch()
        XCTAssertTrue(
            openSeededBook(in: app),
            "The seeded mini-epub3 EPUB should open into the reader"
        )
        openSearchSheet(in: app)
        let searchField = waitForSearchField(in: app)

        // Type a zero-match query so the sheet leaves the idle state for
        // a deterministic, fast non-idle state (no indexing-timing race
        // on result population).
        enterQuery("zzzznotfoundqqq", into: searchField)
        XCTAssertTrue(
            noResultsElement(in: app).waitForExistence(timeout: 45),
            "Precondition: the no-results state should appear before clearing"
        )

        // The clear button (`xmark.circle.fill`) is shown only while the
        // query is non-empty. Tapping it empties the query.
        let clearButton = app.buttons[AccessibilityID.searchClearButton]
        XCTAssertTrue(
            clearButton.waitForExistence(timeout: 5),
            "C5: the `searchClearButton` should be present while the query " +
            "is non-empty"
        )
        clearButton.tap()

        // Emptying the query reverts the sheet to the idle prompt.
        XCTAssertTrue(
            idlePromptElement(in: app).waitForExistence(timeout: 10),
            "C5: clearing the query should revert the sheet to the idle " +
            "`searchEmptyPromptView` — the re-skin preserved the clear behavior"
        )
        // The clear button itself should disappear once the query is empty.
        XCTAssertFalse(
            clearButton.exists,
            "C5: the `searchClearButton` should be hidden once the query is empty"
        )
        // And the no-results state must be gone — clearing returns to idle.
        XCTAssertFalse(
            noResultsElement(in: app).exists,
            "C5: the no-results state must be gone after the query is cleared"
        )
    }
}
