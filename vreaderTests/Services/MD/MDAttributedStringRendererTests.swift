// Purpose: Golden normalization tests for MDAttributedStringRenderer.
// Each test pins the exact rendered text output to catch changes that would
// break offset stability.
//
// @coordinates-with: MDAttributedStringRenderer.swift, MDTypes.swift

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

@Suite("MDAttributedStringRenderer - Golden Text")
struct MDAttributedStringRendererGoldenTests {

    private var config: MDRenderConfig { .default }

    // MARK: - Paragraphs

    @Test("plain paragraph renders as text + newline")
    func plainParagraph() {
        let result = MDAttributedStringRenderer.render(text: "Hello world", config: config)
        #expect(result.renderedText == "Hello world\n")
    }

    @Test("multiple paragraphs separated by blank line")
    func multipleParagraphs() {
        let result = MDAttributedStringRenderer.render(text: "First.\n\nSecond.", config: config)
        #expect(result.renderedText == "First.\nSecond.\n")
    }

    // MARK: - Headings

    @Test("H1 renders as heading text + newline, no # characters")
    func h1Heading() {
        let result = MDAttributedStringRenderer.render(text: "# Title", config: config)
        #expect(result.renderedText == "Title\n")
        #expect(result.headings.count == 1)
        #expect(result.headings[0].level == 1)
        #expect(result.headings[0].text == "Title")
        #expect(result.title == "Title")
    }

    @Test("H2 through H6 render at decreasing sizes")
    func headingLevels() {
        let md = "## Sub\n### Sub-sub\n#### H4\n##### H5\n###### H6"
        let result = MDAttributedStringRenderer.render(text: md, config: config)
        #expect(result.headings.count == 5)
        #expect(result.headings[0].level == 2)
        #expect(result.headings[1].level == 3)
        #expect(result.headings[2].level == 4)
        #expect(result.headings[3].level == 5)
        #expect(result.headings[4].level == 6)
    }

    @Test("heading with tab after # parses correctly")
    func headingWithTab() {
        let result = MDAttributedStringRenderer.render(text: "#\tTab Title", config: config)
        #expect(result.renderedText == "Tab Title\n")
        #expect(result.headings.count == 1)
        #expect(result.headings[0].text == "Tab Title")
    }

    @Test("heading with trailing hashes strips them")
    func headingTrailingHashes() {
        let result = MDAttributedStringRenderer.render(text: "# Title ###", config: config)
        #expect(result.renderedText == "Title\n")
    }

    // MARK: - Bold/Italic

    @Test("bold renders as inner text without asterisks")
    func boldText() {
        let result = MDAttributedStringRenderer.render(text: "**bold**", config: config)
        #expect(result.renderedText == "bold\n")
    }

    @Test("italic renders as inner text without asterisks")
    func italicText() {
        let result = MDAttributedStringRenderer.render(text: "*italic*", config: config)
        #expect(result.renderedText == "italic\n")
    }

    @Test("bold+italic renders as inner text")
    func boldItalicText() {
        let result = MDAttributedStringRenderer.render(text: "***both***", config: config)
        #expect(result.renderedText == "both\n")
    }

    // MARK: - Code

    @Test("code span renders as code text without backticks")
    func codeSpan() {
        let result = MDAttributedStringRenderer.render(text: "`code`", config: config)
        #expect(result.renderedText == "code\n")
    }

    @Test("fenced code block renders content without fence markers")
    func fencedCodeBlock() {
        let md = "```\nline1\nline2\n```"
        let result = MDAttributedStringRenderer.render(text: md, config: config)
        #expect(result.renderedText == "line1\nline2\n")
    }

    @Test("fenced code block with language hint")
    func fencedCodeBlockWithLanguage() {
        let md = "```swift\nlet x = 1\n```"
        let result = MDAttributedStringRenderer.render(text: md, config: config)
        #expect(result.renderedText == "let x = 1\n")
    }

    // MARK: - Links

