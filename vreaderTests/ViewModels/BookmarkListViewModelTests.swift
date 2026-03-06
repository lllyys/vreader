// Purpose: Tests for BookmarkListViewModel — load, add, remove, toggle, edge cases.
//
// @coordinates-with: BookmarkListViewModel.swift, MockBookmarkStore.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Loading

@Suite("BookmarkListViewModel - Loading")
@MainActor
struct BookmarkListViewModelLoadingTests {

    @Test("loads bookmarks for a book")
    func loadBookmarksPopulatesList() async {
        let store = MockBookmarkStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let record = makeBookmarkRecord(title: "Chapter 1")
        await store.seed(record, forBookWithKey: bookKey)

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.loadBookmarks()

        #expect(vm.bookmarks.count == 1)
        #expect(vm.bookmarks.first?.title == "Chapter 1")
    }

    @Test("empty list shows empty state")
    func emptyBookmarkList() async {
        let store = MockBookmarkStore()
        let vm = BookmarkListViewModel(
            bookFingerprintKey: wi9EPUBFingerprint.canonicalKey,
            store: store
        )
        await vm.loadBookmarks()

        #expect(vm.bookmarks.isEmpty)
        #expect(vm.isEmpty)
    }

    @Test("load error sets error message")
    func loadErrorSetsMessage() async {
        let store = MockBookmarkStore()
        await store.setFetchError(WI9TestError.mockFailure)

        let vm = BookmarkListViewModel(
            bookFingerprintKey: wi9EPUBFingerprint.canonicalKey,
            store: store
        )
        await vm.loadBookmarks()

        #expect(vm.bookmarks.isEmpty)
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - Add / Remove

@Suite("BookmarkListViewModel - Add/Remove")
@MainActor
struct BookmarkListViewModelMutationTests {

    @Test("add bookmark appends to list")
    func addBookmark() async {
        let store = MockBookmarkStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let locator = makeEPUBLocator()

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addBookmark(locator: locator, title: "New Bookmark")

        #expect(vm.bookmarks.count == 1)
        #expect(vm.bookmarks.first?.title == "New Bookmark")
        let count = await store.addCallCount
        #expect(count == 1)
    }

    @Test("remove bookmark removes from list")
    func removeBookmark() async {
        let store = MockBookmarkStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let record = makeBookmarkRecord(title: "To Delete")
        await store.seed(record, forBookWithKey: bookKey)

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.loadBookmarks()
        #expect(vm.bookmarks.count == 1)

        await vm.removeBookmark(bookmarkId: record.bookmarkId)

        #expect(vm.bookmarks.isEmpty)
    }

    @Test("remove nonexistent bookmark is no-op")
    func removeNonexistentBookmark() async {
        let store = MockBookmarkStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        await store.seed(makeBookmarkRecord(), forBookWithKey: bookKey)

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.loadBookmarks()

        await vm.removeBookmark(bookmarkId: UUID())

        #expect(vm.bookmarks.count == 1)
    }
}

// MARK: - Toggle

@Suite("BookmarkListViewModel - Toggle")
@MainActor
struct BookmarkListViewModelToggleTests {

    @Test("toggle adds bookmark when not bookmarked")
    func toggleAddsBookmark() async {
        let store = MockBookmarkStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let locator = makeEPUBLocator()

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.toggleBookmark(locator: locator, title: "Toggled")

        #expect(vm.bookmarks.count == 1)
    }

    @Test("toggle removes bookmark when already bookmarked")
    func toggleRemovesBookmark() async {
        let store = MockBookmarkStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let locator = makeEPUBLocator()

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addBookmark(locator: locator, title: "To Toggle")
        #expect(vm.bookmarks.count == 1)

        await vm.toggleBookmark(locator: locator, title: nil)

        #expect(vm.bookmarks.isEmpty)
    }

    @Test("isBookmarked returns false for empty list")
    func isBookmarkedEmptyList() async {
        let store = MockBookmarkStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let locator = makeEPUBLocator()

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        let result = await vm.isBookmarked(at: locator)

        #expect(result == false)
    }
}

// MARK: - Edge Cases

@Suite("BookmarkListViewModel - Edge Cases")
@MainActor
struct BookmarkListViewModelEdgeCaseTests {

    @Test("add bookmark with nil title")
    func addBookmarkNilTitle() async {
        let store = MockBookmarkStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let locator = makeEPUBLocator()

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addBookmark(locator: locator, title: nil)

        #expect(vm.bookmarks.count == 1)
        #expect(vm.bookmarks.first?.title == nil)
    }

    @Test("add bookmark with empty string title")
    func addBookmarkEmptyTitle() async {
        let store = MockBookmarkStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let locator = makeEPUBLocator()

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addBookmark(locator: locator, title: "")

        #expect(vm.bookmarks.count == 1)
    }

    @Test("add error surfaces error message")
    func addBookmarkError() async {
        let store = MockBookmarkStore()
        await store.setAddError(WI9TestError.mockFailure)
        let bookKey = wi9EPUBFingerprint.canonicalKey

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addBookmark(locator: makeEPUBLocator(), title: "Fails")

        #expect(vm.bookmarks.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test("PDF bookmark with page locator")
    func pdfBookmark() async {
        let store = MockBookmarkStore()
        let bookKey = wi9PDFFingerprint.canonicalKey
        let locator = makePDFLocator(page: 5)

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addBookmark(locator: locator, title: "Page 6")

        #expect(vm.bookmarks.count == 1)
        #expect(vm.bookmarks.first?.locator.page == 5)
    }

    @Test("TXT bookmark with UTF-16 offset locator")
    func txtBookmark() async {
        let store = MockBookmarkStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        let locator = makeTXTLocator(offset: 500)

        let vm = BookmarkListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addBookmark(locator: locator, title: "Position 500")

        #expect(vm.bookmarks.count == 1)
        #expect(vm.bookmarks.first?.locator.charOffsetUTF16 == 500)
    }
}
