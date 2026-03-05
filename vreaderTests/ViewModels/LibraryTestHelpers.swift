// Purpose: Shared test helpers for library tests — mock persistence and stubs.

import Foundation
@testable import vreader

// MARK: - MockLibraryPersistence

/// Mock persistence for library operations.
actor MockLibraryPersistence: LibraryPersisting {
    private var books: [String: LibraryBookItem] = [:]
    private(set) var deleteCallCount = 0
    private(set) var deletedKeys: [String] = []
    var fetchError: (any Error)?
    var deleteError: (any Error)?

    func fetchAllLibraryBooks() async throws -> [LibraryBookItem] {
        if let error = fetchError { throw error }
        return Array(books.values)
    }

    func deleteBook(fingerprintKey: String) async throws {
        deleteCallCount += 1
        deletedKeys.append(fingerprintKey)
        if let error = deleteError { throw error }
        books.removeValue(forKey: fingerprintKey)
    }

    // MARK: - Test Helpers

    func seed(_ item: LibraryBookItem) {
        books[item.fingerprintKey] = item
    }

    func seedMany(_ items: [LibraryBookItem]) {
        for item in items {
            books[item.fingerprintKey] = item
        }
    }

    func reset() {
        books = [:]
        deleteCallCount = 0
        deletedKeys = []
        fetchError = nil
        deleteError = nil
    }

    func allBooks() -> [LibraryBookItem] {
        Array(books.values)
    }

    func setFetchError(_ error: (any Error)?) {
        self.fetchError = error
    }
}

// MARK: - LibraryBookItem Stub

extension LibraryBookItem {
    /// Creates a test item with minimal required fields.
    static func stub(
        fingerprintKey: String = "epub:abc123:1024",
        title: String = "Test Book",
        author: String? = nil,
        format: String = "epub",
        addedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        totalReadingSeconds: Int = 0,
        lastReadAt: Date? = nil,
        averagePagesPerHour: Double? = nil,
        averageWordsPerMinute: Double? = nil
    ) -> LibraryBookItem {
        LibraryBookItem(
            fingerprintKey: fingerprintKey,
            title: title,
            author: author,
            coverImagePath: nil,
            format: format,
            addedAt: addedAt,
            lastOpenedAt: lastOpenedAt,
            isFavorite: false,
            totalReadingSeconds: totalReadingSeconds,
            lastReadAt: lastReadAt,
            averagePagesPerHour: averagePagesPerHour,
            averageWordsPerMinute: averageWordsPerMinute
        )
    }
}

// MARK: - Test Errors

enum LibraryTestError: Error {
    case networkFailure
}