    @Test("link renders as link text without brackets/parens")
    func linkRendering() {
        let result = MDAttributedStringRenderer.render(text: "[text](https://x.com)", config: config)
        #expect(result.renderedText == "text\n")
    }

    #if canImport(UIKit)
    @Test("link has .link attribute with URL")
    func linkAttribute() {
        let result = MDAttributedStringRenderer.render(text: "[text](https://x.com)", config: config)
        let attrStr = result.renderedAttributedString
        var effectiveRange = NSRange()
        let attrs = attrStr.attributes(at: 0, effectiveRange: &effectiveRange)
        let linkURL = attrs[.link] as? URL
        #expect(linkURL?.absoluteString == "https://x.com")
    }
    #endif

    // MARK: - Lists

    @Test("unordered list item renders with bullet prefix")
    func unorderedListItem() {
        let result = MDAttributedStringRenderer.render(text: "- item", config: config)
        #expect(result.renderedText == "\u{2022} item\n")
    }

    @Test("ordered list item renders with number prefix")
    func orderedListItem() {
        let result = MDAttributedStringRenderer.render(text: "1. item", config: config)
        #expect(result.renderedText == "1. item\n")
    }

    @Test("nested unordered list has tab prefix")
    func nestedUnorderedList() {
        let md = "- top\n  - nested"
        let result = MDAttributedStringRenderer.render(text: md, config: config)
        // First item: no indent, second: one tab
        #expect(result.renderedText.contains("\t\u{2022} nested"))
    }

    // MARK: - Blockquotes

    @Test("blockquote renders without > character")
    func blockquote() {
        let result = MDAttributedStringRenderer.render(text: "> quote", config: config)
        #expect(result.renderedText == "quote\n")
        #expect(!result.renderedText.contains(">"))
    }

    // MARK: - Thematic Breaks

    @Test("thematic break (---) renders as newline")
    func thematicBreak() {
        let result = MDAttributedStringRenderer.render(text: "---", config: config)
        #expect(result.renderedText == "\n")
    }

    @Test("thematic break (***) renders as newline")
    func thematicBreakAsterisk() {
        let result = MDAttributedStringRenderer.render(text: "***", config: config)
        #expect(result.renderedText == "\n")
    }

    // MARK: - Empty Document

    @Test("empty document renders as empty string")
    func emptyDocument() {
        let result = MDAttributedStringRenderer.render(text: "", config: config)
        #expect(result.renderedText == "")
        #expect(result.renderedAttributedString.length == 0)
        #expect(result.headings.isEmpty)
        #expect(result.title == nil)
    }

    // MARK: - CJK

    @Test("CJK headings render correctly")
    func cjkHeading() {
        let result = MDAttributedStringRenderer.render(text: "# 中文标题", config: config)
        #expect(result.renderedText == "中文标题\n")
        #expect(result.title == "中文标题")
    }

    @Test("CJK body text renders correctly")
    func cjkBody() {
        let result = MDAttributedStringRenderer.render(text: "这是中文内容。", config: config)
        #expect(result.renderedText == "这是中文内容。\n")
    }

    // MARK: - Emoji

    @Test("emoji renders correctly with proper UTF-16 length")
    func emojiRendering() {
        let result = MDAttributedStringRenderer.render(text: "Hello 🌍", config: config)
        #expect(result.renderedText == "Hello 🌍\n")
        // "Hello " = 6 + 🌍 = 2 UTF-16 + "\n" = 1 = 9
        #expect(result.renderedTextLengthUTF16 == 9)
    }

    // MARK: - Complex Document

    @Test("mixed inline tokens preserve correct ordering")
    func mixedInlineTokenOrdering() {
        // bold before code before italic — earliest match should win
        let md = "a **bold** then `code` then *italic* end"
        let result = MDAttributedStringRenderer.render(text: md, config: config)
        let text = result.renderedText
        #expect(text == "a bold then code then italic end\n")
        // Verify no raw syntax leaked
        #expect(!text.contains("**"))
        #expect(!text.contains("`"))
    }

