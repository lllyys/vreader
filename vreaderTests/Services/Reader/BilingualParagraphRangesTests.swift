// Purpose: Feature #56 WI-12b — pin the TXT/MD paragraph-range scanner that
// feeds `BilingualTextRenderer.render(...)`. Pure UTF-16 offset arithmetic —
// no I/O, no async. Empty / single-paragraph / blank-line-separated / CJK /
// trailing-whitespace / mixed-newline edge cases all stay byte-identical.
//
// @coordinates-with: BilingualParagraphRanges.swift,
//   BilingualTextRenderer.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-12b)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #56 WI-12b — BilingualParagraphRanges")
struct BilingualParagraphRangesTests {

    @Test("empty text returns no ranges")
    func emptyText() {
        let ranges = BilingualParagraphRanges.scan(sourceText: "")
        #expect(ranges.isEmpty)
    }

    @Test("single paragraph returns one range covering the whole text")
    func singleParagraph() {
        let text = "Hello world"
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        #expect(ranges == [0..<11])
    }

    @Test("two lines separated by single newline fuse into one paragraph")
    func twoLinesSingleNewlineFuse() {
        // A single-newline-separated pair is one paragraph (line wrap) —
        // a blank line is required to split paragraphs. The fused
        // paragraph range covers the whole text (single \n included).
        let text = "First\nSecond"
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        #expect(ranges == [0..<text.utf16.count])
    }

    @Test("two paragraphs separated by blank line yield two ranges")
    func twoParagraphsBlankLine() {
        let text = "First\n\nSecond"
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        #expect(ranges == [0..<5, 7..<13])
    }

    @Test("trailing blank line is not a paragraph")
    func trailingBlankLine() {
        let text = "First\n\n"
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        #expect(ranges == [0..<5])
    }

    @Test("leading blank lines are skipped")
    func leadingBlankLines() {
        let text = "\n\nFirst"
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        #expect(ranges == [2..<7])
    }

    @Test("blank-only lines between paragraphs preserve ordering")
    func interspersedBlankLines() {
        let text = "First\n\n\nSecond\n\nThird"
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        #expect(ranges == [0..<5, 8..<14, 16..<21])
    }

    @Test("CJK paragraph with full-width punctuation counts as one paragraph")
    func cjkParagraph() {
        let text = "你好世界。这是测试。"  // single paragraph despite full-stop chars
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        #expect(ranges == [0..<text.utf16.count])
    }

    @Test("CJK two paragraphs separated by blank line yield two ranges")
    func cjkTwoParagraphs() {
        let p1 = "你好世界"
        let p2 = "再见世界"
        let text = "\(p1)\n\n\(p2)"
        let p1Len = p1.utf16.count
        let p2Len = p2.utf16.count
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        let sepLen = 2  // "\n\n"
        #expect(ranges == [0..<p1Len, (p1Len + sepLen)..<(p1Len + sepLen + p2Len)])
    }

    @Test("paragraph with internal whitespace stays one paragraph")
    func internalWhitespace() {
        let text = "Hello   world   with   spaces"
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        #expect(ranges == [0..<text.utf16.count])
    }

    @Test("only-whitespace text yields no paragraphs")
    func onlyWhitespace() {
        let text = "\n\n\n   \n  \n"
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        #expect(ranges.isEmpty)
    }

    @Test("CRLF line endings handled like LF")
    func crlfLineEndings() {
        // CRLF — "First\r\n\r\nSecond" — the "\r\n\r\n" is the blank-line sep.
        let text = "First\r\n\r\nSecond"
        let ranges = BilingualParagraphRanges.scan(sourceText: text)
        // The two paragraphs are "First" (0..<5) and "Second" (9..<15).
        #expect(ranges == [0..<5, 9..<15])
    }
}
