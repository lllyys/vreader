// Purpose: ViewModel for full-text search with debounced query and pagination.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - 300ms debounce on query changes to avoid excessive FTS5 queries.
// - Cancels previous search on new query input.
// - Empty query immediately clears results.
// - Pagination via loadMore() for infinite scroll.
// - Uses protocol SearchProviding for testability.
//
// @coordinates-with SearchService.swift, SearchView.swift

import Foundation

/// ViewModel for the search interface.
@Observable
@MainActor
final class SearchViewModel {

    // MARK: - Published State

    /// Current search query text.
    var query: String = "" {
        didSet {
            if oldValue != query {
                onQueryChanged()
            }
        }
    }

    /// Current page of search results.
    private(set) var results: [SearchResult] = []

    /// Whether a search is in progress.
    private(set) var isSearching = false

    /// Whether more results are available.
    private(set) var hasMore = false

    /// Error message from the last failed search, if any.
    var errorMessage: String?

    /// Whether no results were found for a non-empty query.
    var noResultsFound: Bool {
        !query.isEmpty && results.isEmpty && !isSearching && errorMessage == nil && hasSearched
    }

    // MARK: - Private

    private let searchService: any SearchProviding
    private let bookFingerprint: DocumentFingerprint
    private let pageSize: Int
    private let debounceInterval: Duration

    private var currentPage = 0
    private var searchTask: Task<Void, Never>?
    private var hasSearched = false

    // MARK: - Init

    init(
        searchService: any SearchProviding,
        bookFingerprint: DocumentFingerprint,
        pageSize: Int = 20,
        debounceInterval: Duration = .milliseconds(300)
    ) {
        self.searchService = searchService
        self.bookFingerprint = bookFingerprint
        self.pageSize = pageSize
        self.debounceInterval = debounceInterval
    }

    // MARK: - Actions

    /// Loads the next page of results.
    func loadMore() async {
        guard hasMore, !isSearching else { return }
        let previousPage = currentPage
        currentPage += 1
        await performSearch(appendResults: true)
        // Rollback page on failure so retry doesn't skip results
        if errorMessage != nil {
            currentPage = previousPage
        }
    }

    /// Clears the current error message.
    func clearError() {
        errorMessage = nil
    }

    /// Re-triggers the current search if the user already has a query.
    /// Called after the search index finishes building so results appear
    /// without the user needing to retype.
    func retriggerIfNeeded() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task { await resetAndSearch() }
    }

    // MARK: - Private

    private func onQueryChanged() {
        // Cancel any pending search
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            results = []
            hasMore = false
            currentPage = 0
            isSearching = false
            errorMessage = nil
            hasSearched = false
            return
        }

        // Debounced search
        searchTask = Task { [weak self, debounceInterval] in
            do {
                try await Task.sleep(for: debounceInterval)
            } catch {
                return // Cancelled
            }
            await self?.resetAndSearch()
        }
    }

    private func resetAndSearch() async {
        currentPage = 0
        results = []
        hasMore = false
        await performSearch(appendResults: false)
    }

    private func performSearch(appendResults: Bool) async {
        let currentQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentQuery.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let page = try await searchService.search(
                query: currentQuery,
                bookFingerprint: bookFingerprint,
                page: currentPage,
                pageSize: pageSize
            )

            // Check if query changed while we were searching
            guard query.trimmingCharacters(in: .whitespacesAndNewlines) == currentQuery else {
                return
            }

            if appendResults {
                results.append(contentsOf: page.results)
            } else {
                results = page.results
            }
            hasMore = page.hasMore
            hasSearched = true
        } catch {
            if !(error is CancellationError) {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }
}
