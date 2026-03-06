// Purpose: Mock bookmark persistence for unit testing.
//
// @coordinates-with: BookmarkPersisting.swift, BookmarkListViewModelTests.swift

import Foundation
@testable import vreader

/// In-memory mock of BookmarkPersisting for unit tests.
actor MockBookmarkStore: BookmarkPersisting {
    private var bookmarks: [UUID: BookmarkRecord] = [:]
    private var bookIndex: [String: [UUID]] = [:]

    private(set) var addCallCount = 0
    private(set) var removeCallCount = 0
    private(set) var fetchCallCount = 0
    private(set) var isBookmarkedCallCount = 0

    var addError: (any Error & Sendable)?
    var removeError: (any Error & Sendable)?
    var fetchError: (any Error & Sendable)?

    func addBookmark(locator: Locator, title: String?, toBookWithKey key: String) async throws -> BookmarkRecord {
        addCallCount += 1
        if let error = addError { throw error }

        let record = BookmarkRecord(
            bookmarkId: UUID(),
            locator: locator,
            profileKey: "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)",
            title: title,
            createdAt: Date(),
            updatedAt: Date()
        )
        bookmarks[record.bookmarkId] = record
        bookIndex[key, default: []].append(record.bookmarkId)
        return record
    }

    func removeBookmark(bookmarkId: UUID) async throws {
        removeCallCount += 1
        if let error = removeError { throw error }

        if bookmarks.removeValue(forKey: bookmarkId) != nil {
            for (bookKey, ids) in bookIndex {
                bookIndex[bookKey] = ids.filter { $0 != bookmarkId }
            }
        }
    }

    func fetchBookmarks(forBookWithKey key: String) async throws -> [BookmarkRecord] {
        fetchCallCount += 1
        if let error = fetchError { throw error }

        let ids = bookIndex[key] ?? []
        return ids.compactMap { bookmarks[$0] }.sorted { $0.createdAt > $1.createdAt }
    }

    func isBookmarked(locator: Locator, forBookWithKey key: String) async throws -> Bool {
        isBookmarkedCallCount += 1
        let profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
        let ids = bookIndex[key] ?? []
        return ids.contains { bookmarks[$0]?.profileKey == profileKey }
    }

    // MARK: - Test Helpers

    func seed(_ record: BookmarkRecord, forBookWithKey key: String) {
        bookmarks[record.bookmarkId] = record
        bookIndex[key, default: []].append(record.bookmarkId)
    }

    func allBookmarks() -> [BookmarkRecord] {
        Array(bookmarks.values)
    }

    func setFetchError(_ error: (any Error & Sendable)?) {
        fetchError = error
    }

    func setAddError(_ error: (any Error & Sendable)?) {
        addError = error
    }

    func reset() {
        bookmarks = [:]
        bookIndex = [:]
        addCallCount = 0
        removeCallCount = 0
        fetchCallCount = 0
        isBookmarkedCallCount = 0
        addError = nil
        removeError = nil
        fetchError = nil
    }
}
