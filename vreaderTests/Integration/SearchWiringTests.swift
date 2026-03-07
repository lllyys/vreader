// Purpose: Integration test verifying search pipeline wiring.
// When a book is indexed via SearchService and queried via SearchViewModel,
// results are returned. This validates the contract that ReaderContainerView
// must fulfill by wiring these components together.

import Testing
import Foundation
@testable import vreader

@Suite("Search Wiring Integration")
struct SearchWiringTests {

    // MARK: - Helpers

    private static func makeFingerprint() -> DocumentFingerprint {
        DocumentFingerprint(
            contentSHA256: "a" + String(repeating: "0", count: 63),
            fileByteCount: 1000,
            format: .txt
        )
    }

    // MARK: - Tests

    @Test @MainActor func searchViewModelFindsIndexedContent() async throws {
        // This test validates the wiring contract:
        // 1. Create SearchIndexStore + SearchService
        // 2. Index a book's text
        // 3. Create SearchViewModel with the service
        // 4. Search returns results
        let store = try SearchIndexStore()
        let service = SearchService(store: store)
        let fingerprint = Self.makeFingerprint()

        // Index some content
        let textUnits = [
            TextUnit(sourceUnitId: "txt:segment:0", text: "Hello World, this is a test document."),
            TextUnit(sourceUnitId: "txt:segment:1", text: "Swift programming is powerful."),
        ]
        try await service.indexBook(
            fingerprint: fingerprint,
            textUnits: textUnits,
            segmentBaseOffsets: [0: 0, 1: 36]
        )

        // Verify book is indexed
        let isIndexed = await service.isIndexed(fingerprint: fingerprint)
        #expect(isIndexed)

        // Create ViewModel and search (same wiring ReaderContainerView should do)
        let viewModel = SearchViewModel(
            searchService: service,
            bookFingerprint: fingerprint,
            debounceInterval: .zero // no debounce for test
        )

        // Trigger search
        viewModel.query = "Swift"

        // Wait for search to complete (no debounce)
        try await Task.sleep(for: .milliseconds(50))

        #expect(!viewModel.results.isEmpty)
        #expect(viewModel.results.first?.snippet.localizedCaseInsensitiveContains("Swift") == true)
    }

    @Test @MainActor func searchBeforeIndexingReturnsEmpty() async throws {
        let store = try SearchIndexStore()
        let service = SearchService(store: store)
        let fingerprint = Self.makeFingerprint()

        let viewModel = SearchViewModel(
            searchService: service,
            bookFingerprint: fingerprint,
            debounceInterval: .zero
        )

        viewModel.query = "anything"
        try await Task.sleep(for: .milliseconds(50))

        #expect(viewModel.results.isEmpty)
    }

    @Test func backgroundIndexingCoordinatorIndexesBook() async throws {
        let store = try SearchIndexStore()
        let service = SearchService(store: store)
        let coordinator = BackgroundIndexingCoordinator(searchService: service)
        let fingerprint = Self.makeFingerprint()

        let textUnits = [
            TextUnit(sourceUnitId: "txt:segment:0", text: "Background indexing test content."),
        ]

        await coordinator.enqueueIndexing(
            fingerprint: fingerprint,
            textUnits: textUnits,
            segmentBaseOffsets: [0: 0]
        )

        // Wait for background processing (background priority needs more time)
        var status: IndexingStatus = .notIndexed
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(100))
            status = await coordinator.indexingStatus(fingerprint: fingerprint)
            if status == .indexed { break }
        }
        #expect(status == .indexed)

        // Verify searchable
        let page = try await service.search(
            query: "Background",
            bookFingerprint: fingerprint,
            page: 0,
            pageSize: 10
        )
        #expect(!page.results.isEmpty)
    }
}
