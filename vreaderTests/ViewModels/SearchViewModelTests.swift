// Purpose: Tests for SearchViewModel — query debouncing, pagination,
// empty query, error handling, cancel previous search.

import Testing
import Foundation
@testable import vreader

// MARK: - Stub Search Service

/// Stub SearchProviding for ViewModel tests.
actor StubSearchService: SearchProviding {
    var stubbedPage = SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    var searchDelay: Duration?
    var shouldThrow = false
    private(set) var searchCallCount = 0
    private(set) var lastQuery: String?
    private(set) var lastPage: Int?

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
    ) async throws -> SearchResultPage {
        searchCallCount += 1
        lastQuery = query
        lastPage = page
        if let delay = searchDelay {
            try await Task.sleep(for: delay)
        }
        if shouldThrow {
            throw StubSearchError.searchFailed
        }
        return stubbedPage
    }

    func removeIndex(fingerprint: DocumentFingerprint) async throws {}
    func isIndexed(fingerprint: DocumentFingerprint) async -> Bool { false }

    // Helpers
    func setStubPage(_ page: SearchResultPage) { stubbedPage = page }
    func setDelay(_ delay: Duration?) { searchDelay = delay }
    func setThrow(_ value: Bool) { shouldThrow = value }
}

enum StubSearchError: Error, LocalizedError {
    case searchFailed

    var errorDescription: String? { "Search failed" }
}

@Suite("SearchViewModel")
struct SearchViewModelTests {

    // MARK: - Helpers

    private static let testFP = DocumentFingerprint(
        contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
        fileByteCount: 1024,
        format: .txt
    )

    private static func makeLocator() -> Locator {
        Locator(
            bookFingerprint: testFP,
            href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: 0,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
    }

    private static func makeResults(count: Int) -> [SearchResult] {
        (0..<count).map { i in
            SearchResult(
                id: "test:unit:\(i):0",
                snippet: "Result \(i)",
                locator: makeLocator(),
                sourceContext: "Section \(i + 1)"
            )
        }
    }

    // MARK: - Empty Query

    @Test @MainActor func emptyQueryClearsResults() async {
        let stub = StubSearchService()
        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            debounceInterval: .milliseconds(10)
        )

        vm.query = ""
        #expect(vm.results.isEmpty)
        #expect(!vm.isSearching)
    }

    @Test @MainActor func settingQueryToEmptyAfterSearchClearsResults() async {
        let stub = StubSearchService()
        let results = Self.makeResults(count: 3)
        await stub.setStubPage(SearchResultPage(
            results: results, page: 0, hasMore: false, totalEstimate: 3
        ))

        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            debounceInterval: .milliseconds(10)
        )

        vm.query = "test"
        try? await Task.sleep(for: .milliseconds(50))

