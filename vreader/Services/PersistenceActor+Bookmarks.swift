// Purpose: Extension adding BookmarkPersisting conformance to PersistenceActor.
// Provides bookmark CRUD for the reader views.
//
// @coordinates-with: PersistenceActor.swift, BookmarkPersisting.swift,
//   Bookmark.swift, BookmarkRecord.swift

import Foundation
import SwiftData

extension PersistenceActor: BookmarkPersisting {

    func addBookmark(locator: Locator, title: String?, toBookWithKey key: String) async throws -> BookmarkRecord {
        guard locator.bookFingerprint.canonicalKey == key else {
            throw PersistenceError.recordNotFound("Locator fingerprint does not match book key")
        }

        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            throw ImportError.bookNotFound(key)
        }

        // Dedupe: return existing bookmark at the same location
        let profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
        if let existing = book.bookmarks.first(where: { $0.profileKey == profileKey }) {
            return bookmarkToRecord(existing)
        }

        let bookmark = Bookmark(locator: locator, title: title)
        bookmark.book = book
        book.bookmarks.append(bookmark)
        context.insert(bookmark)
        try context.save()

        return bookmarkToRecord(bookmark)
    }

    func removeBookmark(bookmarkId: UUID) async throws {
        let context = ModelContext(modelContainer)
        let id = bookmarkId
        let predicate = #Predicate<Bookmark> { $0.bookmarkId == id }
        var descriptor = FetchDescriptor<Bookmark>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let bookmark = try context.fetch(descriptor).first else {
            return // Idempotent: already deleted
        }

        context.delete(bookmark)
        try context.save()
    }

    func fetchBookmarks(forBookWithKey key: String) async throws -> [BookmarkRecord] {
        let context = ModelContext(modelContainer)
        let predicate = #Predicate<Book> { $0.fingerprintKey == key }
        var descriptor = FetchDescriptor<Book>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let book = try context.fetch(descriptor).first else {
            return []
        }

        return book.bookmarks
            .sorted { $0.createdAt > $1.createdAt }
            .map { bookmarkToRecord($0) }
    }

    func isBookmarked(locator: Locator, forBookWithKey key: String) async throws -> Bool {
        let context = ModelContext(modelContainer)
        let bookPredicate = #Predicate<Book> { $0.fingerprintKey == key }
        var bookDesc = FetchDescriptor<Book>(predicate: bookPredicate)
        bookDesc.fetchLimit = 1

        guard let book = try context.fetch(bookDesc).first else {
            return false
        }

        let profileKey = "\(locator.bookFingerprint.canonicalKey):\(locator.canonicalHash)"
        return book.bookmarks.contains { $0.profileKey == profileKey }
    }

    // MARK: - Private

    private func bookmarkToRecord(_ bookmark: Bookmark) -> BookmarkRecord {
        BookmarkRecord(
            bookmarkId: bookmark.bookmarkId,
            locator: bookmark.locator,
            profileKey: bookmark.profileKey,
            title: bookmark.title,
            createdAt: bookmark.createdAt,
            updatedAt: bookmark.updatedAt
        )
    }
}
