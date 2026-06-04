// Purpose: Feature #91 WI-6a — pin the `search_current_book` tool: forwards the
// `query` to `SearchProviding.search` scoped to the open book's fingerprint at
// page 0 with pageSize == maxResults, formats snippets (FTS5 <b> markers stripped,
// one line, source at line-end), byte-clamps EVERY branch, and turns a missing
// query / search failure into an `isError` ToolResult — never a throw.
//
// Uses a local capturing stub (records query / fingerprint / page / pageSize /
// callCount) so the request-side contract — current-book scoping + the cap — is
// actually asserted, not just the response shape.
//
// @coordinates-with: SearchCurrentBookTool.swift, AITool.swift, SearchService.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-6a)

import Testing
import Foundation
@testable import vreader

// MARK: - Capturing stub

private enum CapturingSearchError: Error { case boom }

/// Records the exact arguments the tool forwards, so scoping (fingerprint) and the
/// request-side cap (pageSize) are testable — the shared StubSearchService doesn't
/// capture those.
private actor CapturingSearch: SearchProviding {
    private(set) var lastQuery: String?
    private(set) var lastFingerprint: DocumentFingerprint?
    private(set) var lastPage: Int?
    private(set) var lastPageSize: Int?
    private(set) var callCount = 0
    private var page = SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    private var shouldThrow = false

    func setPage(_ p: SearchResultPage) { page = p }
    func setThrow(_ v: Bool) { shouldThrow = v }

    func indexBook(
        fingerprint: DocumentFingerprint, textUnits: [TextUnit],
        segmentBaseOffsets: [Int: Int]?) async throws {}

    func search(
        query: String, bookFingerprint: DocumentFingerprint, page: Int, pageSize: Int
    ) async throws -> SearchResultPage {
        callCount += 1
        lastQuery = query
        lastFingerprint = bookFingerprint
        lastPage = page
        lastPageSize = pageSize
        if shouldThrow { throw CapturingSearchError.boom }
        return self.page
    }

    func removeIndex(fingerprint: DocumentFingerprint) async throws {}
    func isIndexed(fingerprint: DocumentFingerprint) async -> Bool { true }
}

@Suite("Feature #91 WI-6a — SearchCurrentBookTool")
struct SearchCurrentBookToolTests {

    private static let bookFP = DocumentFingerprint(
        contentSHA256: String(repeating: "a", count: 64), fileByteCount: 4096, format: .epub)

    private static func locator() -> Locator {
        Locator(
            bookFingerprint: bookFP,
            href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: 0,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil)
    }

    private static func result(_ snippet: String, _ context: String, _ i: Int) -> SearchResult {
        SearchResult(id: "x:\(i)", snippet: snippet, locator: locator(), sourceContext: context)
    }

    private func tool(
        _ stub: CapturingSearch, maxResults: Int = 8, maxContentBytes: Int = 6_000
    ) -> SearchCurrentBookTool {
        SearchCurrentBookTool(
            search: stub, bookFingerprint: Self.bookFP,
            maxResults: maxResults, maxContentBytes: maxContentBytes)
    }

    // MARK: - Definition

    @Test("definition advertises the tool name + required query string")
    func definitionShape() {
        let def = tool(CapturingSearch()).definition
        #expect(def.name == "search_current_book")
        #expect(def.inputSchema["properties"]?["query"]?["type"]?.stringValue == "string")
        #expect(def.inputSchema["required"] == .array([.string("query")]))
    }

    // MARK: - Happy path + request-side scoping/cap

