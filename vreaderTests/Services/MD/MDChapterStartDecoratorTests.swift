// Purpose: Feature #68 WI-3 — tests for MDChapterStartDecorator, which
// applies the design's chapter-start typography (leading-heading restyle
// + accent drop-cap) to the MD renderer's NSAttributedString.
//
// CONTRACT pinned here: decorate(...) only ADDS attributes — the backing
// string is byte-identical to the input, so search / highlight / position
// offsets are unaffected.
//
// @coordinates-with: MDChapterStartDecorator.swift, MDAttributedStringRenderer.swift

#if canImport(UIKit)
import Testing
import UIKit
@testable import vreader

@Suite("MDChapterStartDecorator (feature #68 WI-3)")
struct MDChapterStartDecoratorTests {

    private func config() -> MDRenderConfig {
        var c = MDRenderConfig.default
        c.fontSize = 18
        c.accentColor = UIColor(red: 0.55, green: 0.18, blue: 0.18, alpha: 1.0)
        c.chapterHeadingColor = UIColor(white: 0.4, alpha: 1.0)
        return c
    }

    private func render(_ md: String) -> MDDocumentInfo {
        MDAttributedStringRenderer.render(text: md, config: config())
    }

    private func hasDropCap(_ s: NSAttributedString, fontSize: CGFloat = 18) -> Bool {
        var found = false
        s.enumerateAttribute(.font, in: NSRange(location: 0, length: s.length)) { value, _, _ in
            if let f = value as? UIFont,
               f.pointSize >= fontSize * ChapterStartTypography.dropCapScale - 0.5 {
                found = true
            }
        }
        return found
    }

    private func hasHeadingRestyle(_ s: NSAttributedString) -> Bool {
        var found = false
        s.enumerateAttribute(.font, in: NSRange(location: 0, length: s.length)) { value, _, _ in
            if let f = value as? UIFont,
               f.pointSize == ChapterStartTypography.headingFontSize {
                found = true
            }
        }
        return found
    }

    // MARK: - Backing-string invariant

