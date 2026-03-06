// Purpose: List of bookmarks with navigation and swipe-to-delete.
// Shows empty state when no bookmarks exist.
//
// @coordinates-with: BookmarkListViewModel.swift, BookmarkRecord.swift

import SwiftUI

/// Displays a list of bookmarks for a book.
struct BookmarkListView: View {
    @Bindable var viewModel: BookmarkListViewModel
    let onNavigate: (Locator) -> Void

    var body: some View {
        Group {
            if viewModel.isEmpty {
                emptyState
            } else {
                bookmarkList
            }
        }
        .navigationTitle("Bookmarks")
        .task {
            await viewModel.loadBookmarks()
        }
        .alert("Error", isPresented: .init(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Bookmarks", systemImage: "bookmark")
        } description: {
            Text("Add bookmarks to quickly return to important pages.")
        }
        .accessibilityIdentifier("bookmarkEmptyState")
    }

    @ViewBuilder
    private var bookmarkList: some View {
        List {
            ForEach(viewModel.bookmarks) { bookmark in
                Button {
                    onNavigate(bookmark.locator)
                } label: {
                    BookmarkRowView(bookmark: bookmark)
                }
                .accessibilityIdentifier("bookmarkRow-\(bookmark.bookmarkId)")
            }
            .onDelete(perform: deleteBookmarks)
        }
    }

    private func deleteBookmarks(at offsets: IndexSet) {
        for index in offsets {
            let bookmark = viewModel.bookmarks[index]
            Task {
                await viewModel.removeBookmark(bookmarkId: bookmark.bookmarkId)
            }
        }
    }
}

// MARK: - Bookmark Row

private struct BookmarkRowView: View {
    let bookmark: BookmarkRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 4) {
                Text(bookmark.title ?? "Untitled Bookmark")
                    .font(.body)
                    .lineLimit(1)

                Text(formattedDate(bookmark.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
