// Purpose: Tests for LibraryRefreshService — file existence verification and throttling.

import Testing
import Foundation
@testable import vreader

// MARK: - MockFileExistenceChecker

/// Mock for file existence checks in tests.
struct MockFileExistenceChecker: FileExistenceChecking, Sendable {
    let existingPaths: Set<String>

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }
}

@Suite("LibraryRefreshService")
struct LibraryRefreshServiceTests {

    // MARK: - File Existence Verification

    @Test func verifyFileExistenceReturnsExistingBooks() {
        let checker = MockFileExistenceChecker(existingPaths: ["/books/book1.epub"])
        let service = LibraryRefreshService(fileChecker: checker)

        let books = [
            makeProvenanceItem(key: "k1", filePath: "/books/book1.epub"),
            makeProvenanceItem(key: "k2", filePath: "/books/missing.epub"),
        ]

        let result = service.verifyFileExistence(books: books)

        #expect(result.existing.count == 1)
        #expect(result.existing.first?.fingerprintKey == "k1")
        #expect(result.missing.count == 1)
        #expect(result.missing.first?.fingerprintKey == "k2")
    }

    @Test func verifyFileExistenceAllExist() {
        let checker = MockFileExistenceChecker(existingPaths: ["/a.epub", "/b.pdf"])
        let service = LibraryRefreshService(fileChecker: checker)

        let books = [
            makeProvenanceItem(key: "k1", filePath: "/a.epub"),
            makeProvenanceItem(key: "k2", filePath: "/b.pdf"),
        ]

        let result = service.verifyFileExistence(books: books)

        #expect(result.existing.count == 2)
        #expect(result.missing.isEmpty)
    }

    @Test func verifyFileExistenceAllMissing() {
        let checker = MockFileExistenceChecker(existingPaths: [])
        let service = LibraryRefreshService(fileChecker: checker)

        let books = [
            makeProvenanceItem(key: "k1", filePath: "/missing1.epub"),
            makeProvenanceItem(key: "k2", filePath: "/missing2.epub"),
        ]

        let result = service.verifyFileExistence(books: books)

        #expect(result.existing.isEmpty)
        #expect(result.missing.count == 2)
    }

    @Test func verifyFileExistenceEmptyList() {
        let checker = MockFileExistenceChecker(existingPaths: [])
        let service = LibraryRefreshService(fileChecker: checker)

        let result = service.verifyFileExistence(books: [])

        #expect(result.existing.isEmpty)
        #expect(result.missing.isEmpty)
    }

    @Test func verifyFileExistenceNilPathTreatedAsMissing() {
        let checker = MockFileExistenceChecker(existingPaths: ["/exists.epub"])
        let service = LibraryRefreshService(fileChecker: checker)

        let books = [
            makeProvenanceItem(key: "k1", filePath: nil),
        ]

        let result = service.verifyFileExistence(books: books)

        #expect(result.existing.isEmpty)
        #expect(result.missing.count == 1)
    }

    // MARK: - Throttling

    @Test func throttleAllowsFirstCall() {
        let service = LibraryRefreshService(throttleInterval: 5.0)

        #expect(service.shouldAllowRefresh() == true)
    }

    @Test func throttleBlocksImmediateSecondCall() {
        let service = LibraryRefreshService(throttleInterval: 5.0)

        service.recordRefresh()
        #expect(service.shouldAllowRefresh() == false)
    }

    @Test func throttleAllowsAfterInterval() async {
        let service = LibraryRefreshService(throttleInterval: 0.05)

        service.recordRefresh()
        try? await Task.sleep(for: .milliseconds(60))
        #expect(service.shouldAllowRefresh() == true)
    }

    // MARK: - Helpers

    private func makeProvenanceItem(key: String, filePath: String?) -> LibraryRefreshService.BookFileInfo {
        LibraryRefreshService.BookFileInfo(fingerprintKey: key, sandboxFilePath: filePath)
    }
}
