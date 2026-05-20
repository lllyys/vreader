// Purpose: Tests for ChapterSegmenter — paragraph + CJK-aware sentence
// splitting for feature #56 bilingual reading.
//
// @coordinates-with: ChapterSegmenter.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-4)

import Testing
import Foundation
@testable import vreader

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
}
