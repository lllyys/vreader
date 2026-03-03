import Testing
import Foundation

@testable import vreader

// MARK: - Mock Bookmark Repository

final class MockBookmarkRepository: BookmarkRepositoryProtocol {
    var bookmarks: [Bookmark] = []

    func fetchAll(for bookID: UUID) -> [Bookmark] {
        bookmarks.filter { $0.bookID == bookID }
    }

    func insert(_ bookmark: Bookmark) {
        bookmarks.append(bookmark)
    }

    func delete(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
    }

    func find(bookID: UUID, locator: BookLocator) -> Bookmark? {
        bookmarks.first {
            $0.bookID == bookID
            && $0.locator.chapter == locator.chapter
            && abs($0.locator.progression - locator.progression) < 0.001
        }
    }
}

// MARK: - Mock Navigation Delegate

final class MockNavigationDelegate: NavigationDelegateProtocol {
    var navigatedTo: BookLocator?

    func navigateTo(_ locator: BookLocator) {
        navigatedTo = locator
    }
}

// MARK: - BookmarksViewModel Tests

@Suite("BookmarksViewModel")
struct BookmarksViewModelTests {

    // MARK: - Helpers

    private let testBookID = UUID()

    private func makeViewModel(
        bookID: UUID? = nil,
        bookmarks: [Bookmark] = [],
        navigationDelegate: MockNavigationDelegate = MockNavigationDelegate()
    ) -> BookmarksViewModel {
        let repo = MockBookmarkRepository()
        repo.bookmarks = bookmarks
        let id = bookID ?? testBookID
        return BookmarksViewModel(
            bookID: id,
            repository: repo,
            navigationDelegate: navigationDelegate
        )
    }

    private func makeBookmark(
        bookID: UUID? = nil,
        chapter: Int = 1,
        progression: Double = 0.5,
        label: String? = nil
    ) -> Bookmark {
        Bookmark(
            bookID: bookID ?? testBookID,
            locator: BookLocator(chapter: chapter, progression: progression),
            label: label
        )
    }

    // MARK: - Add Bookmark

    @Test("adds bookmark at current position")
    func addBookmark() {
        let vm = makeViewModel()
        let locator = BookLocator(chapter: 2, progression: 0.4)

        vm.addBookmark(at: locator, label: "My bookmark")

        #expect(vm.bookmarks.count == 1)
        #expect(vm.bookmarks[0].locator.chapter == 2)
        #expect(vm.bookmarks[0].label == "My bookmark")
    }

    @Test("adds bookmark without label")
    func addBookmarkNoLabel() {
        let vm = makeViewModel()

        vm.addBookmark(
            at: BookLocator(chapter: 1, progression: 0.0),
            label: nil
        )

        #expect(vm.bookmarks.count == 1)
        #expect(vm.bookmarks[0].label == nil)
    }

    // MARK: - Remove Bookmark

    @Test("removes bookmark by reference")
    func removeBookmark() {
        let bm = makeBookmark(chapter: 1, progression: 0.3)
        let vm = makeViewModel(bookmarks: [bm])

        vm.removeBookmark(bm)

        #expect(vm.bookmarks.isEmpty)
    }

    @Test("removing nonexistent bookmark is a no-op")
    func removeNonexistent() {
        let existing = makeBookmark(chapter: 1, progression: 0.5)
        let vm = makeViewModel(bookmarks: [existing])
        let ghost = makeBookmark(chapter: 99, progression: 0.0)

        vm.removeBookmark(ghost)

        #expect(vm.bookmarks.count == 1)
    }

    // MARK: - Toggle Bookmark

    @Test("toggle adds bookmark if not present")
    func toggleAddsBookmark() {
        let vm = makeViewModel()
        let locator = BookLocator(chapter: 3, progression: 0.7)

        vm.toggleBookmark(at: locator)

        #expect(vm.bookmarks.count == 1)
    }

    @Test("toggle removes bookmark if already present")
    func toggleRemovesBookmark() {
        let locator = BookLocator(chapter: 3, progression: 0.7)
        let bm = Bookmark(
            bookID: testBookID,
            locator: locator,
            label: nil
        )
        let vm = makeViewModel(bookmarks: [bm])

        vm.toggleBookmark(at: locator)

        #expect(vm.bookmarks.isEmpty)
    }

    @Test("isBookmarked returns true for bookmarked position")
    func isBookmarkedTrue() {
        let locator = BookLocator(chapter: 2, progression: 0.5)
        let bm = Bookmark(
            bookID: testBookID,
            locator: locator,
            label: nil
        )
        let vm = makeViewModel(bookmarks: [bm])

        #expect(vm.isBookmarked(at: locator))
    }

