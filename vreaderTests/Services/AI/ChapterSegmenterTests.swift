// Purpose: Tests for ChapterSegmenter — paragraph + CJK-aware sentence
// splitting for feature #56 bilingual reading.
//
// @coordinates-with: ChapterSegmenter.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-4)

import Testing
import Foundation
@testable import vreader

@Suite("ChapterTranslationPrefetcher granularity gate (Bug #344)")
struct PrefetcherGranularityGateTests {
    @Test func sentenceHonored_whenSupported() {
        #expect(ChapterTranslationPrefetcher.effectiveGranularity(
            requested: .sentence, supportsSentenceGranularity: true) == .sentence)
    }
    @Test func sentenceDegrades_whenUnsupported() {
        #expect(ChapterTranslationPrefetcher.effectiveGranularity(
            requested: .sentence, supportsSentenceGranularity: false) == .paragraph)
    }
    @Test func paragraphAlwaysParagraph() {
        #expect(ChapterTranslationPrefetcher.effectiveGranularity(
            requested: .paragraph, supportsSentenceGranularity: true) == .paragraph)
        #expect(ChapterTranslationPrefetcher.effectiveGranularity(
            requested: .paragraph, supportsSentenceGranularity: false) == .paragraph)
    }
}

@Suite("ChapterSegmenter")
struct ChapterSegmenterTests {

    // MARK: - Paragraphs

    @Test func paragraphs_emptyTextYieldsEmpty() {
        #expect(ChapterSegmenter.paragraphs(in: "").isEmpty)
    }

    @Test func paragraphs_whitespaceOnlyYieldsEmpty() {
        #expect(ChapterSegmenter.paragraphs(in: "   \n\n  \t ").isEmpty)
    }

    @Test func paragraphs_singleParagraph() {
        let result = ChapterSegmenter.paragraphs(in: "Just one paragraph here.")
        #expect(result == ["Just one paragraph here."])
    }

    @Test func paragraphs_blankLineSeparated() {
        let text = "First paragraph.\n\nSecond paragraph.\n\nThird."
        let result = ChapterSegmenter.paragraphs(in: text)
        #expect(result == ["First paragraph.", "Second paragraph.", "Third."])
    }

    @Test func paragraphs_collapsesMultipleBlankLines() {
        let text = "Alpha.\n\n\n\nBeta."
        let result = ChapterSegmenter.paragraphs(in: text)
        #expect(result == ["Alpha.", "Beta."])
    }

    @Test func paragraphs_trimsParagraphWhitespace() {
        let text = "  Leading and trailing.  \n\n  Another.  "
        let result = ChapterSegmenter.paragraphs(in: text)
        #expect(result == ["Leading and trailing.", "Another."])
    }

    @Test func paragraphs_cjkBlankLineSeparated() {
        let text = "第一段落。\n\n第二段落。"
        let result = ChapterSegmenter.paragraphs(in: text)
        #expect(result == ["第一段落。", "第二段落。"])
    }

    @Test func paragraphs_singleNewlineWithinParagraphIsNotABreak() {
        // A soft line wrap (single \n) keeps the paragraph together;
        // only a blank line separates paragraphs.
        let text = "Line one\nstill same paragraph.\n\nNew paragraph."
        let result = ChapterSegmenter.paragraphs(in: text)
        #expect(result.count == 2)
        #expect(result[1] == "New paragraph.")
    }

    // MARK: - Sentences

    @Test func sentences_emptyTextYieldsEmpty() {
        #expect(ChapterSegmenter.sentences(in: "").isEmpty)
    }

    @Test func sentences_latinSplit() {
        let text = "First sentence. Second sentence! Third one?"
        let result = ChapterSegmenter.sentences(in: text)
        #expect(result.count == 3)
        #expect(result[0].contains("First sentence"))
        #expect(result[1].contains("Second sentence"))
        #expect(result[2].contains("Third one"))
    }

    @Test func sentences_cjkSplit() {
        // CJK uses fullwidth terminators 。！？ — enumerateSubstrings(.bySentences)
        // is locale-aware and handles them.
        let text = "第一句。第二句！第三句？"
        let result = ChapterSegmenter.sentences(in: text)
        #expect(result.count == 3)
        #expect(result[0].contains("第一句"))
        #expect(result[2].contains("第三句"))
    }

