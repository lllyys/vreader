// Purpose: Feature #91 WI-6b — pin the search_other_books orchestration over a
// stub LibrarySearchBackend: excludes the open book, gates each book on its
// persisted index (the pure LibraryBookSearchGate, tested separately), restores
// TXT/MD offsets before searching, reports excluded/capped coverage, skips a
// per-book search failure (never fatal), and turns a missing query / library-list
// failure into an isError result — never a throw.
//
// Keys are VALID canonical fingerprint strings ("{format}:{64-hex}:{bytes}") so
// the tool's DocumentFingerprint(canonicalKey:) reconstruction round-trips.
//
// @coordinates-with: SearchOtherBooksTool.swift, LibraryBookSearchGate.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-6b)

import Testing
import Foundation
@testable import vreader

private enum StubBackendError: Error { case boom }

/// In-memory LibrarySearchBackend recording restore/search calls.
private actor StubBackend: LibrarySearchBackend {
    private let books: [LibraryBookItem]
    private let states: [String: LibraryIndexState]
    private let pages: [String: SearchResultPage]
    private let failSearchKeys: Set<String>
    private let listThrows: Bool
    private(set) var restoredKeys: [String] = []
    private(set) var searchedKeys: [String] = []
    /// Ordered call log ("restore:KEY" / "search:KEY") so a test can prove that a
    /// TXT/MD book's offsets are restored BEFORE it is searched.
    private(set) var events: [String] = []

    init(
        books: [LibraryBookItem], states: [String: LibraryIndexState],
        pages: [String: SearchResultPage] = [:], failSearchKeys: Set<String> = [],
        listThrows: Bool = false
    ) {
        self.books = books
        self.states = states
        self.pages = pages
        self.failSearchKeys = failSearchKeys
        self.listThrows = listThrows
    }

    func libraryBooks() async throws -> [LibraryBookItem] {
        if listThrows { throw StubBackendError.boom }
        return books
    }

    func indexState(fingerprintKey: String) async -> LibraryIndexState {
        states[fingerprintKey]
            ?? LibraryIndexState(isIndexed: false, requiresReindex: false, segmentOffsets: nil)
    }

    func restoreSegmentOffsets(fingerprint: DocumentFingerprint, offsets: [Int: Int]) async {
        restoredKeys.append(fingerprint.canonicalKey)
        events.append("restore:\(fingerprint.canonicalKey)")
    }

    func search(
        query: String, fingerprint: DocumentFingerprint, limit: Int
    ) async throws -> SearchResultPage {
        searchedKeys.append(fingerprint.canonicalKey)
        events.append("search:\(fingerprint.canonicalKey)")
        if failSearchKeys.contains(fingerprint.canonicalKey) { throw StubBackendError.boom }
        return pages[fingerprint.canonicalKey]
            ?? SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    }
}

@Suite("Feature #91 WI-6b — SearchOtherBooksTool")
struct SearchOtherBooksToolTests {

    // MARK: - Builders

    private static func key(_ format: String, _ c: Character) -> String {
        "\(format):\(String(repeating: c, count: 64)):4096"
    }

    private static func book(_ key: String, format: String, title: String) -> LibraryBookItem {
        .stub(fingerprintKey: key, title: title, format: format, fileByteCount: 4096)
    }

    private static func indexed(offsets: [Int: Int]? = nil, reindex: Bool = false) -> LibraryIndexState {
        LibraryIndexState(isIndexed: true, requiresReindex: reindex, segmentOffsets: offsets)
    }

    private static func page(_ key: String, snippet: String) -> SearchResultPage {
        let fp = DocumentFingerprint(canonicalKey: key)!
        let loc = Locator(
            bookFingerprint: fp, href: nil, progression: nil, totalProgression: nil, cfi: nil,
            page: nil, charOffsetUTF16: 0, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil)
        return SearchResultPage(
            results: [SearchResult(id: "\(key):0", snippet: snippet, locator: loc, sourceContext: "Ch 1")],
            page: 0, hasMore: false, totalEstimate: 1)
    }

