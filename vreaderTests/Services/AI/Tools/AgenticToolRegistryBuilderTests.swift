// Purpose: Feature #91 WI-8b — pin the agentic tool-registry assembly: with an
// open book all three tools are offered; general (no-book) chat omits
// search_current_book; a book fingerprint without a live search service also omits
// it. Stubs for the three backends; the builder is pure assembly.
//
// @coordinates-with: AgenticToolRegistryBuilder.swift, AIToolRegistry.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-8)

import Testing
import Foundation
@testable import vreader

private struct StubSearch: SearchProviding {
    func indexBook(
        fingerprint: DocumentFingerprint, textUnits: [TextUnit],
        segmentBaseOffsets: [Int: Int]?) async throws {}
    func search(
        query: String, bookFingerprint: DocumentFingerprint, page: Int, pageSize: Int
    ) async throws -> SearchResultPage {
        SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    }
    func removeIndex(fingerprint: DocumentFingerprint) async throws {}
    func isIndexed(fingerprint: DocumentFingerprint) async -> Bool { true }
}

private struct StubLibraryBackend: LibrarySearchBackend {
    func libraryBooks() async throws -> [LibraryBookItem] { [] }
    func indexState(fingerprintKey: String) async -> LibraryIndexState {
        LibraryIndexState(isIndexed: false, requiresReindex: false, segmentOffsets: nil)
    }
    func restoreSegmentOffsets(fingerprint: DocumentFingerprint, offsets: [Int: Int]) async {}
    func search(
        query: String, fingerprint: DocumentFingerprint, limit: Int
    ) async throws -> SearchResultPage {
        SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    }
}

private struct StubContent: BookContentProvider {
    func findBook(title: String) async -> BookTitleResolution { .notFound }
    func extractText(fingerprintKey: String) async throws -> String { "" }
}

/// Records which book fingerprints search_other_books actually searches, so a test
/// can prove the OPEN book is excluded (not merely that the tool exists).
private final class SpyLibraryBackend: LibrarySearchBackend, @unchecked Sendable {
    let books: [LibraryBookItem]
    private(set) var searchedKeys: [String] = []
    init(books: [LibraryBookItem]) { self.books = books }
    func libraryBooks() async throws -> [LibraryBookItem] { books }
    func indexState(fingerprintKey: String) async -> LibraryIndexState {
        LibraryIndexState(isIndexed: true, requiresReindex: false, segmentOffsets: nil)  // epub → searchable
    }
    func restoreSegmentOffsets(fingerprint: DocumentFingerprint, offsets: [Int: Int]) async {}
    func search(
        query: String, fingerprint: DocumentFingerprint, limit: Int
    ) async throws -> SearchResultPage {
        searchedKeys.append(fingerprint.canonicalKey)
        return SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    }
}

@Suite("Feature #91 WI-8b — AgenticToolRegistryBuilder")
struct AgenticToolRegistryBuilderTests {

    private static let fp = DocumentFingerprint(
        contentSHA256: String(repeating: "a", count: 64), fileByteCount: 4096, format: .epub)

    @Test("with an open book + a live search service, the registry offers all three tools")
    func includesCurrentBookTool() {
        let registry = AgenticToolRegistryBuilder.build(
            currentBook: Self.fp, currentBookSearch: StubSearch(),
            libraryBackend: StubLibraryBackend(), contentProvider: StubContent())
        #expect(registry.definitions().map(\.name)
            == ["get_book_content", "search_current_book", "search_other_books"])
    }

    @Test("general chat (no open book) omits search_current_book")
    func noBookOmitsCurrentTool() {
        let registry = AgenticToolRegistryBuilder.build(
            currentBook: nil, currentBookSearch: nil,
            libraryBackend: StubLibraryBackend(), contentProvider: StubContent())
        #expect(registry.definitions().map(\.name) == ["get_book_content", "search_other_books"])
        #expect(!registry.isEmpty)
    }

    @Test("a book fingerprint without a live search service still omits search_current_book")
    func bookButNoSearchOmitsCurrentTool() {
        let registry = AgenticToolRegistryBuilder.build(
            currentBook: Self.fp, currentBookSearch: nil,
            libraryBackend: StubLibraryBackend(), contentProvider: StubContent())
        #expect(!registry.definitions().map(\.name).contains("search_current_book"))
        #expect(registry.definitions().map(\.name) == ["get_book_content", "search_other_books"])
    }

    @Test("the assembled search_other_books EXCLUDES the open book at runtime (not just the names)")
    func searchOtherBooksExcludesOpenBook() async {
        let openKey = "epub:\(String(repeating: "a", count: 64)):4096"
        let otherKey = "epub:\(String(repeating: "b", count: 64)):4096"
        let spy = SpyLibraryBackend(books: [
            LibraryBookItem.stub(fingerprintKey: openKey, title: "Open", format: "epub"),
            LibraryBookItem.stub(fingerprintKey: otherKey, title: "Other", format: "epub"),
        ])
        let registry = AgenticToolRegistryBuilder.build(
            currentBook: DocumentFingerprint(canonicalKey: openKey),
            currentBookSearch: StubSearch(), libraryBackend: spy, contentProvider: StubContent())

        _ = await registry.run(ToolCall(
            id: "c", name: "search_other_books", input: .object(["query": .string("x")])))

        // The builder wired currentBook?.canonicalKey into the tool → the open book
        // is NOT searched; the other indexed book IS. (A regression to nil would
        // search the open book too and fail.)
        #expect(spy.searchedKeys.contains(otherKey))
        #expect(!spy.searchedKeys.contains(openKey))
    }
}