    @Test("decorate does not change the backing string — leading heading doc")
    func backingStringUnchangedLeadingHeading() {
        let info = render("# Chapter One\n\nBody text starts here in the first paragraph.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(decorated.string == info.renderedAttributedString.string)
        #expect(decorated.length == info.renderedAttributedString.length)
    }

    @Test("decorate does not change the backing string — no-heading doc")
    func backingStringUnchangedNoHeading() {
        let info = render("Body text with no heading at the document head at all.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(decorated.string == info.renderedAttributedString.string)
        #expect(decorated.length == info.renderedAttributedString.length)
    }

    // MARK: - Leading heading restyle

    @Test("leading '# Heading' at offset 0 is restyled with the chapter-heading typography")
    func leadingHeadingRestyled() {
        let info = render("# Chapter One\n\nBody paragraph text here.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        // The heading run carries the 13pt serif heading font.
        let font = decorated.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.pointSize == ChapterStartTypography.headingFontSize)
        let kern = decorated.attribute(.kern, at: 2, effectiveRange: nil) as? CGFloat
        #expect(kern == ChapterStartTypography.headingLetterSpacing)
        let color = decorated.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? UIColor
        #expect(color == config().chapterHeadingColor)
        let style = decorated.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.alignment == .center)
    }

    @Test("leading heading characters are byte-identical — no uppercase transform")
    func leadingHeadingNoUppercase() {
        let info = render("# Straße\n\nBody.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(decorated.string == info.renderedAttributedString.string)
    }

    @Test("no heading at offset 0 (body first) — no heading restyle")
    func noHeadingAtOffsetZeroNoRestyle() {
        let info = render("Body text first.\n\n# Later Heading\n\nMore body.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        // The "Later Heading" is NOT at offset 0 → no chapter-heading restyle.
        #expect(!hasHeadingRestyle(decorated))
    }

    @Test("first heading not at offset 0 — no heading restyle, drop-cap on first body para")
    func firstHeadingNotAtOffsetZero() {
        let info = render("Opening prose paragraph.\n\n# A Heading\n\nMore text.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(!hasHeadingRestyle(decorated))
        // Drop-cap goes on the genuine first body paragraph ("Opening...").
        #expect(hasDropCap(decorated))
        let run = decorated.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(run == config().accentColor)
    }

    // MARK: - Drop-cap

    @Test("drop-cap on the first body paragraph after a leading heading")
    func dropCapAfterLeadingHeading() {
        let info = render("# Chapter One\n\nBright morning light filled the room.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(hasDropCap(decorated))
        // The drop-cap is NOT on the heading line — the heading 'C' is 13pt.
        let headingFont = decorated.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect((headingFont?.pointSize ?? 0) < 18 * ChapterStartTypography.dropCapScale - 0.5)
    }

    @Test("drop-cap on the first paragraph when the document has no leading heading")
    func dropCapNoLeadingHeading() {
        let info = render("Bright morning light filled the quiet room and stirred the cat.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(hasDropCap(decorated))
        let run = decorated.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        #expect(run == config().accentColor)
    }

    @Test("drop-cap is NOT applied when the first body block is a bullet list")
    func noDropCapOnList() {
        let info = render("# Heading\n\n- first list item here\n- second item")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(!hasDropCap(decorated))
    }

    @Test("drop-cap is NOT applied when the first body block is an ordered list")
    func noDropCapOnOrderedList() {
        let info = render("# Heading\n\n1. first ordered item\n2. second ordered item")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(!hasDropCap(decorated))
    }

    @Test("drop-cap is NOT applied when the first body block is a fenced code block")
    func noDropCapOnCodeBlock() {
        let info = render("# Heading\n\n```\nlet x = 1\n```")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(!hasDropCap(decorated))
    }

    @Test("drop-cap is NOT applied when the first body block is a blockquote")
    func noDropCapOnBlockquote() {
        let info = render("# Heading\n\n> a quoted opening line of the chapter")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(!hasDropCap(decorated))
    }

    @Test("drop-cap lands on a plain paragraph that follows an initial list block")
    func dropCapSkipsListThenPlainParagraph() {
        let info = render("# Heading\n\n- a list item\n\nA real plain paragraph follows the list.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        // The drop-cap skips the list and lands on the plain paragraph.
        #expect(hasDropCap(decorated))
    }

    @Test("leading heading followed by a second heading — drop-cap skips the 2nd heading")
    func dropCapSkipsSecondHeading() {
        // `# H1` is the leading heading (restyled); `## H2` is a heading
        // too — it is rendered as plain bold text with no distinctive run
        // attribute, so it MUST still be excluded from the drop-cap scan.
        let info = render("# Chapter One\n\n## A Subheading\n\nThe real body paragraph here.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        // The drop-cap must NOT be on "A Subheading" — it must land on the
        // genuine body paragraph. The subheading line ("A Subheading\n")
        // starts after "Chapter One\n" = 12 UTF-16 units; the 'A' there
        // must not carry the 2.6x drop-cap font.
        let subheadingStart = ("Chapter One\n" as NSString).length
        let subFont = decorated.attribute(.font, at: subheadingStart, effectiveRange: nil) as? UIFont
        #expect((subFont?.pointSize ?? 0) < 18 * ChapterStartTypography.dropCapScale - 0.5)
        // The drop-cap IS applied (to the body paragraph).
        #expect(hasDropCap(decorated))
    }

    @Test("leading quote on the first body paragraph — drop-cap on the first letter (R5)")
    func dropCapAfterLeadingQuote() {
        // U+201C left double quote, then 'A'.
        let info = render("# Chapter One\n\n\u{201C}Alpha begins the line,\u{201D} she said.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(hasDropCap(decorated))
        #expect(decorated.string == info.renderedAttributedString.string)
    }

    @Test("supplementary-plane initial on the first body paragraph — drop-cap spans the pair")
    func dropCapSupplementaryPlaneInitial() {
        // U+10400 DESERET CAPITAL LETTER LONG I — alphabetic, non-CJK,
        // drop-cap-eligible; its UTF-16 form is a surrogate pair.
        let deseret = String(Unicode.Scalar(0x10400)!)
        let info = render("# Chapter One\n\n\(deseret)ater words follow here.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(hasDropCap(decorated))
        #expect(decorated.string == info.renderedAttributedString.string)
    }

    // MARK: - Degenerate input

    @Test("empty document — no crash, no-op")
    func emptyDocument() {
        let info = render("")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(decorated.string == "")
        #expect(decorated.length == 0)
    }

    @Test("headings-only document — no crash, no drop-cap")
    func headingsOnlyDocument() {
        let info = render("# Only A Heading")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(decorated.string == info.renderedAttributedString.string)
        #expect(!hasDropCap(decorated))
    }

    @Test("multi-heading-only document — no drop-cap on any heading")
    func multiHeadingOnlyDocument() {
        // A document of nothing but headings must get NO drop-cap — every
        // heading block is excluded from the scan.
        let info = render("# Chapter One\n\n## Subheading\n\n### Sub-subheading")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(decorated.string == info.renderedAttributedString.string)
        #expect(!hasDropCap(decorated))
    }

    @Test("CJK-leading first paragraph — drop-cap skipped (R4), string unchanged")
    func cjkLeadingParagraph() {
        let info = render("# 第一章\n\n中文小说的正文内容从这里开始。")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(decorated.string == info.renderedAttributedString.string)
        #expect(!hasDropCap(decorated))
    }

    @Test("heading with inline markup — restyle applies, string unchanged")
    func headingWithInlineMarkup() {
        let info = render("# **Bold** title\n\nBody paragraph.")
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(decorated.string == info.renderedAttributedString.string)
    }

    // MARK: - Idempotency

    @Test("decorate is idempotent — decorate(decorate(x)) equals decorate(x)")
    func idempotent() {
        let info = render("# Chapter One\n\nBody paragraph text here for the chapter.")
        let once = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        let twice = MDChapterStartDecorator.decorate(
            once, headings: info.headings, config: config()
        )
        #expect(once.isEqual(to: twice))
    }
}
#endif
