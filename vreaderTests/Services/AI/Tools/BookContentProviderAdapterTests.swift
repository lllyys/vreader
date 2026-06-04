// Purpose: Feature #91 WI-8b — pin the production BookContentProvider's title
// resolution (the GetBookContentTool seam): case-insensitive exact match →
// notFound / found / ambiguous-with-author, the canonical-format-derived
// BookContentInfo, and the malformed-key throw in extractText. The library is a
// stub; the file extraction is covered by ClosedBookTextExtractorTests / device.
//
// @coordinates-with: BookContentProviderAdapter.swift, GetBookContentGate.swift,
//   LibraryPersisting.swift, dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-8)

import Testing
import Foundation
@testable import vreader

private enum StubLibraryError: Error { case boom }

private struct StubLibrary: LibraryPersisting {
    let books: [LibraryBookItem]
    let fetchThrows: Bool
    init(books: [LibraryBookItem], fetchThrows: Bool = false) {
        self.books = books
        self.fetchThrows = fetchThrows
    }
    func fetchAllLibraryBooks() async throws -> [LibraryBookItem] {
        if fetchThrows { throw StubLibraryError.boom }
        return books
    }
    func deleteBook(fingerprintKey: String) async throws {}
}

@Suite("Feature #91 WI-8b — BookContentProviderAdapter")
struct BookContentProviderAdapterTests {

    private static func key(_ c: Character) -> String {
        "epub:\(String(repeating: c, count: 64)):4096"
    }

    private static func book(_ title: String, key: String, author: String? = nil) -> LibraryBookItem {
        .stub(fingerprintKey: key, title: title, author: author, format: "epub")
    }

    @Test("an exact (case-insensitive) title resolves to that book, format derived from the key")
    func findsByTitle() async {
        let adapter = BookContentProviderAdapter(library: StubLibrary(books: [
            Self.book("Moby Dick", key: Self.key("a")),
            Self.book("Pride and Prejudice", key: Self.key("b")),
        ]))
        guard case .found(let info) = await adapter.findBook(title: "moby dick") else {
            Issue.record("expected found"); return
        }
        #expect(info.fingerprintKey == Self.key("a"))
        #expect(info.title == "Moby Dick")
        #expect(info.isReadable == true)   // .stub defaults fileState .local
        #expect(info.format == "epub")     // derived from the fingerprint key, not a column
    }

    @Test("no matching (or blank) title resolves to notFound")
    func notFound() async {
        let adapter = BookContentProviderAdapter(
            library: StubLibrary(books: [Self.book("X", key: Self.key("a"))]))
        #expect(await adapter.findBook(title: "ghost") == .notFound)
        #expect(await adapter.findBook(title: "   ") == .notFound)
    }

    @Test("two books sharing a title resolve to ambiguous, carrying authors to disambiguate")
    func ambiguous() async {
        let adapter = BookContentProviderAdapter(library: StubLibrary(books: [
            Self.book("Dune", key: Self.key("a"), author: "Frank Herbert"),
            Self.book("Dune", key: Self.key("b"), author: "Someone Else"),
        ]))
        guard case .ambiguous(let candidates) = await adapter.findBook(title: "Dune") else {
            Issue.record("expected ambiguous"); return
        }
        #expect(candidates.count == 2)
        #expect(candidates.contains { $0.author == "Frank Herbert" })
    }

    @Test("a library-fetch failure collapses to notFound, never a crash")
    func fetchFailureNotFound() async {
        let adapter = BookContentProviderAdapter(
            library: StubLibrary(books: [Self.book("Real", key: Self.key("a"))], fetchThrows: true))
        #expect(await adapter.findBook(title: "Real") == .notFound)
    }

    @Test("format is derived from the KEY even when the book.format column drifts; isReadable propagates")
    func formatFromKeyAndLocalityPropagation() async {
        // A row whose canonical key says TXT but whose `format` column lies "epub",
        // and which is remote-only (not readable).
        let txtKey = "txt:\(String(repeating: "c", count: 64)):4096"
        let drifted = LibraryBookItem.stub(
            fingerprintKey: txtKey, title: "Drift", format: "epub")   // column LIES
        let remote = LibraryBookItem(
            fingerprintKey: "pdf:\(String(repeating: "d", count: 64)):4096", title: "Remote",
            author: nil, coverImagePath: nil, format: "pdf", fileByteCount: 1, addedAt: Date(),
            lastOpenedAt: nil, isFavorite: false, totalReadingSeconds: 0, averagePagesPerHour: nil,
            averageWordsPerMinute: nil, fileState: .remoteOnly)
        let adapter = BookContentProviderAdapter(library: StubLibrary(books: [drifted, remote]))

        guard case .found(let txt) = await adapter.findBook(title: "Drift") else {
            Issue.record("expected found"); return
        }
        #expect(txt.format == "txt")        // derived from the key, NOT the "epub" column
        #expect(txt.isReadable == true)

        guard case .found(let rem) = await adapter.findBook(title: "Remote") else {
            Issue.record("expected found"); return
        }
        #expect(rem.isReadable == false)    // fileState .remoteOnly propagated
    }

    @Test("extractText rejects a malformed fingerprint key, never reaching the file")
    func extractTextMalformedKey() async {
        let adapter = BookContentProviderAdapter(library: StubLibrary(books: []))
        await #expect(throws: (any Error).self) {
            _ = try await adapter.extractText(fingerprintKey: "epub:not-a-sha:1")
        }
    }
}