        vm.query = ""
        #expect(vm.results.isEmpty)
    }

    // MARK: - Query Triggers Search

    @Test @MainActor func queryTriggersSearchAfterDebounce() async {
        let stub = StubSearchService()
        let results = Self.makeResults(count: 2)
        await stub.setStubPage(SearchResultPage(
            results: results, page: 0, hasMore: false, totalEstimate: 2
        ))

        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            debounceInterval: .milliseconds(10)
        )

        vm.query = "hello"
        try? await Task.sleep(for: .milliseconds(100))

        #expect(vm.results.count == 2)
        let count = await stub.searchCallCount
        #expect(count >= 1)
    }

    // MARK: - No Results

    @Test @MainActor func noResultsFoundTrue() async {
        let stub = StubSearchService()
        await stub.setStubPage(SearchResultPage(
            results: [], page: 0, hasMore: false, totalEstimate: 0
        ))

        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            debounceInterval: .milliseconds(10)
        )

        vm.query = "nonexistent"
        try? await Task.sleep(for: .milliseconds(100))

        #expect(vm.noResultsFound)
    }

    @Test @MainActor func noResultsFoundFalseWhenQueryEmpty() async {
        let stub = StubSearchService()
        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            debounceInterval: .milliseconds(10)
        )

        vm.query = ""
        #expect(!vm.noResultsFound)
    }

    // MARK: - Pagination

    @Test @MainActor func loadMoreIncrementsPage() async {
        let stub = StubSearchService()
        let results = Self.makeResults(count: 3)
        await stub.setStubPage(SearchResultPage(
            results: results, page: 0, hasMore: true, totalEstimate: nil
        ))

        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            pageSize: 3,
            debounceInterval: .milliseconds(10)
        )

        vm.query = "test"
        try? await Task.sleep(for: .milliseconds(100))

        #expect(vm.hasMore)

        // Update stub for page 2
        let moreResults = Self.makeResults(count: 2)
        await stub.setStubPage(SearchResultPage(
            results: moreResults, page: 1, hasMore: false, totalEstimate: nil
        ))

        await vm.loadMore()

        #expect(vm.results.count == 5) // 3 + 2
        #expect(!vm.hasMore)
    }

    @Test @MainActor func loadMoreDoesNothingWhenNoMore() async {
        let stub = StubSearchService()
        let results = Self.makeResults(count: 1)
        await stub.setStubPage(SearchResultPage(
            results: results, page: 0, hasMore: false, totalEstimate: 1
        ))

        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            debounceInterval: .milliseconds(10)
        )

        vm.query = "test"
        try? await Task.sleep(for: .milliseconds(100))

        let countBefore = await stub.searchCallCount
        await vm.loadMore()
        let countAfter = await stub.searchCallCount

        #expect(countAfter == countBefore) // No additional call
    }

    // MARK: - Error Handling

    @Test @MainActor func searchErrorSetsErrorMessage() async {
        let stub = StubSearchService()
        await stub.setThrow(true)

        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            debounceInterval: .milliseconds(10)
        )

        vm.query = "test"
        try? await Task.sleep(for: .milliseconds(100))

        #expect(vm.errorMessage != nil)
    }

    @Test @MainActor func clearErrorResetsMessage() async {
        let stub = StubSearchService()
        await stub.setThrow(true)

        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            debounceInterval: .milliseconds(10)
        )

        vm.query = "test"
        try? await Task.sleep(for: .milliseconds(100))

        vm.clearError()
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Debounce

    @Test @MainActor func rapidQueryChangesDebounced() async {
        let stub = StubSearchService()
        let results = Self.makeResults(count: 1)
        await stub.setStubPage(SearchResultPage(
            results: results, page: 0, hasMore: false, totalEstimate: 1
        ))

        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            debounceInterval: .milliseconds(50)
        )

        // Rapid changes — only the last should trigger a search
        vm.query = "h"
        vm.query = "he"
        vm.query = "hel"
        vm.query = "hell"
        vm.query = "hello"

        try? await Task.sleep(for: .milliseconds(150))

        // Should only have searched once (for "hello")
        let count = await stub.searchCallCount
        #expect(count == 1)
        let lastQuery = await stub.lastQuery
        #expect(lastQuery == "hello")
    }

    // MARK: - Cancel Previous Search

    @Test @MainActor func newQueryCancelsPreviousSearch() async {
        let stub = StubSearchService()
        await stub.setDelay(.milliseconds(200))

        let results = Self.makeResults(count: 1)
        await stub.setStubPage(SearchResultPage(
            results: results, page: 0, hasMore: false, totalEstimate: 1
        ))

        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            debounceInterval: .milliseconds(10)
        )

        vm.query = "first"
        try? await Task.sleep(for: .milliseconds(30))

        // Change query before first search completes
        vm.query = "second"
        try? await Task.sleep(for: .milliseconds(300))

        // Should have results from "second" search, not "first"
        let lastQuery = await stub.lastQuery
        #expect(lastQuery == "second")
    }

    // MARK: - Load More Error Rollback

    @Test @MainActor func loadMoreRollsBackPageOnError() async {
        let stub = StubSearchService()
        let results = Self.makeResults(count: 3)
        await stub.setStubPage(SearchResultPage(
            results: results, page: 0, hasMore: true, totalEstimate: nil
        ))

        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            pageSize: 3,
            debounceInterval: .milliseconds(10)
        )

        vm.query = "test"
        try? await Task.sleep(for: .milliseconds(100))
        #expect(vm.results.count == 3)

        // Make next search fail
        await stub.setThrow(true)
        await vm.loadMore()

        // Error should be set, but results should remain
        #expect(vm.errorMessage != nil)
        #expect(vm.results.count == 3)

        // After clearing error and fixing stub, loadMore should retry same page
        vm.clearError()
        await stub.setThrow(false)
        let moreResults = Self.makeResults(count: 2)
        await stub.setStubPage(SearchResultPage(
            results: moreResults, page: 1, hasMore: false, totalEstimate: nil
        ))
        await vm.loadMore()
        #expect(vm.results.count == 5)
    }

    // MARK: - Whitespace Query

    @Test @MainActor func whitespaceOnlyQueryClearsResults() async {
        let stub = StubSearchService()
        let vm = SearchViewModel(
            searchService: stub,
            bookFingerprint: Self.testFP,
            debounceInterval: .milliseconds(10)
        )

        vm.query = "   "
        try? await Task.sleep(for: .milliseconds(50))

        #expect(vm.results.isEmpty)
        #expect(!vm.isSearching)
    }
}
