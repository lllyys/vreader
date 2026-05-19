// Purpose: SwiftUI search interface with a debounced text field, a
// grouped result list, and a navigation callback.
//
// Re-skinned for feature #63 visual-identity v2:
// - WI-1: the system `.searchable` bar + `NavigationStack` `Done`
//   toolbar replaced by the custom in-sheet `SearchBar`.
// - WI-2: the plain `List` replaced by `SearchResultsGroupedList`
//   (results grouped by `sourceContext`); the loading / no-results /
//   empty-prompt states restyled to the design bundle's
//   `vreader-search.jsx`.
// Behavior is preserved — `SearchViewModel`, `SearchResult`, the FTS5
// query / debounce / pagination, and the result-tap → `Locator`
// navigation are all unchanged.
//
// Key decisions:
// - Uses SearchViewModel for state management.
// - Tap on result triggers onNavigate callback with Locator.
// - Restyled empty / no-results states (`SearchStateViews`).
// - Loading indicator during search.
// - Load more affordance at the bottom for pagination (passed into
//   `SearchResultsGroupedList` as its footer slot).
// - Error alert for search failures.
// - `theme` is a presentation input (the feature #60 re-skin pattern,
//   matching the reader sheets); defaulted to `.paper` so it is
//   strictly additive — the three behavioral inputs are unchanged.
//
// @coordinates-with SearchViewModel.swift, SearchResultsGroupedList.swift,
//   SearchResultRow.swift, SearchBar.swift, SearchViewActions.swift,
//   SearchStateViews.swift, ReaderThemeV2.swift, Locator.swift

import SwiftUI

/// Full-text search view for a book.
struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    /// Visual-identity-v2 theme tokens for the re-skinned chrome
    /// (feature #63). Defaults to `.paper` so callers / previews that
    /// omit it keep working — a strictly additive presentation input,
    /// not a behavioral change.
    var theme: ReaderThemeV2 = .paper
    let onNavigate: (Locator) -> Void
    let onDismiss: () -> Void

    /// The book title for the search-bar placeholder ("Search {title}").
    /// Defaults to a neutral phrase when the host omits it.
    var bookTitle: String = "this book"

    /// Bundles the host callbacks for testable wiring (WI-1).
    private var actions: SearchViewActions {
        Self.makeActions(onCancel: onDismiss, onNavigate: onNavigate)
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(
                viewModel: viewModel,
                theme: theme,
                placeholder: "Search \(bookTitle)",
                onCancel: { actions.cancel() }
            )
            searchContent
        }
        .background(Color(theme.sheetSurfaceColor).ignoresSafeArea())
        .alert("Search Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        // Bug #223 / GH #891: the feature-#63 v2 re-skin replaced this
        // view's `NavigationStack` root with a plain `VStack`. Without an
        // explicit container, SwiftUI propagates the identifier onto every
        // leaf descendant (`Image`/`TextField`/`Button`/`StaticText`), so
        // neither this `searchView` id nor the host's outer `searchSheet`
        // id resolves as a queryable `app.otherElements` container.
        // `.accessibilityElement(children: .contain)` collapses the
        // subtree into one container element the identifier names — the
        // same Bug #209 root-cause-(C) fix used on `ReaderSettingsPanel`
        // and the reader annotations sheets.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("searchView")
    }

    // MARK: - Testable wiring

    /// Builds the sheet's callback contract — extracted so `SearchView`'s
    /// wiring is verifiable without rendering the SwiftUI view.
    static func makeActions(
        onCancel: @escaping () -> Void,
        onNavigate: @escaping (Locator) -> Void
    ) -> SearchViewActions {
        SearchViewActions(onCancel: onCancel, onNavigate: onNavigate)
    }

    // MARK: - Content

    @ViewBuilder
    private var searchContent: some View {
        switch Self.contentState(
            isSearching: viewModel.isSearching,
            resultsEmpty: viewModel.results.isEmpty,
            noResultsFound: viewModel.noResultsFound,
            query: viewModel.query
        ) {
        case .loading:
            loadingView
        case .noResults:
            SearchNoResultsView(query: viewModel.query, theme: theme)
        case .prompt:
            SearchPromptView(theme: theme)
        case .results:
            resultsList
        }
    }

    /// The four mutually-exclusive content states the sheet body shows.
    enum SearchContentState: Equatable {
        /// First search in flight, nothing to show yet.
        case loading
        /// A non-empty query produced no matches.
        case noResults
        /// The empty-query prompt (the search-this-book explainer).
        case prompt
        /// The grouped results list.
        case results
    }

    /// Resolves which content state to render from the view-model's
    /// observable surface. Pure + static so it is unit-testable without
    /// rendering. The prompt branch keys on the *trimmed* query — a
    /// whitespace-only query (`"   "`) is empty input, not a
    /// zero-result search, and must show the prompt rather than a
    /// "0 matches" grouped list (Gate-4 round-1 finding).
    static func contentState(
        isSearching: Bool,
        resultsEmpty: Bool,
        noResultsFound: Bool,
        query: String
    ) -> SearchContentState {
        if isSearching && resultsEmpty {
            return .loading
        }
        if noResultsFound {
            return .noResults
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if resultsEmpty && trimmed.isEmpty {
            return .prompt
        }
        return .results
    }

    /// The grouped results list — groups by `sourceContext`, with the
    /// pagination affordance supplied as the trailing footer slot.
    private var resultsList: some View {
        SearchResultsGroupedList(
            results: viewModel.results,
            query: viewModel.query,
            theme: theme,
            onSelect: { actions.navigate(to: $0) },
            footer: { paginationFooter }
        )
    }

    /// Load-more button + the in-flight appending spinner.
    @ViewBuilder
    private var paginationFooter: some View {
        if viewModel.hasMore {
            loadMoreButton
        }
        if viewModel.isSearching && !viewModel.results.isEmpty {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        }
    }

    private var loadMoreButton: some View {
        Button {
            Task {
                await viewModel.loadMore()
            }
        } label: {
            HStack {
                Spacer()
                Text("Load more results")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(theme.accentColor))
                Spacer()
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("loadMoreButton")
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Searching...")
                .font(.subheadline)
                .foregroundStyle(Color(theme.subColor))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("searchLoadingView")
    }
}
