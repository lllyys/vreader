// Purpose: SwiftUI search interface with debounced text field, result list,
// and navigation callback.
//
// Key decisions:
// - Uses SearchViewModel for state management.
// - Tap on result triggers onNavigate callback with Locator.
// - Empty state shown when no results found.
// - Loading indicator during search.
// - Load more button at bottom for pagination.
// - Error alert for search failures.
//
// @coordinates-with SearchViewModel.swift, SearchResultRow.swift, Locator.swift

import SwiftUI

/// Full-text search view for a book.
struct SearchView: View {
    @Bindable var viewModel: SearchViewModel
    let onNavigate: (Locator) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchContent
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        onDismiss()
                    }
                    .accessibilityIdentifier("searchDismissButton")
                }
            }
            .searchable(
                text: $viewModel.query,
                prompt: "Search in book..."
            )
        }
        .alert("Search Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .accessibilityIdentifier("searchView")
    }

    // MARK: - Content

    @ViewBuilder
    private var searchContent: some View {
        if viewModel.isSearching && viewModel.results.isEmpty {
            loadingView
        } else if viewModel.noResultsFound {
            noResultsView
        } else if viewModel.results.isEmpty && viewModel.query.isEmpty {
            emptyPromptView
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        List {
            ForEach(viewModel.results) { result in
                Button {
                    onNavigate(result.locator)
                } label: {
                    SearchResultRow(result: result)
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("searchResult_\(result.id)")
            }

            if viewModel.hasMore {
                loadMoreButton
            }

            if viewModel.isSearching && !viewModel.results.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .accessibilityIdentifier("searchResultsList")
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
                    .foregroundStyle(.blue)
                Spacer()
            }
        }
        .accessibilityIdentifier("loadMoreButton")
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Searching...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .accessibilityIdentifier("searchLoadingView")
    }

    private var noResultsView: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "magnifyingglass")
        } description: {
            Text("No results found for \"\(viewModel.query)\"")
        }
        .accessibilityIdentifier("searchNoResultsView")
    }

    private var emptyPromptView: some View {
        ContentUnavailableView {
            Label("Search", systemImage: "magnifyingglass")
        } description: {
            Text("Enter a search term to find text in this book")
        }
        .accessibilityIdentifier("searchEmptyPromptView")
    }
}
