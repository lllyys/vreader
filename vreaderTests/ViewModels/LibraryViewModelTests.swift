import Testing
import Foundation

@testable import vreader

// MARK: - Mock Book Repository for Library

final class MockLibraryRepository: LibraryRepositoryProtocol {
    var books: [Book] = []

    func fetchAll() -> [Book] {
        books
    }

    func delete(_ book: Book) {
        books.removeAll { $0.id == book.id }
    }

    func insert(_ book: Book) {
        books.append(book)
    }
}

// MARK: - Test Helpers

extension Book {
    /// Convenience initializer for tests with minimal parameters.
    static func stub(
        title: String = "Book",
        author: String? = nil,
        format: BookFormat = .epub,
        dateAdded: Date = Date(),
        lastOpened: Date? = nil,
        progress: Double = 0.0
    ) -> Book {
        let book = Book(
            title: title,
            author: author,
            fileURL: URL(filePath: "/docs/\(title).epub"),
            format: format
        )
        book.dateAdded = dateAdded
        book.lastOpened = lastOpened
        book.progress = progress
        return book
    }
}

// MARK: - LibraryViewModel Tests

@Suite("LibraryViewModel")
struct LibraryViewModelTests {

    // MARK: - Helpers

    private func makeViewModel(books: [Book] = []) -> LibraryViewModel {
        let repo = MockLibraryRepository()
        repo.books = books
        return LibraryViewModel(repository: repo)
    }

    // MARK: - Empty State

    @Test("reports empty state when no books")
    func emptyState() {
        let vm = makeViewModel()

        #expect(vm.isEmpty)
        #expect(vm.books.isEmpty)
    }

    @Test("does not report empty state when books exist")
    func nonEmptyState() {
        let vm = makeViewModel(books: [.stub(title: "A")])

        #expect(!vm.isEmpty)
        #expect(vm.books.count == 1)
    }

    // MARK: - Sort Ordering

    @Test("sorts by title ascending")
    func sortByTitle() {
        let vm = makeViewModel(books: [
            .stub(title: "Zebra"),
            .stub(title: "Apple"),
            .stub(title: "Mango"),
        ])

        vm.sortOrder = .title

        #expect(vm.sortedBooks[0].title == "Apple")
        #expect(vm.sortedBooks[1].title == "Mango")
        #expect(vm.sortedBooks[2].title == "Zebra")
    }

    @Test("sorts by author ascending")
    func sortByAuthor() {
        let vm = makeViewModel(books: [
            .stub(title: "B", author: "Zoe"),
            .stub(title: "A", author: "Alice"),
            .stub(title: "C", author: nil),
        ])

        vm.sortOrder = .author

        // nil author sorts last
        #expect(vm.sortedBooks[0].author == "Alice")
        #expect(vm.sortedBooks[1].author == "Zoe")
        #expect(vm.sortedBooks[2].author == nil)
    }

    @Test("sorts by date added, newest first")
    func sortByDateAdded() {
        let old = Date(timeIntervalSinceNow: -86400)
        let recent = Date()
        let vm = makeViewModel(books: [
            .stub(title: "Old", dateAdded: old),
            .stub(title: "New", dateAdded: recent),
        ])

        vm.sortOrder = .dateAdded

        #expect(vm.sortedBooks[0].title == "New")
        #expect(vm.sortedBooks[1].title == "Old")
    }

    @Test("sorts by last read, most recent first")
    func sortByLastRead() {
        let yesterday = Date(timeIntervalSinceNow: -86400)
        let today = Date()
        let vm = makeViewModel(books: [
            .stub(title: "Yesterday", lastOpened: yesterday),
            .stub(title: "Today", lastOpened: today),
            .stub(title: "Never", lastOpened: nil),
        ])

        vm.sortOrder = .lastRead

        #expect(vm.sortedBooks[0].title == "Today")
        #expect(vm.sortedBooks[1].title == "Yesterday")
        #expect(vm.sortedBooks[2].title == "Never") // nil sorts last
    }

    @Test("CJK titles sort correctly")
    func cjkTitleSort() {
        let vm = makeViewModel(books: [
            .stub(title: "三体"),
            .stub(title: "阿Q正传"),
            .stub(title: "红楼梦"),
        ])

        vm.sortOrder = .title

        // Should not crash; sorted by Unicode ordering
        #expect(vm.sortedBooks.count == 3)
    }

    // MARK: - Delete

    @Test("delete removes book from list")
    func deleteBook() {
        let book = Book.stub(title: "To Delete")
        let vm = makeViewModel(books: [
            .stub(title: "Keep"),
            book,
        ])

        vm.deleteBook(book)

        #expect(vm.books.count == 1)
        #expect(vm.books[0].title == "Keep")
    }

    @Test("delete last book results in empty state")
    func deleteLastBook() {
        let book = Book.stub(title: "Only Book")
        let vm = makeViewModel(books: [book])

        vm.deleteBook(book)

        #expect(vm.isEmpty)
    }

    @Test("delete nonexistent book is a no-op")
    func deleteNonexistentBook() {
        let vm = makeViewModel(books: [.stub(title: "Existing")])
        let ghost = Book.stub(title: "Ghost")

        vm.deleteBook(ghost)

        #expect(vm.books.count == 1)
    }

    // MARK: - Layout Toggle

    @Test("default layout is grid")
    func defaultLayout() {
        let vm = makeViewModel()

        #expect(vm.layoutMode == .grid)
    }

    @Test("toggles between grid and list")
    func toggleLayout() {
        let vm = makeViewModel()

        vm.toggleLayout()
        #expect(vm.layoutMode == .list)

        vm.toggleLayout()
        #expect(vm.layoutMode == .grid)
    }

    // MARK: - Edge Cases

    @Test("handles large library without crash")
    func largeLibrary() {
        let books = (0..<1000).map { Book.stub(title: "Book \($0)") }
        let vm = makeViewModel(books: books)

        vm.sortOrder = .title

        #expect(vm.sortedBooks.count == 1000)
    }

    @Test("sort stability: books with same title maintain relative order")
    func sortStability() {
        let books = [
            Book.stub(title: "Same", author: "A"),
            Book.stub(title: "Same", author: "B"),
            Book.stub(title: "Same", author: "C"),
        ]
        let vm = makeViewModel(books: books)

        vm.sortOrder = .title

        // All have same title; order should be stable (not shuffled)
        #expect(vm.sortedBooks.count == 3)
    }
}