    @Test("adjacent inline tokens render correctly")
    func adjacentInlineTokens() {
        let md = "**bold***italic*`code`"
        let result = MDAttributedStringRenderer.render(text: md, config: config)
        let text = result.renderedText
        #expect(text.contains("bold"))
        #expect(text.contains("italic"))
        #expect(text.contains("code"))
        #expect(!text.contains("**"))
        #expect(!text.contains("`"))
    }

    @Test("link followed by bold renders both correctly")
    func linkThenBold() {
        let md = "[link](https://x.com) **bold**"
        let result = MDAttributedStringRenderer.render(text: md, config: config)
        let text = result.renderedText
        #expect(text == "link bold\n")
    }

    @Test("complex document with multiple elements")
    func complexDocument() {
        let md = """
        # Title

        This is a **bold** and *italic* paragraph.

        - List item 1
        - List item 2

        > A blockquote

        ---

        `code` here.
        """
        let result = MDAttributedStringRenderer.render(text: md, config: config)
        // Verify title was extracted
        #expect(result.title == "Title")
        // Verify headings
        #expect(result.headings.count == 1)
        // Verify no raw markdown syntax in rendered text
        #expect(!result.renderedText.contains("**"))
        #expect(!result.renderedText.contains("# "))
        #expect(!result.renderedText.contains("> "))
        #expect(!result.renderedText.contains("---"))
    }
}

// MARK: - Font Attribute Tests

#if canImport(UIKit)
@Suite("MDAttributedStringRenderer - Font Attributes")
struct MDAttributedStringRendererFontTests {

    private var config: MDRenderConfig { .default }

    @Test("H1 font size is 2x base")
    func h1FontSize() {
        let result = MDAttributedStringRenderer.render(text: "# Title", config: config)
        let attrStr = result.renderedAttributedString
        var range = NSRange()
        let attrs = attrStr.attributes(at: 0, effectiveRange: &range)
        let font = attrs[.font] as? UIFont
        #expect(font != nil)
        // H1 = 2.0x of 18 = 36
        #expect(font!.pointSize == config.fontSize * 2.0)
    }

    @Test("bold text has bold trait")
    func boldTrait() {
        let result = MDAttributedStringRenderer.render(text: "**bold**", config: config)
        let attrStr = result.renderedAttributedString
        var range = NSRange()
        let attrs = attrStr.attributes(at: 0, effectiveRange: &range)
        let font = attrs[.font] as? UIFont
        #expect(font != nil)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.traitBold))
    }

    @Test("italic text has italic trait")
    func italicTrait() {
        let result = MDAttributedStringRenderer.render(text: "*italic*", config: config)
        let attrStr = result.renderedAttributedString
        var range = NSRange()
        let attrs = attrStr.attributes(at: 0, effectiveRange: &range)
        let font = attrs[.font] as? UIFont
        #expect(font != nil)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.traitItalic))
    }

    @Test("code span has monospace font")
    func codeSpanMonospace() {
        let result = MDAttributedStringRenderer.render(text: "`code`", config: config)
        let attrStr = result.renderedAttributedString
        var range = NSRange()
        let attrs = attrStr.attributes(at: 0, effectiveRange: &range)
        let font = attrs[.font] as? UIFont
        #expect(font != nil)
        #expect(font!.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))
    }

    @Test("code block has background color")
    func codeBlockBackground() {
        let md = "```\ncode\n```"
        let result = MDAttributedStringRenderer.render(text: md, config: config)
        let attrStr = result.renderedAttributedString
        var range = NSRange()
        let attrs = attrStr.attributes(at: 0, effectiveRange: &range)
        let bg = attrs[.backgroundColor] as? UIColor
        #expect(bg != nil)
    }

    @Test("blockquote has secondary label color")
    func blockquoteColor() {
        let result = MDAttributedStringRenderer.render(text: "> quote", config: config)
        let attrStr = result.renderedAttributedString
        var range = NSRange()
        let attrs = attrStr.attributes(at: 0, effectiveRange: &range)
        let color = attrs[.foregroundColor] as? UIColor
        #expect(color == UIColor.secondaryLabel)
    }
}
#endif
