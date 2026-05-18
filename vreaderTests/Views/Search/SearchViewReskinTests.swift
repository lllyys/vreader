// Purpose: Feature #63 WI-1 — behavior tests for the re-skinned search
// sheet's custom search bar. The v2 re-skin replaces the system
// `.searchable` bar + NavigationStack `Done` toolbar with a custom
// in-sheet `SearchBar` (search glyph + bound text field + clear button
// + "Cancel"). These tests pin the behavior-preserving contract: the
// clear button empties the bound query, "Cancel" runs the dismiss
// closure, and a result tap still forwards the result's `Locator`.
//
// @coordinates-with: SearchBar.swift, SearchView.swift,
//   SearchViewActions.swift, SearchViewModel.swift, SearchService.swift,
//   Locator.swift

import Testing
import Foundation
@testable import vreader

@Suite("Search sheet re-skin — feature #63 WI-1")
@MainActor
struct SearchViewReskinTests {

    // MARK: - Fixtures

    private static let testFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 1024,
        format: .txt
    )

    private static func makeLocator(offset: Int = 0) -> Locator {
        Locator(
            bookFingerprint: testFP,
            href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: offset,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    private static func makeResult(id: String, offset: Int) -> SearchResult {
        SearchResult(
            id: id,
            snippet: "snippet \(id)",
            locator: makeLocator(offset: offset),
            sourceContext: "Section 1"
        )
    }

    /// A stub search service that returns a pre-set page synchronously.
    private actor StubService: SearchProviding {
        let stubbedPage: SearchResultPage
        init(page: SearchResultPage) { self.stubbedPage = page }
        func indexBook(
            fingerprint: DocumentFingerprint,
            textUnits: [TextUnit],
            segmentBaseOffsets: [Int: Int]?
        ) async throws {}
        func search(
            query: String,
            bookFingerprint: DocumentFingerprint,
            page: Int,
            pageSize: Int
        ) async throws -> SearchResultPage { stubbedPage }
        func removeIndex(fingerprint: DocumentFingerprint) async throws {}
        func isIndexed(fingerprint: DocumentFingerprint) async -> Bool { true }
    }

    // MARK: - Clear button

    @Test("The clear action empties the view-model query string")
    func clearActionEmptiesQuery() {
        let viewModel = SearchViewModel(
            searchService: StubService(
                page: SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
            ),
            bookFingerprint: Self.testFP
        )
        viewModel.query = "elizabeth"
        #expect(viewModel.query == "elizabeth")

        // The custom bar's clear button performs exactly this mutation.
        SearchBar.clear(viewModel)
        #expect(viewModel.query.isEmpty)
    }

    @Test("Clearing a non-empty query drops the pending results")
    func clearDropsResults() async {
        let page = SearchResultPage(
            results: [Self.makeResult(id: "r1", offset: 1)],
            page: 0, hasMore: false, totalEstimate: 1
        )
        let viewModel = SearchViewModel(
            searchService: StubService(page: page),
            bookFingerprint: Self.testFP,
            debounceInterval: .zero
        )
        viewModel.query = "bingley"
        // Allow the debounced search to complete.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!viewModel.results.isEmpty)

        SearchBar.clear(viewModel)
        #expect(viewModel.query.isEmpty)
        // Clearing the query immediately resets results (SearchViewModel
        // contract — onQueryChanged clears synchronously on empty input).
        #expect(viewModel.results.isEmpty)
    }

    // MARK: - Cancel button

    @Test("The Cancel button runs the dismiss closure exactly once")
    func cancelInvokesDismiss() {
        var dismissCount = 0
        let actions = SearchViewActions(
            onCancel: { dismissCount += 1 },
            onNavigate: { _ in }
        )
        actions.cancel()
        #expect(dismissCount == 1)
    }

    // MARK: - Result tap (behavior-preserving guard)

    @Test("Tapping a result forwards that result's Locator to onNavigate")
    func resultTapForwardsLocator() {
        var navigated: Locator?
        let actions = SearchViewActions(
            onCancel: {},
            onNavigate: { navigated = $0 }
        )
        let result = Self.makeResult(id: "r7", offset: 42)
        actions.navigate(to: result)
        #expect(navigated == result.locator)
        #expect(navigated?.charOffsetUTF16 == 42)
    }

    @Test("Navigate and cancel are independent — navigate does not dismiss")
    func navigateDoesNotDismiss() {
        var dismissCount = 0
        var navigateCount = 0
        let actions = SearchViewActions(
            onCancel: { dismissCount += 1 },
            onNavigate: { _ in navigateCount += 1 }
        )
        actions.navigate(to: Self.makeResult(id: "r1", offset: 1))
        #expect(navigateCount == 1)
        #expect(dismissCount == 0)
    }

    // MARK: - Content state resolution

    @Test("An empty query with no results shows the search prompt")
    func emptyQueryShowsPrompt() {
        let state = SearchView.contentState(
            isSearching: false, resultsEmpty: true,
            noResultsFound: false, query: ""
        )
        #expect(state == .prompt)
    }

    @Test("A whitespace-only query shows the prompt, not a zero-result list")
    func whitespaceOnlyQueryShowsPrompt() {
        // `SearchViewModel` treats trimmed-empty input as empty and
        // clears results, but `query` itself stays "   ". The content
        // state must trim before deciding — otherwise the grouped list
        // renders a misleading "0 matches in 0 sections".
        let state = SearchView.contentState(
            isSearching: false, resultsEmpty: true,
            noResultsFound: false, query: "   \n\t"
        )
        #expect(state == .prompt)
    }

    @Test("A first search in flight with no results yet shows loading")
    func searchingWithNoResultsShowsLoading() {
        let state = SearchView.contentState(
            isSearching: true, resultsEmpty: true,
            noResultsFound: false, query: "darcy"
        )
        #expect(state == .loading)
    }

    @Test("A non-empty query that found nothing shows the no-results state")
    func noResultsFoundShowsNoResults() {
        let state = SearchView.contentState(
            isSearching: false, resultsEmpty: true,
            noResultsFound: true, query: "zzzznotfound"
        )
        #expect(state == .noResults)
    }

    @Test("A query with results shows the grouped results list")
    func queryWithResultsShowsResults() {
        let state = SearchView.contentState(
            isSearching: false, resultsEmpty: false,
            noResultsFound: false, query: "bingley"
        )
        #expect(state == .results)
    }

    @Test("Appending more results while paginating keeps the results list")
    func paginatingKeepsResultsList() {
        // isSearching is true (loading the next page) but results are
        // already present — must stay on the results list, not flip to
        // the loading splash.
        let state = SearchView.contentState(
            isSearching: true, resultsEmpty: false,
            noResultsFound: false, query: "bingley"
        )
        #expect(state == .results)
    }
}