    @Test func sentences_mixedCJKAndLatin() {
        let text = "This is English. 这是中文。Back to English!"
        let result = ChapterSegmenter.sentences(in: text)
        #expect(result.count == 3)
    }

    @Test func sentences_noTerminalPunctuation() {
        // A run with no sentence terminator is still one segment.
        let text = "a sentence fragment with no period"
        let result = ChapterSegmenter.sentences(in: text)
        #expect(result.count == 1)
        #expect(result[0] == "a sentence fragment with no period")
    }

    @Test func sentences_trailingWhitespaceTrimmed() {
        let text = "Sentence one.   "
        let result = ChapterSegmenter.sentences(in: text)
        #expect(result == ["Sentence one."])
    }

    @Test func sentences_dropsEmptySegments() {
        let text = "Real sentence.\n\n\n"
        let result = ChapterSegmenter.sentences(in: text)
        #expect(result.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
    }
    // MARK: - Bug #344: sentenceRanges count-parity contract

    /// `sentenceRanges` and `sentences` MUST agree in count AND content for
    /// every input — the display interleave and the translation
    /// segmentation pair 1:1 only because both walk the same enumeration.
    @Test(arguments: [
        "First sentence. Second sentence! Third?",
        "One paragraph here.\n\nAnother paragraph. With two sentences.",
        "无可奈何花落去。似曾相识燕归来。小园香径独徘徊。",
        "Mixed CJK 句子。And English follows. 再来一句！",
        "a sentence fragment with no period",
        "Sentence one.   ",
        "Real sentence.\n\n\n",
        "",
        "   \n\t  ",
        "Quote: \u{201C}Stop.\u{201D} He left. 🙂 Emoji sentence.",
    ])
    func sentenceRanges_countAndContentParity(_ text: String) {
        let sentences = ChapterSegmenter.sentences(in: text)
        let ranges = ChapterSegmenter.sentenceRanges(in: text)
        #expect(ranges.count == sentences.count, "count parity is the 1:1 inject contract")
        let ns = text as NSString
        for (range, sentence) in zip(ranges, sentences) {
            let extracted = ns.substring(
                with: NSRange(location: range.lowerBound, length: range.upperBound - range.lowerBound))
            #expect(extracted == sentence, "trimmed range must extract exactly the trimmed sentence")
        }
    }

    // MARK: - Bug #344 Gate-4: unified blank-line definition

    /// The translation side (`paragraphs`) and the display side
    /// (`BilingualParagraphRanges.scan`) must COUNT identically for every
    /// input — including blank lines made of Unicode whitespace outside
    /// `[ \\t]` (U+3000 ideographic space, U+00A0 NBSP — common in CJK
    /// files). Pre-#344 the regex splitter missed those, so the display
    /// side counted MORE paragraphs and painted source-only.
    @Test(arguments: [
        "para one\nstill one\n\npara two",
        "第一段。\n\u{3000}\n第二段。",
        "first\n\u{00A0}\nsecond",
        "one\r\n\r\ntwo\r\nstill two",
        "single paragraph only",
        "",
        "\n\n\n",
        "lead\n \t \ntrail",
    ])
    func paragraphs_countParityWithDisplayScanner(_ text: String) {
        let paragraphs = ChapterSegmenter.paragraphs(in: text)
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        #expect(paragraphs.count == ranges.count,
                "translation-side and display-side paragraph counts must agree")
    }

    @Test func paragraphs_ideographicSpaceBlankLine_splits() {
        let text = "第一段。\n\u{3000}\n第二段。"
        #expect(ChapterSegmenter.paragraphs(in: text) == ["第一段。", "第二段。"])
    }

    @Test func paragraphs_softWrapLineEndings_normalizeToLF() {
        // Gate-4 round 2: the pre-#344 contract — CRLF/CR soft wraps inside
        // a paragraph normalize to \n in the returned text.
        #expect(ChapterSegmenter.paragraphs(in: "a\r\nb") == ["a\nb"])
        #expect(ChapterSegmenter.paragraphs(in: "a\rb\r\n\r\nc") == ["a\nb", "c"])
    }

        @Test func sentenceRanges_areOrderedAndNonOverlapping() {
        let text = "One. Two. Three. 四。五！"
        let ranges = ChapterSegmenter.sentenceRanges(in: text)
        #expect(ranges.count >= 4)
        for pair in zip(ranges, ranges.dropFirst()) {
            #expect(pair.0.upperBound <= pair.1.lowerBound)
        }
    }
}
