// Purpose: Tests for QuoteRecovery — text quote search with context disambiguation.

import Testing
import Foundation
@testable import vreader

@Suite("QuoteRecovery")
struct QuoteRecoveryTests {

    // MARK: - Exact unique match

    @Test func exactUniqueMatchReturnsExactConfidence() throws {
        let text = "The quick brown fox jumps over the lazy dog."
        let result = QuoteRecovery.findQuote(
            quote: "brown fox",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        let r = try #require(result)
        #expect(r.confidence == .exact)
        #expect(String(text[r.matchRange]) == "brown fox")
    }

    @Test func exactMatchReturnsCorrectUTF16OffsetASCII() throws {
        let text = "Hello world"
        let result = QuoteRecovery.findQuote(
            quote: "world",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        let r = try #require(result)
        #expect(r.utf16Offset == 6)
    }

    // MARK: - Multiple matches disambiguated by context

    @Test func multipleMatchesDisambiguatedByContextBefore() throws {
        let text = "cat sat on mat. dog sat on mat."
        let result = QuoteRecovery.findQuote(
            quote: "sat on mat",
            contextBefore: "dog ",
            contextAfter: nil,
            in: text
        )
        let r = try #require(result)
        #expect(r.confidence == .contextMatch)
        // Should match the second occurrence (after "dog ")
        let matchStart = text.distance(from: text.startIndex, to: r.matchRange.lowerBound)
        #expect(matchStart > 15) // second occurrence is past midpoint
    }

    @Test func multipleMatchesDisambiguatedByContextAfter() throws {
        let text = "I like apples and I like oranges"
        let result = QuoteRecovery.findQuote(
            quote: "I like",
            contextBefore: nil,
            contextAfter: " oranges",
            in: text
        )
        let r = try #require(result)
        #expect(r.confidence == .contextMatch)
        // Should match the second "I like" (before "oranges")
        #expect(String(text[r.matchRange]) == "I like")
        #expect(r.utf16Offset > 10)
    }

    @Test func multipleMatchesDisambiguatedByBothContexts() {
        let text = "AAA BBB CCC AAA BBB CCC AAA BBB CCC"
        let result = QuoteRecovery.findQuote(
            quote: "BBB",
            contextBefore: "CCC AAA ",
            contextAfter: " CCC",
            in: text
        )
        #expect(result != nil)
        #expect(result?.confidence == .contextMatch)
    }

    // MARK: - Case-insensitive fallback

    @Test func caseInsensitiveFallbackReturnsFuzzy() throws {
        let text = "The Quick Brown Fox"
        let result = QuoteRecovery.findQuote(
            quote: "quick brown fox",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        let r = try #require(result)
        #expect(r.confidence == .fuzzy)
        #expect(String(text[r.matchRange]) == "Quick Brown Fox")
    }

    // MARK: - Whitespace normalization fallback

    @Test func whitespaceNormalizationFallbackReturnsFuzzy() {
        let text = "hello   world"
        let result = QuoteRecovery.findQuote(
            quote: "hello world",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        #expect(result?.confidence == .fuzzy)
    }

    @Test func whitespaceNormalizationWithNewlines() {
        let text = "hello\n\nworld"
        let result = QuoteRecovery.findQuote(
            quote: "hello world",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        #expect(result?.confidence == .fuzzy)
    }

    // MARK: - Empty quote returns nil

    @Test func emptyQuoteReturnsNil() {
        let text = "Some text here"
        let result = QuoteRecovery.findQuote(
            quote: "",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result == nil)
    }

    // MARK: - Quote not found returns nil

    @Test func quoteNotFoundReturnsNil() {
        let text = "The quick brown fox"
        let result = QuoteRecovery.findQuote(
            quote: "lazy dog",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result == nil)
    }

    @Test func noMatchEvenWithNormalizationReturnsNil() {
        let text = "completely different content"
        let result = QuoteRecovery.findQuote(
            quote: "nothing matches",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result == nil)
    }

    // MARK: - Quote at start of text

    @Test func quoteAtStartOfTextNoContextBefore() {
        let text = "Hello world, how are you?"
        let result = QuoteRecovery.findQuote(
            quote: "Hello",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        #expect(result?.utf16Offset == 0)
        #expect(result?.confidence == .exact)
    }

    @Test func quoteAtStartWithContextBeforeStillMatches() {
        // contextBefore won't match anything at position 0, but the quote is unique
        let text = "Hello world"
        let result = QuoteRecovery.findQuote(
            quote: "Hello",
            contextBefore: "nonexistent",
            contextAfter: nil,
            in: text
        )
        // Should still find it as exact (unique match, context is best-effort)
        #expect(result != nil)
        #expect(result?.confidence == .exact)
    }

    // MARK: - Quote at end of text

    @Test func quoteAtEndOfText() {
        let text = "The lazy dog"
        let result = QuoteRecovery.findQuote(
            quote: "lazy dog",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        #expect(result?.confidence == .exact)
        #expect(result.map { String(text[$0.matchRange]) } == "lazy dog")
    }

    // MARK: - Unicode / CJK text matching

    @Test func cjkTextExactMatch() {
        let text = "今天天气真好，我们去散步吧。"
        let result = QuoteRecovery.findQuote(
            quote: "天气真好",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        #expect(result?.confidence == .exact)
        #expect(result.map { String(text[$0.matchRange]) } == "天气真好")
    }

    @Test func cjkTextUTF16Offset() {
        let text = "你好世界"
        let result = QuoteRecovery.findQuote(
            quote: "世界",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        // "你好" is 2 CJK chars, each 1 UTF-16 code unit = offset 2
        #expect(result?.utf16Offset == 2)
    }

    @Test func mixedASCIIAndCJK() {
        let text = "Hello 你好 World"
        let result = QuoteRecovery.findQuote(
            quote: "你好",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        #expect(result?.confidence == .exact)
        // "Hello " = 6 UTF-16 code units
        #expect(result?.utf16Offset == 6)
    }

    // MARK: - Emoji / surrogate pair matching

    @Test func emojiExactMatch() {
        let text = "I love 🎉 coding"
        let result = QuoteRecovery.findQuote(
            quote: "🎉 coding",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        #expect(result?.confidence == .exact)
    }

    @Test func emojiUTF16OffsetWithSurrogatePairs() {
        let text = "🎉🎊hello"
        let result = QuoteRecovery.findQuote(
            quote: "hello",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        // 🎉 = 2 UTF-16 code units, 🎊 = 2 UTF-16 code units = offset 4
        #expect(result?.utf16Offset == 4)
    }

    @Test func compositeEmojiMatch() {
        let text = "family: 👨‍👩‍👧‍👦 end"
        let result = QuoteRecovery.findQuote(
            quote: "👨‍👩‍👧‍👦 end",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        #expect(result?.confidence == .exact)
    }

    // MARK: - UTF-16 offset correctness

    @Test func utf16OffsetForPureASCII() {
        let text = "abcdef"
        let result = QuoteRecovery.findQuote(
            quote: "def",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result?.utf16Offset == 3)
    }

    @Test func utf16OffsetAfterMultibyteChars() {
        // é is 1 UTF-16 code unit but 2 UTF-8 bytes
        let text = "café latte"
        let result = QuoteRecovery.findQuote(
            quote: "latte",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        // "café " = 5 UTF-16 code units (c=1, a=1, f=1, é=1, space=1)
        #expect(result?.utf16Offset == 5)
    }

    // MARK: - Confidence levels

    @Test func confidenceIsExactForUniqueMatch() {
        let result = QuoteRecovery.findQuote(
            quote: "unique phrase xyz",
            contextBefore: nil,
            contextAfter: nil,
            in: "This has a unique phrase xyz in it."
        )
        #expect(result?.confidence == .exact)
    }

    @Test func confidenceIsContextMatchForDisambiguated() {
        let text = "the cat the cat the cat"
        let result = QuoteRecovery.findQuote(
            quote: "the cat",
            contextBefore: "cat ",
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        #expect(result?.confidence == .contextMatch)
    }

    @Test func confidenceIsFuzzyForCaseInsensitive() {
        let result = QuoteRecovery.findQuote(
            quote: "HELLO",
            contextBefore: nil,
            contextAfter: nil,
            in: "hello world"
        )
        #expect(result?.confidence == .fuzzy)
    }

    @Test func confidenceIsFuzzyForWhitespaceNormalized() {
        let result = QuoteRecovery.findQuote(
            quote: "a b",
            contextBefore: nil,
            contextAfter: nil,
            in: "a    b"
        )
        #expect(result?.confidence == .fuzzy)
    }

    // MARK: - Edge cases

    @Test func emptyTextReturnsNil() {
        let result = QuoteRecovery.findQuote(
            quote: "something",
            contextBefore: nil,
            contextAfter: nil,
            in: ""
        )
        #expect(result == nil)
    }

    @Test func quoteEqualsEntireText() {
        let text = "entire text"
        let result = QuoteRecovery.findQuote(
            quote: "entire text",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        #expect(result?.confidence == .exact)
        #expect(result?.utf16Offset == 0)
    }

    @Test func singleCharacterQuote() {
        let text = "abcabc"
        let result = QuoteRecovery.findQuote(
            quote: "a",
            contextBefore: nil,
            contextAfter: "bc",
            in: text
        )
        #expect(result != nil)
        // Both "a" occurrences have "bc" after them, so first match wins
    }

    @Test func contextMatchPrefersFirstWhenTied() {
        // When context can't disambiguate, prefer first match
        let text = "xx yy xx yy"
        let result = QuoteRecovery.findQuote(
            quote: "xx",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        // Multiple matches, no context -> just pick first, still contextMatch since ambiguous
        // Actually with no context it should still return, but can't be "exact" if not unique
        #expect(result?.utf16Offset == 0)
    }

    @Test func caseInsensitiveWithCJKUnchanged() {
        // CJK doesn't have case, so case-insensitive should still match
        let text = "你好世界"
        let result = QuoteRecovery.findQuote(
            quote: "你好世界",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        #expect(result != nil)
        #expect(result?.confidence == .exact)
    }

    // MARK: - Whitespace normalized disambiguation with context (Issue #11)

    @Test func whitespaceNormalizedAmbiguousMatchesDisambiguatedByContext() throws {
        // Quote has normalized spacing; text has irregular spacing — forces whitespace-normalized path
        let text = "apple  banana  cherry. grape  banana  cherry."
        let result = QuoteRecovery.findQuote(
            quote: "banana cherry",
            contextBefore: "grape  ",
            contextAfter: ".",
            in: text
        )
        let r = try #require(result)
        #expect(r.confidence == .fuzzy)
        // Should find the second occurrence near "grape"
        #expect(r.utf16Offset > 20)
    }

    // MARK: - Confidence assertion for ambiguous matches (Issue #12)

    @Test func ambiguousMatchWithNoContextReturnsContextMatch() throws {
        let text = "the cat the cat"
        let result = QuoteRecovery.findQuote(
            quote: "the cat",
            contextBefore: nil,
            contextAfter: nil,
            in: text
        )
        let r = try #require(result)
        // Multiple exact matches with no context: returns contextMatch (first-match fallback)
        #expect(r.confidence == .contextMatch)
    }
}
