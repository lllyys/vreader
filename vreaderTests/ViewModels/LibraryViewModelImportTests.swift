// Purpose: Tests for LibraryViewModel.importFiles() — the import wiring.
// Covers happy path, multiple URLs, error handling, partial failure, and empty input.

import Testing
import Foundation
@testable import vreader

@Suite("LibraryViewModel.importFiles")
struct LibraryViewModelImportTests {

    // MARK: - Happy Path

    @Test @MainActor func importSingleFileReloadsBooks() async {
        let mockPersistence = MockLibraryPersistence()
        let mockImporter = MockBookImporter()
        let vm = LibraryViewModel(persistence: mockPersistence, importer: mockImporter)

        // Seed library so loadBooks returns something after import
        await mockPersistence.seed(.stub(title: "Imported Book"))

        let url = URL(fileURLWithPath: "/tmp/test.txt")
        await vm.importFiles([url])

        // Importer was called
        let urls = await mockImporter.importedURLs
        #expect(urls.count == 1)
        #expect(urls.first == url)

        // Books were reloaded
        #expect(vm.books.count == 1)
        #expect(vm.books.first?.title == "Imported Book")
        #expect(vm.errorMessage == nil)
    }

    @Test @MainActor func importMultipleFilesProcessesAll() async {
        let mockPersistence = MockLibraryPersistence()
        let mockImporter = MockBookImporter()
        let vm = LibraryViewModel(persistence: mockPersistence, importer: mockImporter)

        let urls = [
            URL(fileURLWithPath: "/tmp/book1.txt"),
            URL(fileURLWithPath: "/tmp/book2.epub"),
            URL(fileURLWithPath: "/tmp/book3.pdf"),
        ]
        await vm.importFiles(urls)

        let importedURLs = await mockImporter.importedURLs
        #expect(importedURLs.count == 3)
        // Verify order is preserved (sequential processing)
        #expect(importedURLs == urls)
    }

    // MARK: - Error Handling

    @Test @MainActor func importFailureSetsErrorMessage() async {
        let mockPersistence = MockLibraryPersistence()
        let mockImporter = MockBookImporter()
        await mockImporter.setDefaultError(ImportError.unsupportedFormat("docx"))
        let vm = LibraryViewModel(persistence: mockPersistence, importer: mockImporter)

        let url = URL(fileURLWithPath: "/tmp/test.docx")
        await vm.importFiles([url])

        // Error message should be the sanitized ImportError userMessage
        #expect(vm.errorMessage == ImportError.unsupportedFormat("docx").userMessage)
    }

    @Test @MainActor func importNonImportErrorGetsSanitized() async {
        let mockPersistence = MockLibraryPersistence()
        let mockImporter = MockBookImporter()
        await mockImporter.setDefaultError(PersistenceError.recordNotFound("some-key"))
        let vm = LibraryViewModel(persistence: mockPersistence, importer: mockImporter)

        let url = URL(fileURLWithPath: "/tmp/test.txt")
        await vm.importFiles([url])

        // PersistenceError is sanitized by ErrorMessageAuditor
        #expect(vm.errorMessage == "The requested item could not be found.")
    }

    // MARK: - Partial Failure

