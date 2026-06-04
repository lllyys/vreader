// Purpose: Tests for NativeTextPaginator — TextKit 1 based paged layout engine.
// Validates pagination correctness, CJK handling, determinism, offset mapping,
// attributed string support, and recalculation on parameter changes.
//
// Key decisions:
// - Uses real UIFont (not mocked) because accurate text measurement is required.
// - @MainActor tests because TextKit layout managers require main thread.
// - Mirrors TextKit2PaginatorTests structure for consistency.
//
// @coordinates-with: NativeTextPaginator.swift

import Testing
import UIKit
@testable import vreader

@Suite("NativeTextPaginator")
@MainActor
struct NativeTextPaginatorTests {

    // MARK: - Helpers

    private let defaultFont = UIFont.systemFont(ofSize: 17)
    /// A viewport that resembles an iPhone screen in portrait (logical points).
    private let phoneViewport = CGSize(width: 375, height: 667)

    /// Generates a long string by repeating a line.
    private func generateLongText(
        lineCount: Int,
        lineContent: String = "This is a line of text for pagination testing."
    ) -> String {
        (0..<lineCount).map { _ in lineContent }.joined(separator: "\n")
    }

    /// Generates CJK text of approximately the given character count.
    private func generateCJKText(charCount: Int) -> String {
        let base = "这是一段用于测试分页引擎的中文文本。每一行都包含足够多的汉字来填充页面宽度。"
        var result = ""
        while result.count < charCount {
            result += base + "\n"
        }
        return String(result.prefix(charCount))
    }

    /// Builds a simple attributed string with the given font.
    private func makeAttributedString(
        _ text: String,
        font: UIFont? = nil
    ) -> NSAttributedString {
        let f = font ?? defaultFont
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        return NSAttributedString(
            string: text,
            attributes: [.font: f, .paragraphStyle: style]
        )
    }

    // MARK: - Basic Pagination (plain text)

    @Test func paginate_singlePageText_returns1Page() {
        let paginator = NativeTextPaginator()
        let pages = paginator.paginate(
            text: "Hello, world!",
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count == 1)
        #expect(paginator.totalPages == 1)
        #expect(pages[0].pageIndex == 0)
        #expect(pages[0].charRange.location == 0)
    }

    @Test func paginate_multiPageText_returnsMultiplePages() {
        let paginator = NativeTextPaginator()
        // 500 lines should definitely overflow a single phone viewport
        let longText = generateLongText(lineCount: 500)
        let pages = paginator.paginate(
            text: longText,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count > 1, "500 lines of text must span more than 1 page")
        #expect(paginator.totalPages == pages.count)
        // Pages should be numbered sequentially
        for (i, page) in pages.enumerated() {
            #expect(page.pageIndex == i, "Page \(i) should have pageIndex \(i)")
        }
    }

    @Test func paginate_emptyText_returns0Pages() {
        let paginator = NativeTextPaginator()
        let pages = paginator.paginate(
            text: "",
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.isEmpty)
        #expect(paginator.totalPages == 0)
    }

    // MARK: - CJK Handling

