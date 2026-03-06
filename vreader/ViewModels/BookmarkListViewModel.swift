// Purpose: ViewModel for bookmark list — load, add, remove, toggle.
// Manages bookmarks for a single book.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Protocol-based persistence for testability.
// - Toggle uses profileKey matching for idempotent add/remove.
//
// @coordinates-with: BookmarkPersisting.swift, BookmarkRecord.swift, BookmarkListView.swift

import Foundation

/// ViewModel for bookmark list display and management.
@Observable
@MainActor
final class BookmarkListViewModel {

    // MARK: - Published State

    /// All bookmarks for the current book, newest first.
    private(set) var bookmarks: [BookmarkRecord] = []

    /// Whether the bookmark list is empty.
    var isEmpty: Bool { bookmarks.isEmpty }

    /// Error message from the last failed operation.
    var errorMessage: String?

    // MARK: - Dependencies

    private let bookFingerprintKey: String
    private let store: any BookmarkPersisting

    // MARK: - Init

    init(bookFingerprintKey: String, store: any BookmarkPersisting) {
        self.bookFingerprintKey = bookFingerprintKey
        self.store = store
    }

    // MARK: - Load

    /// Loads all bookmarks for the current book.
    func loadBookmarks() async {
        errorMessage = nil
        do {
            bookmarks = try await store.fetchBookmarks(forBookWithKey: bookFingerprintKey)
        } catch {
            bookmarks = []
            errorMessage = "Failed to load bookmarks."
        }
    }

    // MARK: - Add

    /// Adds a bookmark at the given locator.
    func addBookmark(locator: Locator, title: String?) async {
        errorMessage = nil
        do {
            let record = try await store.addBookmark(
                locator: locator,
                title: title,
                toBookWithKey: bookFingerprintKey
            )
            bookmarks.insert(record, at: 0)
        } catch {
            errorMessage = "Failed to add bookmark."
        }
    }

    // MARK: - Remove

    /// Removes a bookmark by its ID.
    func removeBookmark(bookmarkId: UUID) async {
        errorMessage = nil
        do {
            try await store.removeBookmark(bookmarkId: bookmarkId)
            bookmarks.removeAll { $0.bookmarkId == bookmarkId }
        } catch {
            errorMessage = "Failed to remove bookmark."
        }
    }

    // MARK: - Toggle

    /// Toggles a bookmark at the given locator.
    /// If already bookmarked, removes it. Otherwise, adds it.
    func toggleBookmark(locator: Locator, title: String?) async {
        let profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
        if let existing = bookmarks.first(where: { $0.profileKey == profileKey }) {
            await removeBookmark(bookmarkId: existing.bookmarkId)
        } else {
            await addBookmark(locator: locator, title: title)
        }
    }

    // MARK: - Query

    /// Checks whether a bookmark exists at the given locator.
    func isBookmarked(at locator: Locator) async -> Bool {
        do {
            return try await store.isBookmarked(
                locator: locator,
                forBookWithKey: bookFingerprintKey
            )
        } catch {
            return false
        }
    }
}
