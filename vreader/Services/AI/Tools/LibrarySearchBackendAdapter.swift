// Purpose: Feature #91 WI-8b — the production LibrarySearchBackend the
// search_other_books tool (WI-6b) depends on. Pure forwarding glue over the live
// search subsystem: list books via LibraryPersisting, read each book's persisted-
// index state off the SearchIndexStore (the WI-6b gate inputs), restore TXT/MD
// offsets + run per-book FTS via the SearchService. The index-coverage RISK
// (which books are safely searchable) lives in the already-tested pure
// LibraryBookSearchGate; this adapter only maps + forwards.
//
// The concrete `SearchService` / `SearchIndexStore` are reached through two narrow
// seams (SearchIndexReading / IndexedBookSearching) so the adapter's mapping +
// forwarding is unit-testable with stubs (no live FTS DB).
//
// @coordinates-with: LibraryBookSearchGate.swift (LibrarySearchBackend + the gate),
//   SearchOtherBooksTool.swift (consumer), SearchService.swift, SearchIndexStore.swift,
//   LibraryPersisting.swift, dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-8)

import Foundation

/// The persistent-index reads the adapter needs (the WI-6b guard inputs).
/// `SearchIndexStore` conforms — it already vends exactly these.
protocol SearchIndexReading: Sendable {
    func isBookIndexed(fingerprintKey: String) -> Bool
    func requiresReindex(fingerprintKey: String) -> Bool
    func getSegmentBaseOffsets(fingerprintKey: String) -> [Int: Int]?
}

/// Per-book FTS search + TXT/MD offset restore. `SearchService` conforms.
protocol IndexedBookSearching: Sendable {
    func search(
        query: String, bookFingerprint: DocumentFingerprint, page: Int, pageSize: Int
    ) async throws -> SearchResultPage
    func restoreSegmentOffsets(fingerprint: DocumentFingerprint, offsets: [Int: Int])
}

extension SearchIndexStore: SearchIndexReading {}
extension SearchService: IndexedBookSearching {}

struct LibrarySearchBackendAdapter: LibrarySearchBackend {

    private let library: any LibraryPersisting
    private let index: any SearchIndexReading
    private let search: any IndexedBookSearching

    init(
        library: any LibraryPersisting,
        index: any SearchIndexReading,
        search: any IndexedBookSearching
    ) {
        self.library = library
        self.index = index
        self.search = search
    }

    func libraryBooks() async throws -> [LibraryBookItem] {
        try await library.fetchAllLibraryBooks()
    }

    func indexState(fingerprintKey: String) async -> LibraryIndexState {
        LibraryIndexState(
            isIndexed: index.isBookIndexed(fingerprintKey: fingerprintKey),
            requiresReindex: index.requiresReindex(fingerprintKey: fingerprintKey),
            segmentOffsets: index.getSegmentBaseOffsets(fingerprintKey: fingerprintKey))
    }

    func restoreSegmentOffsets(fingerprint: DocumentFingerprint, offsets: [Int: Int]) async {
        search.restoreSegmentOffsets(fingerprint: fingerprint, offsets: offsets)
    }

    func search(
        query: String, fingerprint: DocumentFingerprint, limit: Int
    ) async throws -> SearchResultPage {
        // search_other_books is single-page per book: always page 0, pageSize = the
        // per-book cap.
        try await search.search(query: query, bookFingerprint: fingerprint, page: 0, pageSize: limit)
    }
}