    @Test func paginate_cjkText_correctBoundaries() {
        let paginator = NativeTextPaginator()
        let cjkText = generateCJKText(charCount: 5000)
        let pages = paginator.paginate(
            text: cjkText,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count > 1, "5000 CJK characters should span multiple pages")

        // Verify no page range splits a surrogate pair
        let nsString = cjkText as NSString
        for page in pages {
            let range = page.charRange
            // Extracting substring should not crash (would crash on split surrogates)
            let extracted = nsString.substring(with: range)
            #expect(!extracted.isEmpty || range.length == 0,
                    "Page \(page.pageIndex) extracted text should not be empty for non-zero range")
        }
    }

    @Test func paginate_mixedCJKLatin_noOrphanedText() {
        let paginator = NativeTextPaginator()
        var mixedLines: [String] = []
        for i in 0..<200 {
            if i % 2 == 0 {
                mixedLines.append("English paragraph number \(i) with some words.")
            } else {
                mixedLines.append("第\(i)段中文文本，包含一些汉字和标点符号。")
            }
        }
        let mixedText = mixedLines.joined(separator: "\n")
        let pages = paginator.paginate(
            text: mixedText,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count > 1, "200 mixed lines should span multiple pages")

        // All text should be covered (contiguous ranges)
        let nsString = mixedText as NSString
        let totalCovered = pages.reduce(0) { $0 + $1.charRange.length }
        #expect(totalCovered == nsString.length,
                "Total covered length (\(totalCovered)) must equal text length (\(nsString.length))")
    }

    // MARK: - Page Lookup

    @Test func pageAtIndex_returnsCorrectCharRange() {
        let paginator = NativeTextPaginator()
        let longText = generateLongText(lineCount: 300)
        let pages = paginator.paginate(
            text: longText,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count >= 3, "Need at least 3 pages for this test")

        // Page 2 (0-indexed) should have valid range
        let page2 = pages[2]
        #expect(page2.charRange.length > 0, "Page 2 should have non-zero length")
        #expect(page2.charRange.location >= 0)

        // Range should be within bounds
        let nsString = longText as NSString
        #expect(page2.charRange.location + page2.charRange.length <= nsString.length,
                "Page range must not exceed text length")
    }

    @Test func offsetToPage_returnsCorrectPage() {
        let paginator = NativeTextPaginator()
        let longText = generateLongText(lineCount: 300)
        let pages = paginator.paginate(
            text: longText,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count >= 2)

        // Offset 0 should be on page 0
        let page0 = paginator.pageContaining(offsetUTF16: 0)
        #expect(page0 == 0, "Offset 0 should be on page 0")

        // An offset in the middle of page 1 should return page 1
        if pages.count >= 2 {
            let midPage1 = pages[1].charRange.location + pages[1].charRange.length / 2
            let foundPage = paginator.pageContaining(offsetUTF16: midPage1)
            #expect(foundPage == 1, "Mid-page-1 offset should map to page 1")
        }

        // Offset past end should return nil
        let pastEnd = paginator.pageContaining(offsetUTF16: (longText as NSString).length + 1)
        #expect(pastEnd == nil, "Offset past end should return nil")

        // Negative offset should return nil
        let negative = paginator.pageContaining(offsetUTF16: -1)
        #expect(negative == nil, "Negative offset should return nil")
    }

    // MARK: - Recalculation on Parameter Change

    @Test func viewportChange_recalculatesPages() {
        let text = generateLongText(lineCount: 200)
        let paginator = NativeTextPaginator()

        let pagesLarge = paginator.paginate(
            text: text,
            font: defaultFont,
            viewportSize: CGSize(width: 375, height: 800)
        )
        let pagesSmall = paginator.paginate(
            text: text,
            font: defaultFont,
            viewportSize: CGSize(width: 375, height: 400)
        )

        #expect(pagesSmall.count > pagesLarge.count,
                "Smaller viewport should produce more pages (\(pagesSmall.count) vs \(pagesLarge.count))")
    }

    @Test func fontChange_recalculatesPages() {
        let text = generateLongText(lineCount: 200)
        let paginator = NativeTextPaginator()

        let pagesSmallFont = paginator.paginate(
            text: text,
            font: UIFont.systemFont(ofSize: 14),
            viewportSize: phoneViewport
        )
        let pagesLargeFont = paginator.paginate(
            text: text,
            font: UIFont.systemFont(ofSize: 24),
            viewportSize: phoneViewport
        )

        #expect(pagesLargeFont.count > pagesSmallFont.count,
                "Larger font should produce more pages (\(pagesLargeFont.count) vs \(pagesSmallFont.count))")
    }

    // MARK: - Determinism

    @Test func deterministic_sameInputSameOutput() {
        let text = generateLongText(lineCount: 100)
        let font = UIFont.systemFont(ofSize: 17)
        let viewport = CGSize(width: 375, height: 667)

        let paginator1 = NativeTextPaginator()
        let pages1 = paginator1.paginate(text: text, font: font, viewportSize: viewport)

        let paginator2 = NativeTextPaginator()
        let pages2 = paginator2.paginate(text: text, font: font, viewportSize: viewport)

        #expect(pages1.count == pages2.count, "Same input must produce same page count")
        for i in 0..<pages1.count {
            #expect(pages1[i].charRange == pages2[i].charRange,
                    "Page \(i) range must be identical across runs")
        }
    }

    // MARK: - Text Coverage (no gaps, no overlaps)

    @Test func allPages_coverEntireText_noGapsNoDuplicates() {
        let paginator = NativeTextPaginator()
        let text = generateLongText(lineCount: 150)
        let pages = paginator.paginate(
            text: text,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(!pages.isEmpty)

        // Ranges should be contiguous
        for i in 1..<pages.count {
            let prevEnd = pages[i - 1].charRange.location + pages[i - 1].charRange.length
            let currStart = pages[i].charRange.location
            #expect(currStart == prevEnd,
                    "Page \(i) should start where page \(i-1) ends: expected \(prevEnd), got \(currStart)")
        }

        // First page starts at 0
        #expect(pages.first!.charRange.location == 0)

        // Last page ends at text length
        let lastPage = pages.last!
        let lastEnd = lastPage.charRange.location + lastPage.charRange.length
        #expect(lastEnd == (text as NSString).length,
                "Last page should end at text length \((text as NSString).length), got \(lastEnd)")
    }

    // MARK: - Edge Cases

    @Test func paginate_singleCharacter_returns1Page() {
        let paginator = NativeTextPaginator()
        let pages = paginator.paginate(
            text: "A",
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count == 1)
        #expect(pages[0].charRange.length == 1)
    }

    @Test func paginate_onlyNewlines_handledGracefully() {
        let paginator = NativeTextPaginator()
        let text = String(repeating: "\n", count: 500)
        let pages = paginator.paginate(
            text: text,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        // Should not crash, and should produce at least 1 page
        #expect(pages.count >= 1, "500 newlines should produce at least 1 page")
        let totalLength = pages.reduce(0) { $0 + $1.charRange.length }
        #expect(totalLength == (text as NSString).length,
                "Total covered length must equal text length")
    }

    @Test func paginate_veryNarrowViewport_doesNotCrash() {
        let paginator = NativeTextPaginator()
        let text = "Hello, world! This is a test of very narrow viewport handling."
        let pages = paginator.paginate(
            text: text,
            font: defaultFont,
            viewportSize: CGSize(width: 50, height: 100)
        )
        #expect(pages.count >= 1)
    }

    @Test func paginate_zeroSizeViewport_returnsEmpty() {
        let paginator = NativeTextPaginator()
        let pages = paginator.paginate(
            text: "Hello",
            font: defaultFont,
            viewportSize: CGSize(width: 0, height: 0)
        )
        #expect(pages.isEmpty, "Zero-size viewport should produce 0 pages")
    }

    @Test func paginate_zeroWidthViewport_returnsEmpty() {
        let paginator = NativeTextPaginator()
        let pages = paginator.paginate(
            text: "Hello",
            font: defaultFont,
            viewportSize: CGSize(width: 0, height: 667)
        )
        #expect(pages.isEmpty, "Zero-width viewport should produce 0 pages")
    }

    @Test func paginate_zeroHeightViewport_returnsEmpty() {
        let paginator = NativeTextPaginator()
        let pages = paginator.paginate(
            text: "Hello",
            font: defaultFont,
            viewportSize: CGSize(width: 375, height: 0)
        )
        #expect(pages.isEmpty, "Zero-height viewport should produce 0 pages")
    }

    // MARK: - Attributed String Input

    @Test func paginateAttributed_singlePage_returns1Page() {
        let paginator = NativeTextPaginator()
        let attrText = makeAttributedString("Hello, world!")
        let pages = paginator.paginateAttributed(
            attributedText: attrText,
            viewportSize: phoneViewport
        )
        #expect(pages.count == 1)
        #expect(paginator.totalPages == 1)
    }

    @Test func paginateAttributed_multiPage_returnsMultiplePages() {
        let paginator = NativeTextPaginator()
        let longText = generateLongText(lineCount: 500)
        let attrText = makeAttributedString(longText)
        let pages = paginator.paginateAttributed(
            attributedText: attrText,
            viewportSize: phoneViewport
        )
        #expect(pages.count > 1, "500 lines attributed text must span more than 1 page")
    }

    @Test func paginateAttributed_emptyString_returns0Pages() {
        let paginator = NativeTextPaginator()
        let attrText = NSAttributedString(string: "")
        let pages = paginator.paginateAttributed(
            attributedText: attrText,
            viewportSize: phoneViewport
        )
        #expect(pages.isEmpty)
        #expect(paginator.totalPages == 0)
    }

    @Test func paginateAttributed_contiguousRanges() {
        let paginator = NativeTextPaginator()
        let text = generateLongText(lineCount: 150)
        let attrText = makeAttributedString(text)
        let pages = paginator.paginateAttributed(
            attributedText: attrText,
            viewportSize: phoneViewport
        )
        #expect(!pages.isEmpty)

        // Ranges should be contiguous
        for i in 1..<pages.count {
            let prevEnd = pages[i - 1].charRange.location + pages[i - 1].charRange.length
            let currStart = pages[i].charRange.location
            #expect(currStart == prevEnd,
                    "Page \(i) should start where page \(i-1) ends")
        }

        // First starts at 0, last ends at length
        #expect(pages.first!.charRange.location == 0)
        let lastEnd = pages.last!.charRange.location + pages.last!.charRange.length
        #expect(lastEnd == attrText.length)
    }

    // MARK: - Re-pagination (calling paginate again replaces results)

    @Test func repaginate_replacesOldResults() {
        let paginator = NativeTextPaginator()
        let text1 = generateLongText(lineCount: 100)
        _ = paginator.paginate(text: text1, font: defaultFont, viewportSize: phoneViewport)
        let count1 = paginator.totalPages

        let text2 = "Short"
        _ = paginator.paginate(text: text2, font: defaultFont, viewportSize: phoneViewport)
        let count2 = paginator.totalPages

        #expect(count2 < count1, "Re-pagination with shorter text should produce fewer pages")
        #expect(count2 == 1)
    }

    // MARK: - Offset at exact page boundary

    @Test func offsetToPage_atPageBoundary_returnsCorrectPage() {
        let paginator = NativeTextPaginator()
        let longText = generateLongText(lineCount: 300)
        let pages = paginator.paginate(
            text: longText,
            font: defaultFont,
            viewportSize: phoneViewport
        )
        #expect(pages.count >= 2)

        // The first character of page 1 should map to page 1
        let page1Start = pages[1].charRange.location
        let found = paginator.pageContaining(offsetUTF16: page1Start)
        #expect(found == 1, "First char of page 1 (offset \(page1Start)) should map to page 1")

        // The last character of page 0 should map to page 0
        let page0End = pages[0].charRange.location + pages[0].charRange.length - 1
        let found0 = paginator.pageContaining(offsetUTF16: page0End)
        #expect(found0 == 0, "Last char of page 0 (offset \(page0End)) should map to page 0")
    }

    // MARK: - Feature #92: justification does not drift page boundaries

    /// Justification adjusts intra-line spacing only; TextKit determines line
    /// breaks BEFORE alignment, so a `.justified` attributed string paginates
    /// to the SAME page boundaries (count + per-page char ranges) as the
    /// `.natural` equivalent. Pins the feature-#92 invariant that turning on
    /// justified alignment can't shift a saved position onto a different page.
    @Test func justificationDoesNotChangePageBoundaries() {
        let text = generateLongText(
            lineCount: 200,
            lineContent: "你好世界，这是一段用于测试分页边界的中文文本内容。"
        )

        func paginate(_ alignment: NSTextAlignment) -> [NativePageInfo] {
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            style.alignment = alignment
            let attr = NSAttributedString(
                string: text, attributes: [.font: defaultFont, .paragraphStyle: style]
            )
            return NativeTextPaginator().paginateAttributed(
                attributedText: attr, viewportSize: phoneViewport
            )
        }

        let natural = paginate(.natural)
        let justified = paginate(.justified)
        #expect(natural.count > 1, "fixture must span multiple pages")
        #expect(justified == natural, "justification must not move page boundaries")
    }
}
