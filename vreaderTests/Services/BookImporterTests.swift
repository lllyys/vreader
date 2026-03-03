import Testing
import Foundation

@testable import vreader

// MARK: - BookImporter Tests

@Suite("BookImporter")
struct BookImporterTests {

    // MARK: - Helpers

    private func makeImporter(
        fileSystem: MockFileSystem = MockFileSystem(),
        epubParser: MockEPUBParser = MockEPUBParser(),
        pdfParser: MockPDFParser = MockPDFParser(),
        repository: MockBookRepository = MockBookRepository()
    ) -> BookImporter {
        BookImporter(
            fileSystem: fileSystem,
            epubParser: epubParser,
            pdfParser: pdfParser,
            repository: repository
        )
    }

    private func validEPUBMetadata() -> BookMetadata {
        BookMetadata(
            title: "Sample Book", author: "Author Name",
            language: "en", coverImageData: nil, pageCount: nil
        )
    }

    private func validPDFMetadata() -> BookMetadata {
        BookMetadata(
            title: "PDF Document", author: "PDF Author",
            language: nil, coverImageData: nil, pageCount: 42
        )
    }

    // MARK: - Valid EPUB Import

    @Test("imports valid EPUB and creates book")
    func importValidEPUB() async throws {
        let fileURL = URL(filePath: "/tmp/valid.epub")
        var fs = MockFileSystem()
        fs.files[fileURL] = Data("fake epub".utf8)

        var parser = MockEPUBParser()
        parser.metadata = validEPUBMetadata()

        let repo = MockBookRepository()
        let importer = makeImporter(
            fileSystem: fs, epubParser: parser, repository: repo
        )

        let book = try await importer.importBook(from: fileURL)

        #expect(book.title == "Sample Book")
        #expect(book.author == "Author Name")
        #expect(book.format == .epub)
        #expect(book.fileHash != nil)
        #expect(repo.books.count == 1)
    }

    @Test("EPUB import extracts language")
    func epubLanguage() async throws {
        let url = URL(filePath: "/tmp/book.epub")
        var fs = MockFileSystem()
        fs.files[url] = Data("epub".utf8)

        var parser = MockEPUBParser()
        parser.metadata = BookMetadata(
            title: "Book", author: nil, language: "ja",
            coverImageData: nil, pageCount: nil
        )

        let importer = makeImporter(fileSystem: fs, epubParser: parser)
        let book = try await importer.importBook(from: url)

        #expect(book.language == "ja")
    }

    // MARK: - Valid PDF Import

    @Test("imports valid PDF and creates book")
    func importValidPDF() async throws {
        let url = URL(filePath: "/tmp/valid.pdf")
        var fs = MockFileSystem()
        fs.files[url] = Data("fake pdf".utf8)

        var parser = MockPDFParser()
        parser.metadata = validPDFMetadata()

        let repo = MockBookRepository()
        let importer = makeImporter(
            fileSystem: fs, pdfParser: parser, repository: repo
        )

        let book = try await importer.importBook(from: url)

        #expect(book.title == "PDF Document")
        #expect(book.format == .pdf)
        #expect(book.pageCount == 42)
        #expect(repo.books.count == 1)
    }

    // MARK: - Corrupt Files