    private func tool(
        _ backend: StubBackend, openKey: String?, maxBooks: Int = 10, maxContentBytes: Int = 8_000
    ) -> SearchOtherBooksTool {
        SearchOtherBooksTool(
            backend: backend, currentBookFingerprintKey: openKey,
            maxBooks: maxBooks, maxContentBytes: maxContentBytes)
    }

    // MARK: - Tests

    @Test("definition advertises the tool name + required query string")
    func definitionShape() {
        let backend = StubBackend(books: [], states: [:])
        let def = tool(backend, openKey: nil).definition
        #expect(def.name == "search_other_books")
        #expect(def.inputSchema["required"] == .array([.string("query")]))
    }

    @Test("excludes the open book, searches the eligible ones, restores TXT offsets first")
    func excludesOpenSearchesEligibleRestoresTxt() async {
        let kA = Self.key("epub", "a")   // eligible EPUB
        let kB = Self.key("txt", "b")    // eligible TXT (needs offset restore)
        let kC = Self.key("epub", "c")   // the OPEN book — must be skipped
        let backend = StubBackend(
            books: [
                Self.book(kA, format: "epub", title: "Alpha"),
                Self.book(kB, format: "txt", title: "Beta"),
                Self.book(kC, format: "epub", title: "OpenBook"),
            ],
            states: [kA: Self.indexed(), kB: Self.indexed(offsets: [0: 0]), kC: Self.indexed()],
            pages: [kA: Self.page(kA, snippet: "alpha hit"), kB: Self.page(kB, snippet: "beta hit")])

        let result = await tool(backend, openKey: kC).run(.object(["query": .string("hit")]))

        #expect(result.isError == false)
        let searched = await backend.searchedKeys
        #expect(searched.contains(kA))
        #expect(searched.contains(kB))
        #expect(!searched.contains(kC))                 // the open book is never searched
        // The TXT book had its offsets restored BEFORE searching; the EPUB did not.
        let restored = await backend.restoredKeys
        #expect(restored == [kB])
        // ORDERING: for the TXT book, restore must precede search (else a search
        // before the offsets are live would drop every result).
        let events = await backend.events
        let restoreIdx = events.firstIndex(of: "restore:\(kB)")
        let searchIdx = events.firstIndex(of: "search:\(kB)")
        #expect(restoreIdx != nil && searchIdx != nil)
        #expect((restoreIdx ?? 1) < (searchIdx ?? 0))
        #expect(result.content.contains("alpha hit"))
        #expect(result.content.contains("beta hit"))
        #expect(result.content.contains("Alpha"))
        #expect(result.content.contains("Beta"))
    }

    @Test("the gate keys on the CANONICAL fingerprint format, not the stale book.format column")
    func gatesOnCanonicalFormatNotColumn() async {
        // Two rows whose `book.format` column DISAGREES with the canonical key:
        //  - canonical TXT, column lies "epub", offsets present
        //  - canonical EPUB, column lies "txt", offsets NIL
        let txtKey = Self.key("txt", "a")
        let epubKey = Self.key("epub", "b")
        let backend = StubBackend(
            books: [
                Self.book(txtKey, format: "epub", title: "ReallyTxt"),   // column lies
                Self.book(epubKey, format: "txt", title: "ReallyEpub"),  // column lies
            ],
            states: [txtKey: Self.indexed(offsets: [0: 0]), epubKey: Self.indexed(offsets: nil)],
            pages: [txtKey: Self.page(txtKey, snippet: "t hit"), epubKey: Self.page(epubKey, snippet: "e hit")])

        let result = await tool(backend, openKey: nil).run(.object(["query": .string("hit")]))

        #expect(result.isError == false)
        // Canonical-TXT → offsets restored (book.format=="epub" would have skipped it).
        // Canonical-EPUB with nil offsets → searched, NOT excluded as staleOffsets
        // (book.format=="txt" + nil offsets would have wrongly excluded it).
        let restored = await backend.restoredKeys
        #expect(restored == [txtKey])
        let searched = await backend.searchedKeys
        #expect(searched.contains(txtKey))
        #expect(searched.contains(epubKey))
        #expect(result.content.contains("t hit"))
        #expect(result.content.contains("e hit"))
    }

