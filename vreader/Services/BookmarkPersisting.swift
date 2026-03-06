// Purpose: Protocol for bookmark persistence operations.
// Enables mock injection in tests.
//
// @coordinates-with: PersistenceActor+Bookmarks.swift, BookmarkRecord.swift

import Foundation

/// Protocol for bookmark persistence operations, enabling mock injection in tests.
protocol BookmarkPersisting: Sendable {
    /// Adds a bookmark to a book. Returns the created record.
    func addBookmark(locator: Locator, title: String?, toBookWithKey key: String) async throws -> BookmarkRecord

    /// Removes a bookmark by its ID.
    func removeBookmark(bookmarkId: UUID) async throws

    /// Fetches all bookmarks for a book, ordered by creation date (newest first).
    func fetchBookmarks(forBookWithKey key: String) async throws -> [BookmarkRecord]

    /// Checks whether a bookmark exists at the given locator for a book.
    func isBookmarked(locator: Locator, forBookWithKey key: String) async throws -> Bool
}