    @Test("corrupt EPUB returns descriptive error")
    func corruptEPUB() async {
        let url = URL(filePath: "/tmp/corrupt.epub")
        var fs = MockFileSystem()
        fs.files[url] = Data("not a zip".utf8)

        var parser = MockEPUBParser()
        parser.shouldFail = true

        let importer = makeImporter(fileSystem: fs, epubParser: parser)
        await #expect(throws: ImportError.self) {
            try await importer.importBook(from: url)
        }
    }

    @Test("corrupt PDF returns descriptive error")
    func corruptPDF() async {
        let url = URL(filePath: "/tmp/corrupt.pdf")
        var fs = MockFileSystem()
        fs.files[url] = Data("truncated".utf8)

        var parser = MockPDFParser()
        parser.shouldFail = true

        let importer = makeImporter(fileSystem: fs, pdfParser: parser)
        await #expect(throws: ImportError.self) {
            try await importer.importBook(from: url)
        }
    }

    // MARK: - File Not Found

    @Test("missing file returns error")
    func fileNotFound() async {
        let url = URL(filePath: "/tmp/nonexistent.epub")
        let importer = makeImporter()

        await #expect(throws: ImportError.self) {
            try await importer.importBook(from: url)
        }
    }

    // MARK: - Duplicate Detection

    @Test("duplicate file returns existing book without re-importing")
    func duplicate() async throws {
        let url = URL(filePath: "/tmp/book.epub")
        let data = Data("book content".utf8)
        var fs = MockFileSystem()
        fs.files[url] = data

        var parser = MockEPUBParser()
        parser.metadata = validEPUBMetadata()

        let repo = MockBookRepository()
        let existing = Book(
            title: "Already Here", author: nil,
            fileURL: URL(filePath: "/docs/book.epub"), format: .epub
        )
        existing.fileHash = Book.computeHash(from: data)
        repo.books.append(existing)

        let importer = makeImporter(
            fileSystem: fs, epubParser: parser, repository: repo
        )
        let result = try await importer.importBook(from: url)

        #expect(result.id == existing.id)
        #expect(repo.books.count == 1)
    }

    // MARK: - DRM Detection

    @Test("DRM-protected EPUB returns user-friendly error")
    func drmDetection() async {
        let url = URL(filePath: "/tmp/drm.epub")
        var fs = MockFileSystem()
        fs.files[url] = Data("drm".utf8)

        var parser = MockEPUBParser()
        parser.isDRMProtected = true

        let importer = makeImporter(fileSystem: fs, epubParser: parser)
        await #expect(throws: ImportError.drmProtected) {
            try await importer.importBook(from: url)
        }
    }

    // MARK: - Low Disk Space

    @Test("import fails gracefully with low disk space")
    func lowDiskSpace() async {
        let url = URL(filePath: "/tmp/big.epub")
        var fs = MockFileSystem()
        fs.files[url] = Data(repeating: 0, count: 100_000)
        fs.availableSpace = 1000

        var parser = MockEPUBParser()
        parser.metadata = validEPUBMetadata()

        let importer = makeImporter(fileSystem: fs, epubParser: parser)
        await #expect(throws: ImportError.self) {
            try await importer.importBook(from: url)
        }
    }

    // MARK: - Copy Failure

    @Test("copy failure cleans up and returns error")
    func copyFailure() async {
        let url = URL(filePath: "/tmp/book.epub")
        var fs = MockFileSystem()
        fs.files[url] = Data("content".utf8)
        fs.shouldFailCopy = true

        var parser = MockEPUBParser()
        parser.metadata = validEPUBMetadata()

        let repo = MockBookRepository()
        let importer = makeImporter(
            fileSystem: fs, epubParser: parser, repository: repo
        )
        await #expect(throws: ImportError.self) {
            try await importer.importBook(from: url)
        }
        #expect(repo.books.isEmpty)
    }

    // MARK: - Format Detection

    @Test("unsupported file extension returns error")
    func unsupportedFormat() async {
        let url = URL(filePath: "/tmp/book.mobi")
        var fs = MockFileSystem()
        fs.files[url] = Data("mobi".utf8)

        let importer = makeImporter(fileSystem: fs)
        await #expect(throws: ImportError.self) {
            try await importer.importBook(from: url)
        }
    }

    @Test(
        "detects format from file extension",
        arguments: [
            ("book.epub", BookFormat.epub),
            ("book.EPUB", BookFormat.epub),
            ("book.pdf", BookFormat.pdf),
            ("book.PDF", BookFormat.pdf),
        ]
    )
    func formatFromExtension(filename: String, expected: BookFormat) {
        let format = BookImporter.detectFormat(
            from: URL(filePath: "/tmp/\(filename)")
        )
        #expect(format == expected)
    }

    @Test("unknown extension returns nil format")
    func unknownExtension() {
        let format = BookImporter.detectFormat(
            from: URL(filePath: "/tmp/book.txt")
        )
        #expect(format == nil)
    }

    // MARK: - Unicode Filenames

    @Test("handles Unicode filenames")
    func unicodeFilename() async throws {
        let url = URL(filePath: "/tmp/三体.epub")
        var fs = MockFileSystem()
        fs.files[url] = Data("content".utf8)

        var parser = MockEPUBParser()
        parser.metadata = validEPUBMetadata()

        let importer = makeImporter(fileSystem: fs, epubParser: parser)
        let book = try await importer.importBook(from: url)
        #expect(book.title == "Sample Book")
    }
}
