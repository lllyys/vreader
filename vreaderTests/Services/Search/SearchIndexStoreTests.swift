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
        #expect(hits.count == 5, "Should return exactly 5 hits (limit applied to 20 available), got \(hits.count)")
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

        // Each CJK character is tokenized individually
        let spans = try store.tokenSpans(
            fingerprintKey: "txt:abc:1024",
            sourceUnitId: "txt:segment:0",
            normalizedToken: "你"
        )
        #expect(!spans.isEmpty, "Each CJK character should be an individual token")
        #expect(spans.first?.startOffsetUTF16 == 0)

        let allSpans = try store.tokenSpans(
            fingerprintKey: "txt:abc:1024",
            sourceUnitId: "txt:segment:0"
        )
        #expect(allSpans.count == 4, "4 CJK chars → 4 tokens")
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

    @Test func whitespaceOnlyQuery() throws {
        let store = try makeStore()
        let units = makeTextUnits()
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)
        let hits = try store.search(query: "   \t\n  ", bookFingerprintKey: "txt:abc:1024")
        #expect(hits.isEmpty, "Whitespace-only query should return empty, not throw")
    }

    @Test func punctuationOnlyQuery() throws {
        let store = try makeStore()
        let units = makeTextUnits()
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)
        let hits = try store.search(query: "...,,,!!!", bookFingerprintKey: "txt:abc:1024")
        #expect(hits.isEmpty, "Punctuation-only query should return empty, not throw")
    }

    @Test func unicodeQuery() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "café résumé")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        // FTS5 with unicode61 should find diacritic-folded matches
        let hits = try store.search(query: "cafe", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits.isEmpty)
    }

    @Test func searchChineseSubstring() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "这是一本关于编程的书。")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "编程", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits.isEmpty, "CJK search should match Chinese characters within a sentence")
    }

    @Test func searchChineseMultiSegment() throws {
        let store = try makeStore()
        let units = [
            TextUnit(sourceUnitId: "txt:segment:0", text: "第一章 引言"),
            TextUnit(sourceUnitId: "txt:segment:1", text: "这是一本关于编程的书"),
            TextUnit(sourceUnitId: "txt:segment:2", text: "你好世界"),
        ]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits1 = try store.search(query: "引言", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits1.isEmpty, "Should find '引言' in segment 0")

        let hits2 = try store.search(query: "编程", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits2.isEmpty, "Should find '编程' in segment 1")
        #expect(hits2.first?.sourceUnitId == "txt:segment:1")

        let hits3 = try store.search(query: "你好", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits3.isEmpty, "Should find '你好' in segment 2")
    }

    @Test func searchHitContainsSnippet() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "The quick brown fox jumps over the lazy dog")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "fox", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits.isEmpty)
        #expect(hits.first?.snippet != nil)
    }

    // MARK: - CJK search integration (bug fix coverage)

    @Test func searchCJKMixedWithLatin() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "Chapter 1 第一章 Introduction")]
        try store.indexBook(fingerprintKey: "txt:cjk:1", textUnits: units)

        let latinHits = try store.search(query: "Chapter", bookFingerprintKey: "txt:cjk:1")
        #expect(!latinHits.isEmpty, "Latin word 'Chapter' should be found in mixed CJK/Latin text")

        let cjkHits = try store.search(query: "第一章", bookFingerprintKey: "txt:cjk:1")
        #expect(!cjkHits.isEmpty, "CJK phrase '第一章' should be found in mixed CJK/Latin text")
    }

    @Test func searchJapaneseHiragana() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "こんにちは世界")]
        try store.indexBook(fingerprintKey: "txt:jp:1", textUnits: units)

        let hits = try store.search(query: "こんにちは", bookFingerprintKey: "txt:jp:1")
        #expect(!hits.isEmpty, "Japanese hiragana substring 'こんにちは' should match")
    }

    @Test func searchKoreanHangul() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "안녕하세요")]
        try store.indexBook(fingerprintKey: "txt:kr:1", textUnits: units)

        let hits = try store.search(query: "안녕", bookFingerprintKey: "txt:kr:1")
        #expect(!hits.isEmpty, "Korean Hangul substring '안녕' should match")
    }

    @Test func searchCJKWithPunctuation() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "你好，世界！这是测试。")]
        try store.indexBook(fingerprintKey: "txt:cjk:2", textUnits: units)

        let hits = try store.search(query: "世界", bookFingerprintKey: "txt:cjk:2")
        #expect(!hits.isEmpty, "CJK search should find '世界' despite surrounding Chinese punctuation")
    }

    @Test func searchSingleCJKCharacter() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "编程")]
        try store.indexBook(fingerprintKey: "txt:cjk:3", textUnits: units)

        let hits = try store.search(query: "编", bookFingerprintKey: "txt:cjk:3")
        #expect(!hits.isEmpty, "Single CJK character '编' should match within '编程'")
    }

    // MARK: - Multiple occurrences per segment (bug #2 fix)

    @Test func searchReturnsAllOccurrencesWithinSegment() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "hello world hello again hello")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "hello", bookFingerprintKey: "txt:abc:1024")
        #expect(hits.count == 3, "Should return all 3 occurrences of 'hello', got \(hits.count)")
    }

    @Test func searchReturnsAllOccurrencesAcrossSegments() throws {
        let store = try makeStore()
        let units = [
            TextUnit(sourceUnitId: "txt:segment:0", text: "hello world hello"),
            TextUnit(sourceUnitId: "txt:segment:1", text: "another hello here"),
        ]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "hello", bookFingerprintKey: "txt:abc:1024")
        #expect(hits.count == 3, "Should return all 3 occurrences across segments, got \(hits.count)")
    }

    @Test func searchReturnsDistinctOffsetsPerOccurrence() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "cat sat on cat")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "cat", bookFingerprintKey: "txt:abc:1024")
        #expect(hits.count == 2, "Should return 2 occurrences of 'cat', got \(hits.count)")

        if hits.count == 2 {
            #expect(hits[0].matchStartOffsetUTF16 != hits[1].matchStartOffsetUTF16,
                    "Each occurrence should have a distinct start offset")
        }
    }

    @Test func searchCJKReturnsAllOccurrences() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "编程是编程的基础")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "编程", bookFingerprintKey: "txt:abc:1024")
        #expect(hits.count == 2, "Should return 2 occurrences of '编程', got \(hits.count)")
    }

    @Test func searchLimitAppliesAfterExpansion() throws {
        let store = try makeStore()
        let text = (0..<20).map { "word\($0) common" }.joined(separator: " ")
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: text)]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "common", bookFingerprintKey: "txt:abc:1024", limit: 5)
        #expect(hits.count == 5, "Limit should cap expanded results at 5, got \(hits.count)")
    }

    @Test func searchMultiTokenPhraseMatchesConsecutiveTokens() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "the quick brown fox jumps over the lazy dog")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "quick brown fox", bookFingerprintKey: "txt:abc:1024")
        #expect(!hits.isEmpty, "Multi-token phrase 'quick brown fox' should match")
        if let hit = hits.first {
            // Verify the range covers all three tokens
            #expect(hit.matchStartOffsetUTF16 < hit.matchEndOffsetUTF16)
        }
    }

    @Test func searchLimitZeroReturnsAtLeastOne() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "hello world")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        // limit is clamped to max(1, limit) so 0 should still return 1
        let hits = try store.search(query: "hello", bookFingerprintKey: "txt:abc:1024", limit: 0)
        #expect(hits.count == 1, "limit=0 should be clamped to 1, got \(hits.count)")
    }

    @Test func searchMultiTokenNonAdjacentDoesNotMatch() throws {
        let store = try makeStore()
        // "quick" and "dog" both exist but are far apart — should not match as a phrase
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "the quick brown fox jumps over the lazy dog")]
        try store.indexBook(fingerprintKey: "txt:abc:1024", textUnits: units)

        let hits = try store.search(query: "quick dog", bookFingerprintKey: "txt:abc:1024")
        #expect(hits.isEmpty, "Non-adjacent tokens 'quick' and 'dog' should not match as phrase, got \(hits.count)")
    }

    @Test func searchFullWidthDigitsMixedWithCJK() throws {
        let store = try makeStore()
        let units = [TextUnit(sourceUnitId: "txt:segment:0", text: "第１章 引言")]
        try store.indexBook(fingerprintKey: "txt:cjk:4", textUnits: units)

        let hits = try store.search(query: "引言", bookFingerprintKey: "txt:cjk:4")
        #expect(!hits.isEmpty, "CJK search should find '引言' despite full-width digits in surrounding text")
    }
}