    @Test("forwards the query to the open book's fingerprint at page 0, pageSize == maxResults")
    func searchesScopedAndFormats() async {
        let stub = CapturingSearch()
        await stub.setPage(SearchResultPage(
            results: [
                Self.result("the proud <b>Darcy</b> bowed", "Chapter 2", 0),
                Self.result("<b>Darcy</b> wrote a letter", "Chapter 5", 1),
            ],
            page: 0, hasMore: false, totalEstimate: 2))

        let result = await tool(stub, maxResults: 5).run(.object(["query": .string("Darcy")]))

        #expect(result.isError == false)
        // Request-side contract: scoped to THIS book, page 0, the cap forwarded.
        #expect(await stub.lastQuery == "Darcy")
        #expect(await stub.lastFingerprint == Self.bookFP)
        #expect(await stub.lastPage == 0)
        #expect(await stub.lastPageSize == 5)
        // Response: <b>…</b> markers stripped, source surfaced for citation.
        #expect(result.content.contains("the proud Darcy bowed"))
        #expect(result.content.contains("Darcy wrote a letter"))
        #expect(!result.content.contains("<b>"))
        #expect(result.content.contains("Chapter 2"))
    }

    @Test("a book-controlled chapter title with newlines stays one line per result")
    func sourceContextNormalizedToOneLine() async {
        let stub = CapturingSearch()
        await stub.setPage(SearchResultPage(
            results: [Self.result("a match", "Chapter\n  3:  Hostile\nTitle", 0)],
            page: 0, hasMore: false, totalEstimate: 1))

        let result = await tool(stub).run(.object(["query": .string("a")]))
        // One result → exactly two lines (header + one result line); the embedded
        // newlines in the chapter title must NOT add extra lines.
        #expect(result.content.split(separator: "\n").count == 2)
        #expect(result.content.contains("Chapter 3: Hostile Title"))
    }

    @Test("zero matches is a non-error result, not a failure")
    func zeroMatches() async {
        let stub = CapturingSearch()
        let result = await tool(stub).run(.object(["query": .string("nonexistent")]))
        #expect(result.isError == false)
        #expect(result.content.localizedCaseInsensitiveContains("no match"))
    }

    // MARK: - Bad input (never calls search)

    @Test("a missing query yields an isError result and does NOT call search")
    func missingQuery() async {
        let stub = CapturingSearch()
        let result = await tool(stub).run(.object(["unrelated": .number(1)]))
        #expect(result.isError == true)
        #expect(await stub.callCount == 0)
    }

    @Test("an empty / whitespace query yields an isError result and does NOT call search")
    func blankQuery() async {
        let stub = CapturingSearch()
        let result = await tool(stub).run(.object(["query": .string("   ")]))
        #expect(result.isError == true)
        #expect(await stub.callCount == 0)
    }

    // MARK: - Failure is data, never a throw

    @Test("a thrown search error becomes an isError result, not a crash")
    func searchThrows() async {
        let stub = CapturingSearch()
        await stub.setThrow(true)
        let result = await tool(stub).run(.object(["query": .string("Darcy")]))
        #expect(result.isError == true)
    }

    // MARK: - Caps

    @Test("results are capped to maxResults")
    func capsResults() async {
        let stub = CapturingSearch()
        let many = (0..<20).map { Self.result("match number \($0)", "Section \($0)", $0) }
        await stub.setPage(SearchResultPage(
            results: many, page: 0, hasMore: true, totalEstimate: 20))

        let result = await tool(stub, maxResults: 3).run(.object(["query": .string("match")]))

        #expect(result.isError == false)
        #expect(result.content.contains("match number 0"))
        #expect(result.content.contains("match number 2"))
        #expect(!result.content.contains("match number 3"))
    }

    @Test("content is byte-clamped (UTF-8) with a truncation marker, even for CJK snippets")
    func contentIsByteBounded() async {
        let stub = CapturingSearch()
        // Eight multibyte (CJK) results — joined they far exceed a 256-byte budget.
        let cjk = (0..<8).map { Self.result("这是第\($0)个匹配的段落内容，很长很长。", "第\($0)章", $0) }
        await stub.setPage(SearchResultPage(
            results: cjk, page: 0, hasMore: false, totalEstimate: 8))

        let limit = 256  // the init floor; large enough to pass, small enough to truncate 8 CJK lines
        let result = await tool(stub, maxResults: 8, maxContentBytes: limit)
            .run(.object(["query": .string("匹配")]))

        #expect(result.isError == false)
        #expect(result.content.utf8.count <= limit)            // hard byte bound
        #expect(result.content.contains("…(truncated)"))       // the cut is signalled
    }
}