    @Test("excluded books (not-indexed / stale TXT) are reported by count, not searched")
    func reportsExcludedCoverage() async {
        let kGood = Self.key("epub", "a")
        let kNever = Self.key("epub", "b")   // not indexed
        let kStale = Self.key("txt", "c")    // indexed but NIL offsets → stale
        let backend = StubBackend(
            books: [
                Self.book(kGood, format: "epub", title: "Good"),
                Self.book(kNever, format: "epub", title: "Never"),
                Self.book(kStale, format: "txt", title: "Stale"),
            ],
            states: [
                kGood: Self.indexed(),
                kNever: LibraryIndexState(isIndexed: false, requiresReindex: false, segmentOffsets: nil),
                kStale: Self.indexed(offsets: nil),
            ],
            pages: [kGood: Self.page(kGood, snippet: "found it")])

        let result = await tool(backend, openKey: nil).run(.object(["query": .string("found")]))

        #expect(result.isError == false)
        #expect(result.content.contains("found it"))
        #expect(result.content.contains("2 book(s) not searched"))   // Never + Stale
        let searched = await backend.searchedKeys
        #expect(searched == [kGood])                                 // only the eligible book
    }

    @Test("the number of books searched is capped; the rest are reported")
    func capsBooksSearched() async {
        let keys = (0..<5).map { Self.key("epub", Character(UnicodeScalar(97 + $0)!)) }
        let backend = StubBackend(
            books: keys.enumerated().map { Self.book($1, format: "epub", title: "B\($0)") },
            states: Dictionary(uniqueKeysWithValues: keys.map { ($0, Self.indexed()) }),
            pages: Dictionary(uniqueKeysWithValues: keys.map { ($0, Self.page($0, snippet: "x")) }))

        let result = await tool(backend, openKey: nil, maxBooks: 2).run(.object(["query": .string("x")]))

        #expect(result.isError == false)
        let searched = await backend.searchedKeys
        #expect(searched.count == 2)                                 // only maxBooks searched
        #expect(result.content.contains("3 more indexed book(s) not searched (result cap)"))
    }

    @Test("zero eligible books yields a coverage message, not an error")
    func zeroEligibleCoverageMessage() async {
        let kA = Self.key("epub", "a")
        let kB = Self.key("epub", "b")
        let backend = StubBackend(
            books: [Self.book(kA, format: "epub", title: "A"), Self.book(kB, format: "epub", title: "B")],
            states: [
                kA: LibraryIndexState(isIndexed: false, requiresReindex: false, segmentOffsets: nil),
                kB: LibraryIndexState(isIndexed: false, requiresReindex: false, segmentOffsets: nil),
            ])

        let result = await tool(backend, openKey: nil).run(.object(["query": .string("x")]))

        #expect(result.isError == false)
        #expect(result.content.localizedCaseInsensitiveContains("no other indexed books"))
        #expect(result.content.contains("2 book(s) not searched"))
    }

    @Test("a per-book search failure is skipped, not fatal")
    func perBookFailureSkipped() async {
        let kA = Self.key("epub", "a")   // its search THROWS
        let kB = Self.key("epub", "b")   // succeeds
        let backend = StubBackend(
            books: [Self.book(kA, format: "epub", title: "Boom"), Self.book(kB, format: "epub", title: "Fine")],
            states: [kA: Self.indexed(), kB: Self.indexed()],
            pages: [kB: Self.page(kB, snippet: "survivor")],
            failSearchKeys: [kA])

        let result = await tool(backend, openKey: nil).run(.object(["query": .string("x")]))

        #expect(result.isError == false)                            // the throw didn't sink the tool
        #expect(result.content.contains("survivor"))
        #expect(!result.content.contains("Boom"))                   // the failing book contributes nothing
        // The failed book is reported as a failure, NOT silently counted as searched.
        #expect(result.content.contains("1 book(s) failed to search"))
    }

    @Test("an eligible book with zero hits reports the COMPLETED count, not the attempted count")
    func eligibleButNoHits() async {
        let kA = Self.key("epub", "a")
        let backend = StubBackend(
            books: [Self.book(kA, format: "epub", title: "Empty")],
            states: [kA: Self.indexed()],
            pages: [kA: SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)])

