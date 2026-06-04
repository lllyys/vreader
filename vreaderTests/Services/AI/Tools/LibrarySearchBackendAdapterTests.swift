// Purpose: Feature #91 WI-8b — pin the LibrarySearchBackendAdapter's mapping +
// forwarding: libraryBooks → LibraryPersisting, indexState → the three store reads
// mapped into LibraryIndexState, restoreSegmentOffsets → the search service, and
// search → page 0 with pageSize == the per-book limit. The index-coverage gate
// itself is tested in LibraryBookSearchGateTests.
//
// @coordinates-with: LibrarySearchBackendAdapter.swift, LibraryBookSearchGate.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-8)

import Testing
import Foundation
@testable import vreader

private struct StubLibrary: LibraryPersisting {
    let books: [LibraryBookItem]
    func fetchAllLibraryBooks() async throws -> [LibraryBookItem] { books }
    func deleteBook(fingerprintKey: String) async throws {}
}

/// Records the fingerprintKey passed to EACH of the three reads, so a test can
/// prove the key is forwarded (not dropped) — and returns asymmetric values so a
/// field swap is caught.
private final class RecordingIndex: SearchIndexReading, @unchecked Sendable {
    let indexed: Bool
    let reindex: Bool
    let offsets: [Int: Int]?
    private(set) var keys: [String] = []
    init(indexed: Bool, reindex: Bool, offsets: [Int: Int]?) {
        self.indexed = indexed; self.reindex = reindex; self.offsets = offsets
    }
    func isBookIndexed(fingerprintKey: String) -> Bool { keys.append(fingerprintKey); return indexed }
    func requiresReindex(fingerprintKey: String) -> Bool { keys.append(fingerprintKey); return reindex }
    func getSegmentBaseOffsets(fingerprintKey: String) -> [Int: Int]? {
        keys.append(fingerprintKey); return offsets
    }
}

private final class RecordingSearch: IndexedBookSearching, @unchecked Sendable {
    var stubbedPage = SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    private(set) var lastSearch: (query: String, key: String, page: Int, pageSize: Int)?
    private(set) var restoredKey: String?
    private(set) var restoredOffsets: [Int: Int]?

    func search(
        query: String, bookFingerprint: DocumentFingerprint, page: Int, pageSize: Int
    ) async throws -> SearchResultPage {
        lastSearch = (query, bookFingerprint.canonicalKey, page, pageSize)
        return stubbedPage
    }
    func restoreSegmentOffsets(fingerprint: DocumentFingerprint, offsets: [Int: Int]) {
        restoredKey = fingerprint.canonicalKey
        restoredOffsets = offsets
    }
}

@Suite("Feature #91 WI-8b — LibrarySearchBackendAdapter")
struct LibrarySearchBackendAdapterTests {

    private static let fp = DocumentFingerprint(
        contentSHA256: String(repeating: "a", count: 64), fileByteCount: 4096, format: .txt)

    private func adapter(
        library: StubLibrary = StubLibrary(books: []),
        index: RecordingIndex = RecordingIndex(indexed: true, reindex: false, offsets: nil),
        search: RecordingSearch = RecordingSearch()
    ) -> LibrarySearchBackendAdapter {
        LibrarySearchBackendAdapter(library: library, index: index, search: search)
    }

    @Test("libraryBooks forwards to LibraryPersisting.fetchAllLibraryBooks")
    func libraryBooksForwards() async throws {
        let book = LibraryBookItem.stub(
            fingerprintKey: "txt:\(String(repeating: "a", count: 64)):4096", title: "B", format: "txt")
        let books = try await adapter(library: StubLibrary(books: [book])).libraryBooks()
        #expect(books.map(\.title) == ["B"])
    }

    @Test("indexState maps the three store reads into the right LibraryIndexState slots")
    func indexStateMaps() async {
        // Asymmetric values (isIndexed=false, requiresReindex=true) so an
        // isIndexed↔requiresReindex swap would fail.
        let index = RecordingIndex(indexed: false, reindex: true, offsets: [0: 0, 1: 4096])
        let state = await adapter(index: index).indexState(fingerprintKey: "the-key")
        #expect(state == LibraryIndexState(
            isIndexed: false, requiresReindex: true, segmentOffsets: [0: 0, 1: 4096]))
        #expect(index.keys == ["the-key", "the-key", "the-key"])   // the key reached all 3 reads
    }

    @Test("restoreSegmentOffsets forwards the fingerprint AND the offsets payload")
    func restoreForwards() async {
        let search = RecordingSearch()
        await adapter(search: search).restoreSegmentOffsets(
            fingerprint: Self.fp, offsets: [0: 0, 1: 4096])
        #expect(search.restoredKey == Self.fp.canonicalKey)
        #expect(search.restoredOffsets == [0: 0, 1: 4096])
    }

    @Test("search forwards at page 0 with pageSize == the per-book limit")
    func searchForwards() async throws {
        let search = RecordingSearch()
        _ = try await adapter(search: search).search(query: "darcy", fingerprint: Self.fp, limit: 5)
        #expect(search.lastSearch?.page == 0)
        #expect(search.lastSearch?.pageSize == 5)
        #expect(search.lastSearch?.key == Self.fp.canonicalKey)
        #expect(search.lastSearch?.query == "darcy")
    }
}
