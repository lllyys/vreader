// Purpose: Feature #68 WI-2 — tests for
// TXTReaderViewModel.headingLineLength, the pure derivation that drives
// buildChapterStart's `headingLineLength` argument.
//
// @coordinates-with: TXTReaderViewModel.swift

import Testing
import Foundation
@testable import vreader

@Suite("TXTReaderViewModel — chapter heading line length (feature #68 WI-2)")
struct TXTReaderViewModelChapterHeadingTests {

    @Test("regex chapter — first line equals the title → returns first-line UTF-16 length")
    func regexChapterReturnsFirstLineLength() {
        let title = "Chapter One"
        let text = "\(title)\nIt was a bright cold day in April."
        let result = TXTReaderViewModel.headingLineLength(
            chapterText: text, chapterTitle: title
        )
        #expect(result == (title as NSString).length)
    }

    @Test("synthetic chapter — title 'Chapter 3', body is prose → returns 0")
    func syntheticChapterReturnsZero() {
        let result = TXTReaderViewModel.headingLineLength(
            chapterText: "It was a bright cold day in April, and the clocks struck.",
            chapterTitle: "Chapter 3"
        )
        #expect(result == 0)
    }

    @Test("'前言' chapter — title is 前言, body first line is opening prose → returns 0")
    func qianyanChapterReturnsZero() {
        let result = TXTReaderViewModel.headingLineLength(
            chapterText: "这本书讲述了一个关于时间的故事。\n第一段正文。",
            chapterTitle: "前言"
        )
        #expect(result == 0)
    }

    @Test("CJK regex chapter — first line equals a 第一章-style title")
    func cjkRegexChapterMatches() {
        let title = "第一章 风起"
        let text = "\(title)\n小说正文从这里开始。"
        let result = TXTReaderViewModel.headingLineLength(
            chapterText: text, chapterTitle: title
        )
        #expect(result == (title as NSString).length)
    }

    @Test("first line trimmed equals trimmed title despite surrounding whitespace")
    func trimmedMatchStillCounts() {
        let title = "  Chapter Two  "
        let text = "Chapter Two\nBody text here."
        let result = TXTReaderViewModel.headingLineLength(
            chapterText: text, chapterTitle: title
        )
        // The returned length is the FIRST LINE length (untrimmed line),
        // which is "Chapter Two" = 11.
        #expect(result == ("Chapter Two" as NSString).length)
    }

    @Test("first line almost equals title but differs by trailing punctuation → returns 0")
    func nearMissReturnsZero() {
        // Audit-driven: a false-positive heading restyle must not happen.
        let result = TXTReaderViewModel.headingLineLength(
            chapterText: "Chapter One.\nBody text here.",
            chapterTitle: "Chapter One"
        )
        #expect(result == 0)
    }

    @Test("nil chapter text → returns 0")
    func nilTextReturnsZero() {
        #expect(TXTReaderViewModel.headingLineLength(
            chapterText: nil, chapterTitle: "Chapter One"
        ) == 0)
    }

    @Test("nil chapter title → returns 0")
    func nilTitleReturnsZero() {
        #expect(TXTReaderViewModel.headingLineLength(
            chapterText: "Some body text.", chapterTitle: nil
        ) == 0)
    }

    @Test("empty chapter text → returns 0")
    func emptyTextReturnsZero() {
        #expect(TXTReaderViewModel.headingLineLength(
            chapterText: "", chapterTitle: "Chapter One"
        ) == 0)
    }

    @Test("single-line chapter text with no newline that equals the title")
    func singleLineEqualsTitle() {
        let title = "Chapter One"
        let result = TXTReaderViewModel.headingLineLength(
            chapterText: title, chapterTitle: title
        )
        #expect(result == (title as NSString).length)
    }

    @Test("chapter text begins with a blank line → returns 0")
    func leadingBlankLineReturnsZero() {
        let result = TXTReaderViewModel.headingLineLength(
            chapterText: "\nChapter One\nBody.", chapterTitle: "Chapter One"
        )
        #expect(result == 0)
    }

    @Test("all-whitespace title → returns 0")
    func whitespaceTitleReturnsZero() {
        #expect(TXTReaderViewModel.headingLineLength(
            chapterText: "   \nBody text.", chapterTitle: "   "
        ) == 0)
    }
}
