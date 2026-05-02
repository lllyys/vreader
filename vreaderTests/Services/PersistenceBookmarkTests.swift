// Purpose: Tests for PersistenceActor+Bookmarks — CRUD, deduplication, and edge cases.
// Phase R1 of the refactoring plan.

import Testing
import Foundation
@testable import vreader

@Suite("PersistenceActor — Bookmarks")
struct PersistenceBookmarkTests {

    private func makeLocator(key: String, offset: Int = 0) -> Locator {
        let fp = DocumentFingerprint(canonicalKey: key)!
        return Locator.validated(
            bookFingerprint: fp,
            charOffsetUTF16: offset,
            charRangeStartUTF16: offset,
            charRangeEndUTF16: offset + 10
        )!
    }

    // MARK: - Add

    @Test func addBookmarkCreatesRecord() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let locator = makeLocator(key: key, offset: 100)

        let record = try await persistence.addBookmark(
            locator: locator, title: "Chapter 1", toBookWithKey: key
        )

        #expect(record.title == "Chapter 1")
    }

    @Test func addBookmarkWithNilTitle() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let locator = makeLocator(key: key, offset: 200)

        let record = try await persistence.addBookmark(
            locator: locator, title: nil, toBookWithKey: key
        )

        #expect(record.title == nil)
    }

    @Test func addBookmarkRejectsMismatchedKey() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let wrongLocator = makeLocator(key: "wrong:key:123", offset: 0)

        await #expect(throws: (any Error).self) {
            try await persistence.addBookmark(
                locator: wrongLocator, title: nil, toBookWithKey: key
            )
        }
    }

    // MARK: - Deduplication

    @Test func addDuplicateBookmarkReturnsSameId() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let locator = makeLocator(key: key, offset: 300)

        let first = try await persistence.addBookmark(
            locator: locator, title: "A", toBookWithKey: key
        )
        let second = try await persistence.addBookmark(
            locator: locator, title: "B", toBookWithKey: key
        )

        #expect(first.bookmarkId == second.bookmarkId)
    }

    // MARK: - Fetch

    @Test func fetchBookmarksReturnsAll() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)

        _ = try await persistence.addBookmark(
            locator: makeLocator(key: key, offset: 10), title: "A", toBookWithKey: key
        )
        _ = try await persistence.addBookmark(
            locator: makeLocator(key: key, offset: 20), title: "B", toBookWithKey: key
        )

        let all = try await persistence.fetchBookmarks(forBookWithKey: key)
        #expect(all.count == 2)
    }

    @Test func fetchBookmarksForMissingBookReturnsEmpty() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let all = try await persistence.fetchBookmarks(forBookWithKey: "nonexistent:key:0")
        #expect(all.isEmpty)
    }

    // MARK: - Delete

    @Test func removeBookmarkDeletesRecord() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let record = try await persistence.addBookmark(
            locator: makeLocator(key: key, offset: 50), title: "Del", toBookWithKey: key
        )

        try await persistence.removeBookmark(bookmarkId: record.bookmarkId)

        let remaining = try await persistence.fetchBookmarks(forBookWithKey: key)
        #expect(remaining.isEmpty)
    }

    @Test func removeNonexistentBookmarkIsIdempotent() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        try await persistence.removeBookmark(bookmarkId: UUID())
    }

    // MARK: - isBookmarked

    @Test func isBookmarkedReturnsTrueForExisting() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let locator = makeLocator(key: key, offset: 400)

        _ = try await persistence.addBookmark(
            locator: locator, title: nil, toBookWithKey: key
        )

        let result = try await persistence.isBookmarked(locator: locator, forBookWithKey: key)
        #expect(result == true)
    }

    @Test func isBookmarkedReturnsFalseForMissing() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let locator = makeLocator(key: key, offset: 999)

        let result = try await persistence.isBookmarked(locator: locator, forBookWithKey: key)
        #expect(result == false)
    }

    // MARK: - Update Title

    @Test func updateBookmarkTitle() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let key = try await CollectionTestHelper.insertBook(persistence: persistence)
        let record = try await persistence.addBookmark(
            locator: makeLocator(key: key, offset: 500), title: "Old", toBookWithKey: key
        )

        try await persistence.updateBookmarkTitle(bookmarkId: record.bookmarkId, title: "New")

        let all = try await persistence.fetchBookmarks(forBookWithKey: key)
        #expect(all.first?.title == "New")
    }
}