        let result = await tool(backend, openKey: nil).run(.object(["query": .string("absent")]))

        #expect(result.isError == false)
        #expect(result.content.contains("No matches for \"absent\" in 1 other indexed book(s)"))
    }

    @Test("when every eligible book's search fails, coverage signals failure (not 'no matches')")
    func allSearchesFailed() async {
        let kA = Self.key("epub", "a")
        let backend = StubBackend(
            books: [Self.book(kA, format: "epub", title: "Boom")],
            states: [kA: Self.indexed()],
            failSearchKeys: [kA])

        let result = await tool(backend, openKey: nil).run(.object(["query": .string("x")]))

        #expect(result.isError == false)
        // NOT "no matches in 1 book" — the book was attempted but never completed.
        #expect(!result.content.localizedCaseInsensitiveContains("no matches"))
        #expect(result.content.localizedCaseInsensitiveContains("couldn't search"))
        #expect(result.content.contains("1 book(s) failed to search"))
    }

    @Test("a malformed fingerprint key is excluded, never searched")
    func malformedKeyExcluded() async {
        let kGood = Self.key("epub", "a")
        let kBad = "epub:not-a-valid-sha:1"                          // invalid SHA → init? returns nil
        let backend = StubBackend(
            books: [Self.book(kGood, format: "epub", title: "Good"), Self.book(kBad, format: "epub", title: "Bad")],
            states: [kGood: Self.indexed()],
            pages: [kGood: Self.page(kGood, snippet: "ok")])

        let result = await tool(backend, openKey: nil).run(.object(["query": .string("ok")]))

        #expect(result.isError == false)
        #expect(result.content.contains("ok"))
        #expect(result.content.contains("1 book(s) not searched"))
        let searched = await backend.searchedKeys
        #expect(searched == [kGood])
    }

    @Test("the coverage footer survives byte-clamp truncation of a large hit set")
    func coverageSurvivesTruncation() async {
        // 8 eligible books with long snippets (would overflow a tight budget) plus
        // 2 not-indexed books → the coverage line must NOT be truncated away.
        // (Keys repeat a single HEX digit so DocumentFingerprint(canonicalKey:)
        // accepts them — 'g'/'h' etc. are not valid SHA hex.)
        let hex = Array("0123456789abcdef")
        let eligible = (0..<8).map { Self.key("epub", hex[$0]) }      // '0'..'7'
        let excluded = [Self.key("epub", hex[14]), Self.key("epub", hex[15])]  // 'e','f'
        let longSnippet = String(repeating: "lorem ipsum dolor ", count: 30)   // ~540 chars
        var books = eligible.map { Self.book($0, format: "epub", title: "E") }
        books += excluded.map { Self.book($0, format: "epub", title: "X") }
        var states = Dictionary(uniqueKeysWithValues: eligible.map { ($0, Self.indexed()) })
        for k in excluded {
            states[k] = LibraryIndexState(isIndexed: false, requiresReindex: false, segmentOffsets: nil)
        }
        let pages = Dictionary(uniqueKeysWithValues: eligible.map { ($0, Self.page($0, snippet: longSnippet)) })
        let backend = StubBackend(books: books, states: states, pages: pages)

        let result = await tool(backend, openKey: nil, maxContentBytes: 400)
            .run(.object(["query": .string("lorem")]))

        #expect(result.isError == false)
        #expect(result.content.contains("…(truncated)"))                  // the body WAS truncated
        #expect(result.content.contains("2 book(s) not searched"))        // …yet coverage survived
    }

    // MARK: - Bad input / failure is data

    @Test("a missing query yields an isError result")
    func missingQuery() async {
        let backend = StubBackend(books: [], states: [:])
        let result = await tool(backend, openKey: nil).run(.object(["nope": .number(1)]))
        #expect(result.isError == true)
    }

    @Test("a library-list failure becomes an isError result, not a crash")
    func libraryListThrows() async {
        let backend = StubBackend(books: [], states: [:], listThrows: true)
        let result = await tool(backend, openKey: nil).run(.object(["query": .string("x")]))
        #expect(result.isError == true)
    }
}
