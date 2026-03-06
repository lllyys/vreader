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
        // ① (U+2460) normalizes to "1"
        let result = SearchTextNormalizer.normalize("①②③")
        #expect(result == "1.2.3." || result == "123" || result.contains("1"))
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
}
