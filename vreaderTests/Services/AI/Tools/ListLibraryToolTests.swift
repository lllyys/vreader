// Purpose: Feature #97 — tests for the `list_library` agentic tool: enumerate the
// user's library (titles/authors/format), with dedupe, open-book exclusion, total
// sort tie-breaks, limit clamping, restore-placeholder friendliness, canonical
// format derivation, byte-clamp, CJK pass-through, and recoverable backend errors.

import Testing
import Foundation
@testable import vreader

/// A canned `LibrarySearchBackend` — only `libraryBooks()` matters for
/// `ListLibraryTool`; the other protocol methods are unused no-ops.
private actor StubListBackend: LibrarySearchBackend {
    private let books: [LibraryBookItem]
    private let throwsOnList: Bool
    init(books: [LibraryBookItem], throwsOnList: Bool = false) {
        self.books = books
        self.throwsOnList = throwsOnList
    }
    struct ListFailure: Error {}
    func libraryBooks() async throws -> [LibraryBookItem] {
        if throwsOnList { throw ListFailure() }
        return books
    }
    func indexState(fingerprintKey: String) async -> LibraryIndexState {
        LibraryIndexState(isIndexed: false, requiresReindex: false, segmentOffsets: nil)
    }
    func restoreSegmentOffsets(fingerprint: DocumentFingerprint, offsets: [Int: Int]) async {}
    func search(query: String, fingerprint: DocumentFingerprint, limit: Int) async throws -> SearchResultPage {
        SearchResultPage(results: [], page: 0, hasMore: false, totalEstimate: 0)
    }
}

private func key(_ format: String = "epub", _ hexChar: String = "a", bytes: Int = 4096) -> String {
    "\(format):\(String(repeating: hexChar, count: 64)):\(bytes)"
}

@Suite("ListLibraryTool — feature #97")
struct ListLibraryToolTests {

    private func tool(
        _ books: [LibraryBookItem], openKey: String? = nil, throwsOnList: Bool = false
    ) -> ListLibraryTool {
        ListLibraryTool(
            backend: StubListBackend(books: books, throwsOnList: throwsOnList),
            currentBookFingerprintKey: openKey)
    }

    private func run(_ tool: ListLibraryTool, _ input: JSONValue = .object([:])) async -> ToolResult {
        await tool.run(input)
    }

    @Test func definitionAdvertisesListLibrary() {
        let def = tool([]).definition
        #expect(def.name == "list_library")
        #expect(!def.description.isEmpty)
        // schema is a well-formed object
        #expect(def.inputSchema["type"]?.stringValue == "object")
    }

    @Test func listsAllBooksWithTitleAuthorFormat() async {
        let books = [
            LibraryBookItem.stub(fingerprintKey: key("epub", "a"), title: "Dune", author: "Herbert", format: "epub"),
            LibraryBookItem.stub(fingerprintKey: key("pdf", "b"), title: "SICP", author: "Abelson", format: "pdf"),
        ]
        let result = await run(tool(books))
        #expect(!result.isError)
        #expect(result.content.contains("Dune"))
        #expect(result.content.contains("Herbert"))
        #expect(result.content.contains("SICP"))
        #expect(result.content.lowercased().contains("epub"))
        #expect(result.content.lowercased().contains("pdf"))
    }

    @Test func emptyLibraryReportsNoBooks() async {
        let result = await run(tool([]))
        #expect(!result.isError)
        #expect(result.content.lowercased().contains("no books"))
    }

    @Test func excludesOpenBookOnlyWhenRequested() async {
        let openKey = key("epub", "a")
        let books = [
            LibraryBookItem.stub(fingerprintKey: openKey, title: "OpenBook", format: "epub"),
            LibraryBookItem.stub(fingerprintKey: key("epub", "b"), title: "OtherBook", format: "epub"),
        ]
        // default: open book included
        let included = await run(tool(books, openKey: openKey))
        #expect(included.content.contains("OpenBook"))
        // include_current_book=false → excluded
        let excluded = await run(tool(books, openKey: openKey),
                                 .object(["include_current_book": .bool(false)]))
        #expect(!excluded.content.contains("OpenBook"))
        #expect(excluded.content.contains("OtherBook"))
    }

    @Test func dedupesByFingerprintKey() async {
        let dup = key("epub", "a")
        let books = [
            LibraryBookItem.stub(fingerprintKey: dup, title: "Twice", format: "epub"),
            LibraryBookItem.stub(fingerprintKey: dup, title: "Twice", format: "epub"),
        ]
        let result = await run(tool(books))
        // "Twice" appears exactly once
        let occurrences = result.content.components(separatedBy: "Twice").count - 1
        #expect(occurrences == 1)
    }

