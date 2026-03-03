import Testing
import Foundation

@testable import vreader

// MARK: - Book Model Tests

@Suite("Book Model")
struct BookTests {

    // MARK: - Creation & Defaults

    @Test("creates book with required fields")
    func createWithRequiredFields() {
        let book = Book(
            title: "The Art of War",
            author: "Sun Tzu",
            fileURL: URL(filePath: "/docs/art-of-war.epub"),
            format: .epub
        )

        #expect(book.title == "The Art of War")
        #expect(book.author == "Sun Tzu")
        #expect(book.format == .epub)
        #expect(book.fileURL.lastPathComponent == "art-of-war.epub")
    }

    @Test("assigns default values on creation")
    func defaultValues() {
        let book = Book(
            title: "Test",
            author: nil,
            fileURL: URL(filePath: "/docs/test.epub"),
            format: .epub
        )

        #expect(book.dateAdded != nil)
        #expect(book.lastOpened == nil)
        #expect(book.progress == 0.0)
        #expect(book.author == nil)
        #expect(book.coverImageData == nil)
        #expect(book.fileHash == nil)
        #expect(book.language == nil)
        #expect(book.pageCount == nil)
    }

    @Test("auto-generates id on creation")
    func autoGeneratesID() {
        let book1 = Book(
            title: "Book 1",
            author: nil,
            fileURL: URL(filePath: "/docs/b1.epub"),
            format: .epub
        )
        let book2 = Book(
            title: "Book 2",
            author: nil,
            fileURL: URL(filePath: "/docs/b2.epub"),
            format: .epub
        )

        #expect(book1.id != book2.id)
    }

    // MARK: - Title Fallback

    @Test("falls back to filename when title is empty")
    func titleFallbackEmptyString() {
        let book = Book(
            title: "",
            author: nil,
            fileURL: URL(filePath: "/docs/my-book.epub"),
            format: .epub
        )

        #expect(book.displayTitle == "my-book")
    }

    @Test("falls back to filename when title is whitespace only")
    func titleFallbackWhitespace() {
        let book = Book(
            title: "   ",
            author: nil,
            fileURL: URL(filePath: "/docs/fallback-title.pdf"),
            format: .pdf
        )

        #expect(book.displayTitle == "fallback-title")
    }

    @Test("uses provided title when non-empty")
    func titleUsesProvidedValue() {
        let book = Book(
            title: "Real Title",
            author: nil,
            fileURL: URL(filePath: "/docs/file.epub"),
            format: .epub
        )

        #expect(book.displayTitle == "Real Title")
    }

    // MARK: - File Hash / Duplicate Detection

    @Test("computes SHA-256 hash from data")
    func hashComputation() {
        let data = Data("Hello, world!".utf8)
        let hash = Book.computeHash(from: data)

        #expect(hash != nil)
        #expect(!hash!.isEmpty)
        // SHA-256 produces a 64-character hex string
        #expect(hash!.count == 64)
    }

    @Test("same content produces same hash")
    func hashDeterministic() {
        let data = Data("identical content".utf8)
        let hash1 = Book.computeHash(from: data)
        let hash2 = Book.computeHash(from: data)

        #expect(hash1 == hash2)
    }

    @Test("different content produces different hash")
    func hashDiffers() {
        let hash1 = Book.computeHash(from: Data("content A".utf8))
        let hash2 = Book.computeHash(from: Data("content B".utf8))

        #expect(hash1 != hash2)
    }

    @Test("empty data produces valid hash")
    func hashEmptyData() {
        let hash = Book.computeHash(from: Data())

        #expect(hash != nil)
        #expect(hash!.count == 64)
    }

    @Test("two books with same hash are considered duplicates")
    func duplicateDetection() {
        let hash = "abc123def456"
        let book1 = Book(
            title: "Book",
            author: nil,
            fileURL: URL(filePath: "/docs/a.epub"),
            format: .epub
        )
        book1.fileHash = hash

        let book2 = Book(
            title: "Book Copy",
            author: nil,
            fileURL: URL(filePath: "/docs/b.epub"),
            format: .epub
        )
        book2.fileHash = hash

        #expect(book1.isDuplicate(of: book2))
    }

    @Test("books without hash are not considered duplicates")
    func noDuplicateWithoutHash() {
        let book1 = Book(
            title: "Book",
            author: nil,
            fileURL: URL(filePath: "/docs/a.epub"),
            format: .epub
        )
        let book2 = Book(
            title: "Book",
            author: nil,
            fileURL: URL(filePath: "/docs/b.epub"),
            format: .epub
        )

        #expect(!book1.isDuplicate(of: book2))
    }

    // MARK: - Unicode / CJK Titles

    @Test(
        "handles Unicode titles correctly",
        arguments: [
            ("三体", "三体"),
            ("도서관", "도서관"),
            ("كتاب", "كتاب"),
            ("Ünïcödé Bøøk", "Ünïcödé Bøøk"),
            ("📚 Emoji Title", "📚 Emoji Title"),
        ]
    )
    func unicodeTitles(title: String, expected: String) {
        let book = Book(
            title: title,
            author: nil,
            fileURL: URL(filePath: "/docs/book.epub"),
            format: .epub
        )

        #expect(book.displayTitle == expected)
    }

    // MARK: - Extremely Long Title

    @Test("handles extremely long title without crash")
    func longTitle() {
        let longTitle = String(repeating: "A", count: 10_000)
        let book = Book(
            title: longTitle,
            author: nil,
            fileURL: URL(filePath: "/docs/book.epub"),
            format: .epub
        )

        #expect(book.title.count == 10_000)
        #expect(!book.displayTitle.isEmpty)
    }

    // MARK: - Format Detection

    @Test(
        "stores correct format",
        arguments: [
            (BookFormat.epub, "epub"),
            (BookFormat.pdf, "pdf"),
        ]
    )
    func formatStored(format: BookFormat, label: String) {
        let book = Book(
            title: "Test",
            author: nil,
            fileURL: URL(filePath: "/docs/test.\(label)"),
            format: format
        )

        #expect(book.format == format)
    }

    // MARK: - Progress Bounds

    @Test("progress clamps to 0.0-1.0 range")
    func progressClamping() {
        let book = Book(
            title: "Test",
            author: nil,
            fileURL: URL(filePath: "/docs/t.epub"),
            format: .epub
        )

        book.progress = 1.5
        #expect(book.clampedProgress <= 1.0)

        book.progress = -0.5
        #expect(book.clampedProgress >= 0.0)
    }

    @Test("progress percentage computed correctly")
    func progressPercentage() {
        let book = Book(
            title: "Test",
            author: nil,
            fileURL: URL(filePath: "/docs/t.epub"),
            format: .epub
        )
        book.progress = 0.753

        #expect(book.progressPercentage == 75)
    }
}
