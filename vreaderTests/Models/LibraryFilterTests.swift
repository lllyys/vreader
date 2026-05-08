// Bug #155 / GH #451 — regression-guard tests for `LibraryFilter.matches(_:)`.
//
// The bug: `LibraryView.gridView`/`listView` iterated `viewModel.books`
// directly, never consulting `activeFilter`. These tests pin the filter
// helper that the view now consults to derive `displayedBooks`.

import Testing
import Foundation
@testable import vreader

@Suite("LibraryFilter matches (Bug #155)")
struct LibraryFilterTests {

    // Helper to build a LibraryBookItem with a controllable
    // `collectionNames` set. Other fields use safe placeholders.
    private static func makeBook(
        title: String,
        collectionNames: [String] = []
    ) -> LibraryBookItem {
        LibraryBookItem(
            fingerprintKey: "txt:\(title.lowercased()):0000",
            title: title,
            author: nil,
            coverImagePath: nil,
            format: "txt",
            fileByteCount: 0,
            addedAt: Date(timeIntervalSinceReferenceDate: 0),
            lastOpenedAt: nil,
            isFavorite: false,
            totalReadingSeconds: 0,
            lastReadAt: nil,
            averagePagesPerHour: nil,
            averageWordsPerMinute: nil,
            collectionNames: collectionNames
        )
    }

    @Test func allBooksMatchesEverything() {
        let book = Self.makeBook(title: "A", collectionNames: [])
        #expect(LibraryFilter.allBooks.matches(book))

        let bookInCollections = Self.makeBook(title: "B", collectionNames: ["Reading List", "Sci-Fi"])
        #expect(LibraryFilter.allBooks.matches(bookInCollections))
    }

    @Test func collectionFilterMatchesMembers() {
        let book = Self.makeBook(title: "A", collectionNames: ["Reading List"])
        #expect(LibraryFilter.collection("Reading List").matches(book))
    }

    @Test func collectionFilterMatchesOneOfMany() {
        let book = Self.makeBook(title: "A", collectionNames: ["Sci-Fi", "Reading List", "Favorites"])
        #expect(LibraryFilter.collection("Reading List").matches(book))
    }

    @Test func collectionFilterRejectsNonMembers() {
        let book = Self.makeBook(title: "A", collectionNames: ["Other"])
        #expect(!LibraryFilter.collection("Reading List").matches(book))
    }

    @Test func collectionFilterRejectsBooksWithNoCollections() {
        let book = Self.makeBook(title: "A", collectionNames: [])
        #expect(!LibraryFilter.collection("Reading List").matches(book))
    }

    @Test func unknownCollectionMatchesNothing() {
        let book = Self.makeBook(title: "A", collectionNames: ["Reading List"])
        #expect(!LibraryFilter.collection("Nonexistent").matches(book))
    }

    @Test func collectionFilterIsCaseAndUnicodeExact() {
        // Per-row notes from feature #34's `CollectionPersistenceTests` describe
        // case-insensitive duplicate REJECTION at create time, but membership
        // matching at filter time is exact-string. Pin that behavior here.
        let book = Self.makeBook(title: "A", collectionNames: ["Reading List"])
        #expect(!LibraryFilter.collection("reading list").matches(book))
        #expect(!LibraryFilter.collection("READING LIST").matches(book))

        let cjkBook = Self.makeBook(title: "B", collectionNames: ["読書リスト"])
        #expect(LibraryFilter.collection("読書リスト").matches(cjkBook))
        #expect(!LibraryFilter.collection("読書").matches(cjkBook))
    }
}
