import Foundation

@testable import vreader

// MARK: - Mock File System

struct MockFileSystem: FileSystemProtocol {
    var files: [URL: Data] = [:]
    var availableSpace: UInt64 = 1_000_000_000
    var shouldFailCopy = false

    func fileExists(at url: URL) -> Bool {
        files[url] != nil
    }

    func readData(at url: URL) throws -> Data {
        guard let data = files[url] else {
            throw FileSystemError.fileNotFound(url.path)
        }
        return data
    }

    func copyFile(from source: URL, to destination: URL) throws {
        if shouldFailCopy {
            throw FileSystemError.copyFailed("Simulated copy failure")
        }
    }

    func availableDiskSpace() -> UInt64 { availableSpace }
    func removeFile(at url: URL) throws {}
}

// MARK: - Mock EPUB Parser

struct MockEPUBParser: EPUBParserProtocol {
    var metadata: BookMetadata?
    var shouldFail = false
    var isDRMProtected = false

    func parseMetadata(at url: URL) throws -> BookMetadata {
        if isDRMProtected { throw ImportError.drmProtected }
        if shouldFail { throw ImportError.corruptFile("Invalid EPUB structure") }
        guard let metadata else { throw ImportError.corruptFile("No metadata") }
        return metadata
    }
}

// MARK: - Mock PDF Parser

struct MockPDFParser: PDFParserProtocol {
    var metadata: BookMetadata?
    var shouldFail = false

    func parseMetadata(at url: URL) throws -> BookMetadata {
        if shouldFail { throw ImportError.corruptFile("Invalid PDF") }
        guard let metadata else { throw ImportError.corruptFile("No metadata") }
        return metadata
    }
}

// MARK: - Mock Book Repository

final class MockBookRepository: BookRepositoryProtocol {
    var books: [Book] = []

    func findByHash(_ hash: String) -> Book? {
        books.first { $0.fileHash == hash }
    }

    func insert(_ book: Book) { books.append(book) }

    func delete(_ book: Book) {
        books.removeAll { $0.id == book.id }
    }
}