    @Test("isBookmarked returns false for non-bookmarked position")
    func isBookmarkedFalse() {
        let vm = makeViewModel()
        let locator = BookLocator(chapter: 1, progression: 0.5)

        #expect(!vm.isBookmarked(at: locator))
    }

    // MARK: - Sort Order

    @Test("bookmarks sorted by chapter then progression")
    func sortOrder() {
        let bm1 = makeBookmark(chapter: 3, progression: 0.2)
        let bm2 = makeBookmark(chapter: 1, progression: 0.8)
        let bm3 = makeBookmark(chapter: 1, progression: 0.2)
        let vm = makeViewModel(bookmarks: [bm1, bm2, bm3])

        let sorted = vm.sortedBookmarks

        #expect(sorted[0].locator.chapter == 1)
        #expect(sorted[0].locator.progression == 0.2)
        #expect(sorted[1].locator.chapter == 1)
        #expect(sorted[1].locator.progression == 0.8)
        #expect(sorted[2].locator.chapter == 3)
    }

    // MARK: - Navigate

    @Test("navigate triggers navigation delegate")
    func navigateToBookmark() {
        let navDelegate = MockNavigationDelegate()
        let bm = makeBookmark(chapter: 5, progression: 0.3)
        let vm = makeViewModel(
            bookmarks: [bm],
            navigationDelegate: navDelegate
        )

        vm.navigateTo(bm)

        #expect(navDelegate.navigatedTo?.chapter == 5)
        #expect(abs(navDelegate.navigatedTo!.progression - 0.3) < 0.01)
    }

    // MARK: - Duplicate Prevention

    @Test("prevents adding duplicate bookmark at same position")
    func duplicatePrevention() {
        let locator = BookLocator(chapter: 2, progression: 0.5)
        let existing = Bookmark(
            bookID: testBookID,
            locator: locator,
            label: nil
        )
        let vm = makeViewModel(bookmarks: [existing])

        vm.addBookmark(at: locator, label: "Duplicate attempt")

        #expect(vm.bookmarks.count == 1) // Still just 1
    }

    @Test("allows bookmarks at different positions in same chapter")
    func differentPositions() {
        let bm1 = makeBookmark(chapter: 1, progression: 0.2)
        let vm = makeViewModel(bookmarks: [bm1])

        vm.addBookmark(
            at: BookLocator(chapter: 1, progression: 0.8),
            label: nil
        )

        #expect(vm.bookmarks.count == 2)
    }

    @Test("allows bookmarks at same progression in different chapters")
    func differentChapters() {
        let bm1 = makeBookmark(chapter: 1, progression: 0.5)
        let vm = makeViewModel(bookmarks: [bm1])

        vm.addBookmark(
            at: BookLocator(chapter: 2, progression: 0.5),
            label: nil
        )

        #expect(vm.bookmarks.count == 2)
    }

    // MARK: - Edge Cases

    @Test("handles empty bookmark list")
    func emptyList() {
        let vm = makeViewModel()

        #expect(vm.bookmarks.isEmpty)
        #expect(vm.sortedBookmarks.isEmpty)
    }

    @Test("handles many bookmarks")
    func manyBookmarks() {
        let bookmarks = (0..<200).map { i in
            makeBookmark(
                chapter: i / 20,
                progression: Double(i % 20) / 20.0
            )
        }
        let vm = makeViewModel(bookmarks: bookmarks)

        #expect(vm.bookmarks.count == 200)
        #expect(vm.sortedBookmarks.count == 200)
    }

    @Test("bookmark with CJK label appears in list")
    func cjkLabelInList() {
        let bm = makeBookmark(
            chapter: 1,
            progression: 0.5,
            label: "第三章の始まり"
        )
        let vm = makeViewModel(bookmarks: [bm])

        #expect(vm.bookmarks[0].label == "第三章の始まり")
    }

    @Test("bookmarks only shows current book's bookmarks")
    func filtersByBook() {
        let otherBookID = UUID()
        let bm1 = makeBookmark(bookID: testBookID, chapter: 1, progression: 0.5)
        let bm2 = makeBookmark(bookID: otherBookID, chapter: 2, progression: 0.3)

        let repo = MockBookmarkRepository()
        repo.bookmarks = [bm1, bm2]

        let vm = BookmarksViewModel(
            bookID: testBookID,
            repository: repo,
            navigationDelegate: MockNavigationDelegate()
        )

        #expect(vm.bookmarks.count == 1)
        #expect(vm.bookmarks[0].bookID == testBookID)
    }
}
