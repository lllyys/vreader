// Purpose: Tests for PersistenceActor+Collections — verifies collection CRUD
// and book membership operations using in-memory SwiftData.

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("Collection Persistence")
struct CollectionPersistenceTests {

    // MARK: - Create Collection

    @Test("createCollection saves and retrieves")
    func createCollectionSavesAndRetrieves() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let name = try await persistence.createCollection(name: "Fiction")
        #expect(name == "Fiction")

        let collections = try await persistence.fetchAllCollections()
        #expect(collections.count == 1)
        #expect(collections[0].name == "Fiction")
        #expect(collections[0].bookCount == 0)
    }

    @Test("createCollection trims whitespace")
    func createCollectionTrimsWhitespace() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let name = try await persistence.createCollection(name: "  Fantasy  ")
        #expect(name == "Fantasy")
    }

    @Test("createCollection truncates long names")
    func createCollectionTruncatesLongName() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let longName = String(repeating: "b", count: 150)
        let name = try await persistence.createCollection(name: longName)
        #expect(name.count == 100)
    }

    @Test("createCollection rejects empty name")
    func createCollectionRejectsEmpty() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        await #expect(throws: CollectionError.emptyName) {
            try await persistence.createCollection(name: "")
        }
    }

    @Test("createCollection rejects whitespace-only name")
    func createCollectionRejectsWhitespace() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        await #expect(throws: CollectionError.emptyName) {
            try await persistence.createCollection(name: "   ")
        }
    }

    @Test("createCollection rejects duplicate name case-insensitive")
    func createCollectionRejectsDuplicate() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        _ = try await persistence.createCollection(name: "Fiction")
        await #expect(throws: CollectionError.self) {
            try await persistence.createCollection(name: "fiction")
        }
    }

    @Test("createCollection handles Unicode/CJK names")
    func createCollectionHandlesUnicode() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let name = try await persistence.createCollection(name: "科幻小说")
        #expect(name == "科幻小说")
    }

    // MARK: - Delete Collection

    @Test("deleteCollection removes but keeps books")
    func deleteCollectionKeepsBooks() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )

        _ = try await persistence.createCollection(name: "ToDelete")
        try await persistence.addBookToCollection(
            bookFingerprintKey: bookKey, collectionName: "ToDelete"
        )

        try await persistence.deleteCollection(name: "ToDelete")

        let collections = try await persistence.fetchAllCollections()
        #expect(collections.isEmpty)

        let book = try await persistence.findBook(byFingerprintKey: bookKey)
        #expect(book != nil)
    }

    @Test("deleteCollection throws for nonexistent")
    func deleteCollectionThrowsNotFound() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        await #expect(throws: CollectionError.collectionNotFound("Ghost")) {
            try await persistence.deleteCollection(name: "Ghost")
        }
    }

    // MARK: - Rename Collection

    @Test("renameCollection updates name")
    func renameCollectionUpdatesName() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        _ = try await persistence.createCollection(name: "Old Name")

        try await persistence.renameCollection(
            oldName: "Old Name", newName: "New Name"
        )

        let collections = try await persistence.fetchAllCollections()
        #expect(collections.count == 1)
        #expect(collections[0].name == "New Name")
    }

    @Test("renameCollection rejects empty new name")
    func renameCollectionRejectsEmpty() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        _ = try await persistence.createCollection(name: "Valid")
        await #expect(throws: CollectionError.emptyName) {
            try await persistence.renameCollection(
                oldName: "Valid", newName: ""
            )
        }
    }

    @Test("renameCollection rejects duplicate new name")
    func renameCollectionRejectsDuplicate() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        _ = try await persistence.createCollection(name: "First")
        _ = try await persistence.createCollection(name: "Second")
        await #expect(throws: CollectionError.self) {
            try await persistence.renameCollection(
                oldName: "Second", newName: "First"
            )
        }
    }

    @Test("renameCollection allows same name with different case")
    func renameCollectionAllowsSameName() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        _ = try await persistence.createCollection(name: "fiction")
        try await persistence.renameCollection(
            oldName: "fiction", newName: "Fiction"
        )
        let collections = try await persistence.fetchAllCollections()
        #expect(collections[0].name == "Fiction")
    }

    // MARK: - Add/Remove Book to Collection

    @Test("addBookToCollection bidirectional link")
    func addBookToCollectionBidirectional() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )
        _ = try await persistence.createCollection(name: "Favorites")

        try await persistence.addBookToCollection(
            bookFingerprintKey: bookKey, collectionName: "Favorites"
        )

        let booksInCollection = try await persistence.fetchBooksInCollection(
            name: "Favorites"
        )
        #expect(booksInCollection.contains(bookKey))
    }

    @Test("removeBookFromCollection preserves book")
    func removeBookFromCollectionPreservesBook() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )
        _ = try await persistence.createCollection(name: "Temp")

        try await persistence.addBookToCollection(
            bookFingerprintKey: bookKey, collectionName: "Temp"
        )
        try await persistence.removeBookFromCollection(
            bookFingerprintKey: bookKey, collectionName: "Temp"
        )

        let books = try await persistence.fetchBooksInCollection(name: "Temp")
        #expect(books.isEmpty)

        let book = try await persistence.findBook(byFingerprintKey: bookKey)
        #expect(book != nil)
    }

    @Test("bookInMultipleCollections allowed")
    func bookInMultipleCollections() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )
        _ = try await persistence.createCollection(name: "Collection A")
        _ = try await persistence.createCollection(name: "Collection B")

        try await persistence.addBookToCollection(
            bookFingerprintKey: bookKey, collectionName: "Collection A"
        )
        try await persistence.addBookToCollection(
            bookFingerprintKey: bookKey, collectionName: "Collection B"
        )

        let booksA = try await persistence.fetchBooksInCollection(
            name: "Collection A"
        )
        let booksB = try await persistence.fetchBooksInCollection(
            name: "Collection B"
        )
        #expect(booksA.contains(bookKey))
        #expect(booksB.contains(bookKey))
    }

    @Test("addBookToCollection is idempotent")
    func addBookToCollectionIdempotent() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )
        _ = try await persistence.createCollection(name: "Idem")

        try await persistence.addBookToCollection(
            bookFingerprintKey: bookKey, collectionName: "Idem"
        )
        try await persistence.addBookToCollection(
            bookFingerprintKey: bookKey, collectionName: "Idem"
        )

        let books = try await persistence.fetchBooksInCollection(name: "Idem")
        #expect(books.count == 1)
    }

    @Test("deleteBook removes from collections")
    func deleteBookRemovesFromCollections() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )
        _ = try await persistence.createCollection(name: "WillLoseBook")

        try await persistence.addBookToCollection(
            bookFingerprintKey: bookKey, collectionName: "WillLoseBook"
        )

        try await persistence.deleteBook(fingerprintKey: bookKey)

        let books = try await persistence.fetchBooksInCollection(
            name: "WillLoseBook"
        )
        #expect(books.isEmpty)
    }

    // MARK: - Fetch All Collections Sorted

    @Test("fetchAllCollections returns sorted by name")
    func fetchAllCollectionsSorted() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        _ = try await persistence.createCollection(name: "Zebra")
        _ = try await persistence.createCollection(name: "Alpha")
        _ = try await persistence.createCollection(name: "Middle")

        let collections = try await persistence.fetchAllCollections()
        #expect(collections.count == 3)
        #expect(collections[0].name == "Alpha")
        #expect(collections[1].name == "Middle")
        #expect(collections[2].name == "Zebra")
    }

    // MARK: - Library Projection (Bug #155)

    /// Bug #155 / GH #451: locks in that `PersistenceActor.fetchAllLibraryBooks`
    /// projects each book's `bookCollections` membership into
    /// `LibraryBookItem.collectionNames`. This is the persistence-side half of
    /// the fix; the view-side filter helper is exercised by
    /// `LibraryFilterTests`. Together they prove the chain
    /// `Book.bookCollections → LibraryBookItem.collectionNames →
    /// LibraryFilter.matches` is wired end-to-end.
    @Test("fetchAllLibraryBooks projects collectionNames")
    func fetchAllLibraryBooksProjectsCollectionNames() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )
        _ = try await persistence.createCollection(name: "Reading List")
        _ = try await persistence.createCollection(name: "Sci-Fi")
        try await persistence.addBookToCollection(
            bookFingerprintKey: bookKey, collectionName: "Reading List"
        )
        try await persistence.addBookToCollection(
            bookFingerprintKey: bookKey, collectionName: "Sci-Fi"
        )

        let items = try await persistence.fetchAllLibraryBooks()
        let item = try #require(items.first { $0.fingerprintKey == bookKey })
        // SwiftData relationship order isn't guaranteed; assert as a Set.
        #expect(Set(item.collectionNames) == Set(["Reading List", "Sci-Fi"]))
    }

    @Test("fetchAllLibraryBooks projects empty collectionNames for unassigned book")
    func fetchAllLibraryBooksEmptyCollectionNames() async throws {
        let persistence = try CollectionTestHelper.makePersistence()
        let bookKey = try await CollectionTestHelper.insertBook(
            persistence: persistence
        )

        let items = try await persistence.fetchAllLibraryBooks()
        let item = try #require(items.first { $0.fingerprintKey == bookKey })
        #expect(item.collectionNames.isEmpty)
    }
}
