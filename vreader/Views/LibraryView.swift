// Purpose: Main library view displaying the user's book collection.
// Supports grid/list toggle, sorting, pull-to-refresh, swipe-to-delete,
// and empty state with onboarding CTA.
//
// Key decisions:
// - Uses .refreshable for pull-to-refresh (delegates to ViewModel throttle).
// - Grid uses adaptive columns for responsive layout.
// - Sort picker and view mode toggle in toolbar.
// - Empty state shown when library is empty.
// - Swipe-to-delete in both grid and list modes.
//
// @coordinates-with: LibraryViewModel.swift, BookCardView.swift, BookRowView.swift

import SwiftUI
import UniformTypeIdentifiers

/// Main library view for the book collection.
struct LibraryView: View {
    @State private var viewModel: LibraryViewModel
    @State private var bookToDelete: LibraryBookItem?
    @State private var isShowingImporter = false

    init(viewModel: LibraryViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isEmpty {
                    emptyState
                } else {
                    bookCollection
                }
            }
            .navigationTitle("Library")
            .toolbar {
                toolbarContent
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                await viewModel.loadBooks()
            }
            .alert("Error", isPresented: hasError) {
                Button("OK") { viewModel.clearError() }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert(
                "Delete Book",
                isPresented: .init(
                    get: { bookToDelete != nil },
                    set: { if !$0 { bookToDelete = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { bookToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let book = bookToDelete {
                        let key = book.fingerprintKey
                        bookToDelete = nil
                        Task { await viewModel.deleteBook(fingerprintKey: key) }
                    }
                }
            } message: {
                if let book = bookToDelete {
                    Text("Are you sure you want to delete \"\(book.title)\"? This cannot be undone.")
                }
            }
            .fileImporter(
                isPresented: $isShowingImporter,
                allowedContentTypes: [.epub, .pdf, .plainText],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task { await viewModel.importFiles(urls) }
                case .failure:
                    break
                }
            }
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private var bookCollection: some View {
        switch viewModel.viewMode {
        case .grid:
            gridView
        case .list:
            listView
        }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 180))],
                spacing: 16
            ) {
                ForEach(viewModel.books) { book in
                    BookCardView(book: book)
                        .contextMenu {
                            deleteButton(for: book)
                        }
                }
            }
            .padding()
        }
    }

    private var listView: some View {
        List {
            ForEach(viewModel.books) { book in
                BookRowView(book: book)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        deleteButton(for: book)
                    }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Your Library is Empty")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Import books to start reading. Supports EPUB, PDF, and TXT formats.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                isShowingImporter = true
            } label: {
                Label("Import Books", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("importBooksButton")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emptyLibraryState")
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                viewModel.toggleViewMode()
            } label: {
                Image(systemName: viewModel.viewMode == .grid
                    ? "list.bullet"
                    : "square.grid.2x2")
            }
            .accessibilityLabel(viewModel.viewMode == .grid
                ? "Switch to list view"
                : "Switch to grid view")
            .accessibilityIdentifier("viewModeToggle")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Sort By", selection: $viewModel.sortOrder) {
                    ForEach(LibrarySortOrder.allCases) { order in
                        Text(order.label).tag(order)
                    }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort books")
            .accessibilityIdentifier("sortPicker")
        }
    }

    // MARK: - Delete Actions

    private func deleteButton(for book: LibraryBookItem) -> some View {
        Button(role: .destructive) {
            bookToDelete = book
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Helpers

    private var hasError: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )
    }
}
