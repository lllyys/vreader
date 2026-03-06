// Purpose: Unit tests for SearchIndexStore — FTS5 indexing, querying, span map.

import Testing
import Foundation
@testable import vreader

@Suite("SearchIndexStore")
struct SearchIndexStoreTests {

    // MARK: - Helpers

    private func makeStore() throws -> SearchIndexStore {
        try SearchIndexStore()
    }

    private func makeTextUnits() -> [TextUnit] {
        [
            TextUnit(sourceUnitId: "txt:segment:0", text: "Hello world this is a test document"),
            TextUnit(sourceUnitId: "txt:segment:1", text: "Another paragraph with different words"),
        ]
    }

    // MARK: - Index and search

    @Test func indexAndSearchBasic() throws {
        let store = try makeStore()
        let units = makeTextUnits()
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "hello", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits.isEmpty)
        #expect(hits.first?.fingerprintKey == "txt:abc:1024")
    }

    @Test func searchReturnsCorrectSourceUnitId() throws {
        let store = try makeStore()
        let units = makeTextUnits()
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "another", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits.isEmpty)
        #expect(hits.first?.sourceUnitId == "txt:segment:1")
    }

    @Test func searchCaseInsensitive() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello World")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "HELLO", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits.isEmpty)
    }

    @Test func searchNoResults() throws {
        let store = try makeStore()
        let units = makeTextUnits()
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "xyznonexistent", bookFingerprintKey: "txt:abc:1024")
        #expect(hits.isEmpty)
    }

    @Test func searchLimitResults() throws {
        let store = try makeStore()
        // Create many units with the word "common"
        var units: [TextUnit] = []
        for i in 0..<20 {
            units.append(TextUnit(sourceUnitId: "txt:segment:\(i)", text: "common word in segment \(i)"))
        }
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "common", bookFingerprintKey: "txt:abc:1024", limit: 5)
        #expect(hits.count <= 5)
    }

    // MARK: - Multi-book isolation

    @Test func searchIsolatedByBook() throws {
        let store = try makeStore()
        let units1 = [TextUnit(sourceUnitId: "txt:segment:0", text: "Alpha bravo charlie")]
        let units2 = [TextUnit(sourceUnitId: "txt:segment:0", text: "Delta echo foxtrot")]

        try store.indexBook(fingerprintKey: "book1", textUnits: units1)
        try store.indexBook(fingerprintKey: "book2", textUnits: units2)

        let hits1 = try store.search(query: "alpha", bookFingerprintKey: "book1")
        let hits2 = try store.search(query: "alpha", bookFingerprintKey: "book2")

        #expect(!hits1.isEmpty)
        #expect(hits2.isEmpty)
    }

    // MARK: - Span map

    @Test func spanMapStoresOffsets() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Hello world")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let spans = try store.tokenSpans(
            fingerprintKey: "txt:abc:1024",
            sourceUnitId: "txt:segment:0",
            normalizedToken: "hello"
        )
        #expect(!spans.isEmpty)
        #expect(spans.first?.startOffsetUTF16 == 0)
        #expect(spans.first?.endOffsetUTF16 == 5)
    }

    @Test func spanMapCJK() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "你好世界")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let spans = try store.tokenSpans(
            fingerprintKey: "txt:abc:1024",
            sourceUnitId: "txt:segment:0",
            normalizedToken: "你好"
        )
        // CJK tokens may be tokenized differently; check we stored something
        let allSpans = try store.tokenSpans(
            fingerprintKey: "txt:abc:1024",
            sourceUnitId: "txt:segment:0"
        )
        #expect(!allSpans.isEmpty)
    }

    // MARK: - Edge cases

    @Test func emptyTextUnits() throws {
        let store = try makeStore()
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: [])
        let hits = try store.search(query: "anything", bookFingerprintKey: "txt:abc:1024")
        #expect(hits.isEmpty)
    }

    @Test func emptyQuery() throws {
        let store = try makeStore()
        let units = makeTextUnits()
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)
        let hits = try store.search(query: "", bookFingerprintKey: "txt:abc:1024")
        #expect(hits.isEmpty)
    }

    @Test func unicodeQuery() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "café résumé")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        // FTS5 with unicode61 should find diacritic-folded matches
        let hits = try store.search(query: "cafe", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits.isEmpty)
    }

    @Test func searchHitContainsSnippet() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "The quick brown fox jumps over the lazy dog")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "fox", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits.isEmpty)
        #expect(hits.first?.snippet != nil)
    }
}