    @Test @MainActor func partialFailureImportsSuccessfulAndSetsError() async {
        let mockPersistence = MockLibraryPersistence()
        let mockImporter = MockBookImporter()

        let failURL = URL(fileURLWithPath: "/tmp/bad.docx")
        await mockImporter.setError(ImportError.unsupportedFormat("docx"), for: failURL)

        let vm = LibraryViewModel(persistence: mockPersistence, importer: mockImporter)

        // Seed library so loadBooks returns books
        await mockPersistence.seed(.stub(title: "Good Book"))

        let successURL = URL(fileURLWithPath: "/tmp/good.txt")
        await vm.importFiles([successURL, failURL])

        // Both were attempted
        let importedURLs = await mockImporter.importedURLs
        #expect(importedURLs.count == 2)

        // Books were reloaded (the successful import was persisted)
        #expect(vm.books.count == 1)

        // Error message is set for the failed one
        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage == ImportError.unsupportedFormat("docx").userMessage)
    }

    // MARK: - Empty Input

    @Test @MainActor func importEmptyURLListIsNoOp() async {
        let mockPersistence = MockLibraryPersistence()
        let mockImporter = MockBookImporter()
        let vm = LibraryViewModel(persistence: mockPersistence, importer: mockImporter)

        await vm.importFiles([])

        // No imports attempted
        let urls = await mockImporter.importedURLs
        #expect(urls.isEmpty)

        // No error
        #expect(vm.errorMessage == nil)

        // Books not loaded (no need to reload if nothing imported)
        #expect(vm.books.isEmpty)
    }

    // MARK: - Import Source

    @Test @MainActor func importUsesFilesAppSource() async {
        let mockPersistence = MockLibraryPersistence()
        let mockImporter = MockBookImporter()
        let vm = LibraryViewModel(persistence: mockPersistence, importer: mockImporter)

        let url = URL(fileURLWithPath: "/tmp/test.txt")
        await vm.importFiles([url])

        let urls = await mockImporter.importedURLs
        #expect(urls.count == 1)

        let sources = await mockImporter.importedSources
        #expect(sources.count == 1)
        #expect(sources.first == .filesApp)
    }

    // MARK: - Reloads After All Imports

    @Test @MainActor func reloadsOnceAfterAllImports() async {
        let mockPersistence = MockLibraryPersistence()
        let mockImporter = MockBookImporter()
        let vm = LibraryViewModel(persistence: mockPersistence, importer: mockImporter)

        // Seed 2 books so after reload we see them
        await mockPersistence.seedMany([
            .stub(fingerprintKey: "k1", title: "Book A"),
            .stub(fingerprintKey: "k2", title: "Book B"),
        ])

        let urls = [
            URL(fileURLWithPath: "/tmp/a.txt"),
            URL(fileURLWithPath: "/tmp/b.txt"),
        ]
        await vm.importFiles(urls)

        // After import, loadBooks was called and books are populated
        #expect(vm.books.count == 2)

        // Verify fetchAllLibraryBooks was called exactly once (not per-URL)
        let fetchCount = await mockPersistence.fetchCallCount
        #expect(fetchCount == 1)
    }

    // MARK: - Multiple Errors Show First Error

    @Test @MainActor func multipleFailuresShowsFirstError() async {
        let mockPersistence = MockLibraryPersistence()
        let mockImporter = MockBookImporter()

        let url1 = URL(fileURLWithPath: "/tmp/bad1.docx")
        let url2 = URL(fileURLWithPath: "/tmp/bad2.xyz")
        await mockImporter.setError(ImportError.unsupportedFormat("docx"), for: url1)
        await mockImporter.setError(ImportError.fileNotReadable("missing"), for: url2)

        let vm = LibraryViewModel(persistence: mockPersistence, importer: mockImporter)
        await vm.importFiles([url1, url2])

        // Error message should be the first error (unsupportedFormat for url1)
        #expect(vm.errorMessage == ImportError.unsupportedFormat("docx").userMessage)
    }

    // MARK: - ViewModel without Importer

    @Test @MainActor func viewModelWorksWithoutImporter() async {
        // The init should still work without passing an importer (backward compat)
        let mockPersistence = MockLibraryPersistence()
        let vm = LibraryViewModel(persistence: mockPersistence)

        // Should not crash, importFiles is a no-op without importer
        await vm.importFiles([URL(fileURLWithPath: "/tmp/test.txt")])
        #expect(vm.errorMessage == nil)
    }

    // MARK: - Cancellation

    @Test @MainActor func cancellationErrorNotSurfacedToUser() async {
        let mockPersistence = MockLibraryPersistence()
        let mockImporter = MockBookImporter()
        await mockImporter.setDefaultError(CancellationError())
        let vm = LibraryViewModel(persistence: mockPersistence, importer: mockImporter)

        let url = URL(fileURLWithPath: "/tmp/test.txt")
        await vm.importFiles([url])

        // CancellationError should not produce a user-facing error
        #expect(vm.errorMessage == nil)
    }
}