    @Test func restorePlaceholderTitleIsFriendly() async {
        let restoreTitle = "restore_" + String(repeating: "a", count: 64)
        let books = [LibraryBookItem.stub(fingerprintKey: key("epub", "c"), title: restoreTitle, format: "epub")]
        let result = await run(tool(books))
        #expect(!result.content.contains(restoreTitle))   // raw id never surfaced
        #expect(result.content.lowercased().contains("pending restore"))
    }

    @Test func normalTitleStartingWithRestoreIsUntouched() async {
        let books = [LibraryBookItem.stub(fingerprintKey: key("epub", "d"), title: "restore your faith", format: "epub")]
        let result = await run(tool(books))
        #expect(result.content.contains("restore your faith"))
    }

    @Test func limitClampedToAtLeastOne() async {
        let books = (0..<5).map {
            LibraryBookItem.stub(fingerprintKey: key("epub", String($0)), title: "Book\($0)", format: "epub")
        }
        // limit 0 must NOT empty a non-empty library
        let zero = await run(tool(books), .object(["limit": .number(0)]))
        #expect(zero.content.contains("Book"))
    }

    @Test func capsLargeLibraryAndAnnouncesPartial() async {
        let books = (0..<10).map {
            LibraryBookItem.stub(fingerprintKey: key("epub", "x", bytes: $0 + 1), title: "B\($0)", format: "epub")
        }
        let result = await run(tool(books), .object(["limit": .number(3)]))
        #expect(result.content.contains("Showing 3 of 10"))
    }

    @Test func formatDerivedFromCanonicalFingerprintNotStaleColumn() async {
        // fingerprint key says pdf, the stale column says epub → show pdf.
        let books = [LibraryBookItem.stub(fingerprintKey: key("pdf", "e"), title: "Drifted", author: nil, format: "epub")]
        let result = await run(tool(books))
        #expect(result.content.lowercased().contains("pdf"))
    }

    @Test func backendThrowsYieldsRecoverableError() async {
        let result = await run(tool([], throwsOnList: true))
        #expect(result.isError)   // recoverable as DATA, no crash
    }

    @Test func cjkTitlesPassThrough() async {
        let books = [LibraryBookItem.stub(fingerprintKey: key("epub", "f"), title: "三体", author: "刘慈欣", format: "epub")]
        let result = await run(tool(books))
        #expect(result.content.contains("三体"))
        #expect(result.content.contains("刘慈欣"))
    }

    @Test func excludingTheOnlyBookSaysOtherNotNone() async {
        // Gate-4 Medium: a library with only the open book, excluded, is NOT "no books".
        let openKey = key("epub", "a")
        let books = [LibraryBookItem.stub(fingerprintKey: openKey, title: "OnlyOne", format: "epub")]
        let result = await run(tool(books, openKey: openKey),
                               .object(["include_current_book": .bool(false)]))
        #expect(!result.isError)
        #expect(result.content.lowercased().contains("other"))
        #expect(!result.content.contains("OnlyOne"))
    }

    @Test func progressIsClampedAndNonFiniteSafe() async {
        // Gate-4 Medium: >1 must not render "134%"; +infinity must not crash.
        let books = [
            LibraryBookItem.stub(fingerprintKey: key("epub", "g"), title: "Over", format: "epub", progressFraction: 1.34),
            LibraryBookItem.stub(fingerprintKey: key("epub", "h"), title: "Inf", format: "epub", progressFraction: .infinity),
        ]
        let result = await run(tool(books))   // must not trap
        #expect(!result.content.contains("134%"))
        #expect(result.content.contains("100%"))   // 1.34 clamps to 100%
    }

    @Test func sortByTitleIsDeterministic() async {
        let books = [
            LibraryBookItem.stub(fingerprintKey: key("epub", "9"), title: "Zebra", format: "epub"),
            LibraryBookItem.stub(fingerprintKey: key("epub", "1"), title: "Apple", format: "epub"),
        ]
        let result = await run(tool(books), .object(["sort_by": .string("title")]))
        let appleIdx = result.content.range(of: "Apple")!.lowerBound
        let zebraIdx = result.content.range(of: "Zebra")!.lowerBound
        #expect(appleIdx < zebraIdx)
    }
}
