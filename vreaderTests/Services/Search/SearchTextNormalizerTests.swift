// Purpose: Unit tests for SearchTextNormalizer — NFKC, case folding, diacritic folding,
// full-width/half-width conversion.

import Testing
import Foundation
@testable import vreader

@Suite("SearchTextNormalizer")
struct SearchTextNormalizerTests {

    // MARK: - Unicode NFKC normalization

    @Test func nfkcNormalizesCompatibilityCharacters() {
        // ﬁ (U+FB01) should decompose to "fi"
        let result = SearchTextNormalizer.normalize("ﬁnance")
        #expect(result == "finance")
    }

    @Test func nfkcNormalizesCircledLetters() {
        // ① (U+2460) NFKC decomposes; exact output is platform-dependent
        let result = SearchTextNormalizer.normalize("①②③")
        // Must contain "1", "2", "3" in order (platform may or may not include periods)
        #expect(result == "123" || result == "1.2.3.",
                "Expected NFKC decomposition of circled numbers, got: \(result)")
    }

    // MARK: - Case folding

    @Test func caseFolding() {
        let result = SearchTextNormalizer.normalize("Hello WORLD")
        #expect(result == "hello world")
    }

    @Test func caseFoldingGerman() {
        // ß should remain ß (lowercase) or fold to ss
        let result = SearchTextNormalizer.normalize("Straße")
        #expect(result == "strasse" || result == "straße")
    }

    @Test func caseFoldingTurkish() {
        let result = SearchTextNormalizer.normalize("İSTANBUL")
        #expect(result.lowercased() == result)
    }

    // MARK: - Diacritic folding

    @Test func diacriticFolding() {
        let result = SearchTextNormalizer.normalize("café résumé naïve")
        #expect(result == "cafe resume naive")
    }

    @Test func diacriticFoldingAccentedVowels() {
        // à á â ã ä å (6) è é ê ë (4) ì í î ï (4) ò ó ô õ ö (5) ù ú û ü (4)
        let result = SearchTextNormalizer.normalize("àáâãäåèéêëìíîïòóôõöùúûü")
        #expect(result == "aaaaaaeeeeiiiiooooouuuu")
    }

    @Test func diacriticFoldingCombiningCharacters() {
        // e + combining acute accent
        let result = SearchTextNormalizer.normalize("caf\u{0065}\u{0301}")
        #expect(result == "cafe")
    }

    // MARK: - Full-width to half-width folding

    @Test func fullWidthToHalfWidthLatinLetters() {
        // Ａ Ｂ Ｃ → A B C (then case-folded to a b c)
        let result = SearchTextNormalizer.normalize("ＡＢＣ")
        #expect(result == "abc")
    }

    @Test func fullWidthToHalfWidthDigits() {
        // ０１２３ → 0123
        let result = SearchTextNormalizer.normalize("０１２３")
        #expect(result == "0123")
    }

    @Test func fullWidthToHalfWidthKatakana() {
        // Full-width katakana should NOT be converted (only ASCII range)
        // This test ensures CJK characters are preserved
        let result = SearchTextNormalizer.normalize("東京")
        #expect(result == "東京" || result == "东京")
    }

    // MARK: - CJK handling

    @Test func cjkPreserved() {
        let result = SearchTextNormalizer.normalize("你好世界")
        #expect(result == "你好世界")
    }

    @Test func cjkMixedWithLatin() {
        let result = SearchTextNormalizer.normalize("Hello你好World")
        #expect(result == "hello你好world")
    }

    // MARK: - Edge cases

    @Test func emptyString() {
        let result = SearchTextNormalizer.normalize("")
        #expect(result == "")
    }

    @Test func whitespaceOnly() {
        let result = SearchTextNormalizer.normalize("   ")
        #expect(result == "   ")
    }

    @Test func emojiPreserved() {
        let result = SearchTextNormalizer.normalize("Hello 😀 World")
        #expect(result == "hello 😀 world")
    }

    @Test func newlinesPreserved() {
        let result = SearchTextNormalizer.normalize("Hello\nWorld")
        #expect(result == "hello\nworld")
    }

    @Test func mixedNormalization() {
        // Full-width + diacritics + case
        let result = SearchTextNormalizer.normalize("ＣＡＦÉ")
        #expect(result == "cafe")
    }

    // MARK: - CJK Segmentation

    @Test func segmentCJKSeparatesCharacters() {
        let result = SearchTextNormalizer.segmentCJK("你好世界")
        #expect(result == "你 好 世 界")
    }

    @Test func segmentCJKMixedWithLatin() {
        let result = SearchTextNormalizer.segmentCJK("Hello你好World")
        #expect(result == "Hello 你 好 World")
    }

    @Test func segmentCJKPreservesExistingSpaces() {
        let result = SearchTextNormalizer.segmentCJK("你好 世界")
        #expect(result == "你 好 世 界")
    }

    @Test func segmentCJKEmpty() {
        let result = SearchTextNormalizer.segmentCJK("")
        #expect(result == "")
    }

    @Test func segmentCJKPureLatin() {
        let result = SearchTextNormalizer.segmentCJK("Hello World")
        #expect(result == "Hello World")
    }

    @Test func segmentCJKJapaneseHiragana() {
        let result = SearchTextNormalizer.segmentCJK("こんにちは")
        #expect(result == "こ ん に ち は")
    }

    @Test func segmentCJKWithPunctuation() {
        let result = SearchTextNormalizer.segmentCJK("你好，世界！")
        // Punctuation stays between CJK chars
        #expect(result.contains("你"))
        #expect(result.contains("世"))
    }

    @Test func isCJKCharacterDetectsIdeographs() {
        #expect(SearchTextNormalizer.isCJKCharacter("你"))
        #expect(SearchTextNormalizer.isCJKCharacter("好"))
        #expect(SearchTextNormalizer.isCJKCharacter("こ"))  // Hiragana
        #expect(SearchTextNormalizer.isCJKCharacter("ア"))  // Katakana
        #expect(!SearchTextNormalizer.isCJKCharacter("A"))
        #expect(!SearchTextNormalizer.isCJKCharacter("1"))
        #expect(!SearchTextNormalizer.isCJKCharacter(" "))
    }

    // MARK: - CJK segmentation edge cases (bug fix coverage)

    @Test func segmentCJKKoreanHangul() {
        let result = SearchTextNormalizer.segmentCJK("안녕하세요")
        #expect(result == "안 녕 하 세 요", "Korean Hangul syllables should be space-separated")
    }

    @Test func segmentCJKIdempotent() {
        let original = "你好世界"
        let firstPass = SearchTextNormalizer.segmentCJK(original)
        #expect(firstPass == "你 好 世 界")
        let secondPass = SearchTextNormalizer.segmentCJK(firstPass)
        // Already-segmented text should not gain extra spaces
        #expect(secondPass == "你 好 世 界", "Running segmentCJK twice should not add extra spaces")
    }

    @Test func segmentCJKNumbersBetweenCJK() {
        let result = SearchTextNormalizer.segmentCJK("第1章")
        // "第" is CJK, "1" is not, "章" is CJK — transitions should insert spaces
        #expect(result.contains("第"), "Should contain '第'")
        #expect(result.contains("1"), "Should contain '1'")
        #expect(result.contains("章"), "Should contain '章'")
        // The three items should be space-separated
        #expect(result == "第 1 章", "CJK-number-CJK should be fully separated: got '\(result)'")
    }
}
