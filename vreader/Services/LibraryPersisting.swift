// Purpose: Protocol for library-specific persistence operations.
// Separates library queries from book import persistence (BookPersisting).
//
// Key decisions:
// - Separate protocol from BookPersisting to follow single-responsibility.
// - Returns LibraryBookItem value types (not @Model objects).
// - Actor-conformant: all methods are async throws.

import Foundation

/// Protocol for library persistence operations, enabling mock injection in tests.
protocol LibraryPersisting: Sendable {
    /// Fetches all books with their reading stats for library display.
    func fetchAllLibraryBooks() async throws -> [LibraryBookItem]

    /// Deletes a book and all associated data (sessions, stats, bookmarks, etc.).
    func deleteBook(fingerprintKey: String) async throws
}
