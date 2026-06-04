// Purpose: Feature #68 WI-2 — tests for
// TXTAttributedStringBuilder.buildChapterStart, the chapter-start
// typography variant (drop-cap + regex-heading restyle).
//
// The single most important invariant pinned here: buildChapterStart
// only ever adds NSAttributedString attributes — the backing string is
// byte-identical to the input text in every path, so every offset-based
// subsystem (positions, highlights, search, TTS) is unaffected.
//
// @coordinates-with: TXTAttributedStringBuilder.swift,
//   ChapterStartTypography.swift

#if canImport(UIKit)
import Testing
import UIKit
@testable import vreader

@Suite("TXTAttributedStringBuilder — chapter start (feature #68 WI-2)")
struct TXTAttributedStringBuilderChapterStartTests {

    // MARK: - Helpers

    private func config(fontSize: CGFloat = 18) -> TXTViewConfig {
        var c = TXTViewConfig()
        c.fontSize = fontSize
        c.accentColor = UIColor(red: 0.55, green: 0.18, blue: 0.18, alpha: 1.0)
        c.chapterHeadingColor = UIColor(white: 0.4, alpha: 1.0)
        return c
    }

    private func dropCapRun(_ s: NSAttributedString, at index: Int)
        -> (font: UIFont?, color: UIColor?, baseline: CGFloat?) {
        let font = s.attribute(.font, at: index, effectiveRange: nil) as? UIFont
        let color = s.attribute(.foregroundColor, at: index, effectiveRange: nil) as? UIColor
        let baseline = s.attribute(.baselineOffset, at: index, effectiveRange: nil) as? CGFloat
        return (font, color, baseline)
    }

    // MARK: - Backing-string invariant (the v2 offset invariant)

    @Test("buildChapterStart does not change the backing string — regex chapter")
    func backingStringUnchangedRegexChapter() {
        let text = "Chapter One\nIt was a bright cold day in April."
        let headingLen = ("Chapter One" as NSString).length
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(), headingLineLength: headingLen
        )
        #expect(result.string == text)
        #expect(result.length == (text as NSString).length)
    }

    @Test("buildChapterStart does not change the backing string — synthetic chapter")
    func backingStringUnchangedSyntheticChapter() {
        let text = "It was a bright cold day in April, and the clocks were striking."
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(), headingLineLength: 0
        )
        #expect(result.string == text)
        #expect(result.length == (text as NSString).length)
    }

    // MARK: - Heading run (regex chapters, headingLineLength > 0)

    @Test("heading run carries the design serif typography over 0..<headingLineLength")
    func headingRunStyled() {
        let heading = "Chapter One"
        let text = "\(heading)\nBody text starts here."
        let headingLen = (heading as NSString).length
        let cfg = config()
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: cfg, headingLineLength: headingLen
        )

        // Sample a char inside the heading (skip index 0 which also has
        // the drop-cap... actually the drop-cap is on the BODY paragraph,
        // not the heading — so index 0 here is heading-only).
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.pointSize == ChapterStartTypography.headingFontSize)

        let kern = result.attribute(.kern, at: 2, effectiveRange: nil) as? CGFloat
        #expect(kern == ChapterStartTypography.headingLetterSpacing)

        let color = result.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? UIColor
        #expect(color == cfg.chapterHeadingColor)

        let style = result.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
        #expect(style?.alignment == .center)
        #expect(style?.paragraphSpacing == ChapterStartTypography.headingSpacingAfter)
        #expect(style?.paragraphSpacingBefore == ChapterStartTypography.headingSpacingBefore)
    }

    /// Feature #92: the chapter-start BODY inherits the justified base
    /// alignment (the decorator copies the base style for the drop-cap
    /// paragraph) while the heading stays centered (the decorator sets a
    /// fresh `.center` style) — the two coexist.
    @Test("feature #92 — heading centered, body justified")
    func chapterStartBodyIsJustifiedHeadingCentered() {
        let heading = "Chapter One"
        let text = "\(heading)\nBody text that should be justified across the page."
        let headingLen = (heading as NSString).length
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(), headingLineLength: headingLen
        )
        // Heading paragraph (inside the heading line) stays centered.
        let headingStyle = result.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle
        #expect(headingStyle?.alignment == .center)
        // Body paragraph (well past the heading + newline) is justified.
        let bodyStyle = result.attribute(.paragraphStyle, at: headingLen + 5, effectiveRange: nil) as? NSParagraphStyle
        #expect(bodyStyle?.alignment == .justified)
    }

    @Test("heading text characters are byte-identical — no uppercase transform")
    func headingNoUppercase() {
        // German ß would change length under .uppercased() (ß -> SS).
        let heading = "Straße"
        let text = "\(heading)\nBody."
        let headingLen = (heading as NSString).length
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(), headingLineLength: headingLen
        )
        #expect((result.string as NSString).substring(to: headingLen) == heading)
    }

    @Test("synthetic chapter applies no heading run")
    func syntheticChapterNoHeadingRun() {
        let text = "Body prose with no heading line above it at all here."
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(), headingLineLength: 0
        )
        // No run anywhere should carry the 13pt heading font size.
        var sawHeadingFont = false
        result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if let f = value as? UIFont, f.pointSize == ChapterStartTypography.headingFontSize {
                sawHeadingFont = true
            }
        }
        #expect(!sawHeadingFont)
    }

    // MARK: - Drop-cap run

    @Test("drop-cap run on first body char — regex chapter at offset headingLineLength")
    func dropCapRegexChapter() {
        let heading = "Chapter One"
        let text = "\(heading)\nBright morning light filled the room."
        let headingLen = (heading as NSString).length
        let cfg = config(fontSize: 18)
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: cfg, headingLineLength: headingLen
        )
        // First body char is at headingLen + 1 (past the "\n").
        let bodyStart = headingLen + 1
        let run = dropCapRun(result, at: bodyStart)
        #expect(run.font != nil)
        #expect((run.font?.pointSize ?? 0) >= 18 * ChapterStartTypography.dropCapScale - 0.5)
        #expect(run.color == cfg.accentColor)
        // A negative baselineOffset drops the oversized capital onto the line.
        #expect((run.baseline ?? 0) < 0)
    }

    @Test("drop-cap run on first body char — synthetic chapter at offset 0")
    func dropCapSyntheticChapter() {
        let text = "Bright morning light filled the room and woke the cat."
        let cfg = config(fontSize: 20)
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: cfg, headingLineLength: 0
        )
        let run = dropCapRun(result, at: 0)
        #expect(run.font != nil)
        #expect((run.font?.pointSize ?? 0) >= 20 * ChapterStartTypography.dropCapScale - 0.5)
        #expect(run.color == cfg.accentColor)
        #expect((run.baseline ?? 0) < 0)
    }

    @Test("first body paragraph gets a positive firstLineHeadIndent for the drop-cap")
    func dropCapFirstLineIndent() {
        let text = "Bright morning light filled the room."
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(), headingLineLength: 0
        )
        let style = result.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        #expect((style?.firstLineHeadIndent ?? 0) > 0)
    }

    @Test("drop-cap applied only to the first body paragraph, not later paragraphs")
    func dropCapOnlyFirstParagraph() {
        let text = "First paragraph here.\nSecond paragraph also here with more words."
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(fontSize: 18), headingLineLength: 0
        )
        // The 'S' starting "Second" must NOT carry the 2.6x drop-cap font.
        let secondStart = ("First paragraph here.\n" as NSString).length
        let font = result.attribute(.font, at: secondStart, effectiveRange: nil) as? UIFont
        #expect((font?.pointSize ?? 0) < 18 * ChapterStartTypography.dropCapScale - 0.5)
    }

    // MARK: - Eligibility edge cases (Risk R4 / R5)

    @Test("leading opening quote — drop-cap goes on the first letter after the quote (R5)")
    func dropCapAfterOpeningQuote() {
        // U+201C left double quote, then 'H'.
        let text = "\u{201C}Hello,\u{201D} she said as the door opened."
        let cfg = config(fontSize: 18)
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: cfg, headingLineLength: 0
        )
        // The quote at index 0 must NOT be enlarged.
        let quoteFont = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect((quoteFont?.pointSize ?? 0) < 18 * ChapterStartTypography.dropCapScale - 0.5)
        // The 'H' at index 1 carries the drop-cap.
        let letterRun = dropCapRun(result, at: 1)
        #expect((letterRun.font?.pointSize ?? 0) >= 18 * ChapterStartTypography.dropCapScale - 0.5)
        #expect(letterRun.color == cfg.accentColor)
    }

    @Test("supplementary-plane letter — drop-cap styles the full surrogate pair")
    func dropCapSupplementaryPlaneLetter() {
        // U+10400 DESERET CAPITAL LETTER LONG I — alphabetic, non-CJK,
        // so isDropCapEligible accepts it. Its UTF-16 form is a surrogate
        // pair (length 2); the drop-cap run must cover both units.
        let deseret = String(Unicode.Scalar(0x10400)!)
        let text = "\(deseret)ater words follow in the paragraph."
        let cfg = config(fontSize: 18)
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: cfg, headingLineLength: 0
        )
        #expect(result.string == text)
        // Both UTF-16 units of the pair carry the drop-cap font.
        let unit0 = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let unit1 = result.attribute(.font, at: 1, effectiveRange: nil) as? UIFont
        #expect((unit0?.pointSize ?? 0) >= 18 * ChapterStartTypography.dropCapScale - 0.5)
        #expect((unit1?.pointSize ?? 0) >= 18 * ChapterStartTypography.dropCapScale - 0.5)
        // The next char ('a', UTF-16 index 2) is NOT enlarged.
        let next = result.attribute(.font, at: 2, effectiveRange: nil) as? UIFont
        #expect((next?.pointSize ?? 0) < 18 * ChapterStartTypography.dropCapScale - 0.5)
    }

    @Test("CJK-leading body paragraph — drop-cap skipped, no crash (R4)")
    func dropCapSkippedForCJK() {
        // U+4E2D 中 leads the body — ineligible per ChapterStartTypography.
        let text = "\u{4E2D}文小说的开头第一段文字内容。"
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(fontSize: 18), headingLineLength: 0
        )
        // No 2.6x run anywhere.
        var sawDropCap = false
        result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if let f = value as? UIFont, f.pointSize >= 18 * ChapterStartTypography.dropCapScale - 0.5 {
                sawDropCap = true
            }
        }
        #expect(!sawDropCap)
        // String unchanged.
        #expect(result.string == text)
    }

    @Test("CJK chapter still restyles the heading line even though the drop-cap is skipped")
    func cjkChapterHeadingStillRestyled() {
        let heading = "第一章"
        let text = "\(heading)\n中文小说的正文内容从这里开始。"
        let headingLen = (heading as NSString).length
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(), headingLineLength: headingLen
        )
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        #expect(font?.pointSize == ChapterStartTypography.headingFontSize)
        #expect(result.string == text)
    }

    // MARK: - Degenerate input

    @Test("empty text — no crash, returns empty string")
    func emptyText() {
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: "", config: config(), headingLineLength: 0
        )
        #expect(result.string == "")
        #expect(result.length == 0)
    }

    @Test("single-character text — no crash")
    func singleCharacterText() {
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: "A", config: config(), headingLineLength: 0
        )
        #expect(result.string == "A")
        #expect(result.length == 1)
    }

    @Test("text is only a heading line with no body — no crash")
    func headingOnlyNoBody() {
        let text = "Chapter One"
        let headingLen = (text as NSString).length
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(), headingLineLength: headingLen
        )
        #expect(result.string == text)
        #expect(result.length == headingLen)
    }

    @Test("headingLineLength larger than text length — treated as no heading (drop-cap only)")
    func headingLineLengthOverflow() {
        // Overflow is invalid input — it must NOT restyle the whole body
        // as a heading. It is treated as headingLineLength == 0: no
        // heading run, drop-cap still applied to the first body char.
        let text = "Short opening line of the body paragraph here."
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(fontSize: 18), headingLineLength: 9999
        )
        #expect(result.string == text)
        #expect(result.length == (text as NSString).length)
        // No run carries the 13pt heading font.
        var sawHeadingFont = false
        result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if let f = value as? UIFont, f.pointSize == ChapterStartTypography.headingFontSize {
                sawHeadingFont = true
            }
        }
        #expect(!sawHeadingFont)
        // Drop-cap still lands on the first body char.
        let run = dropCapRun(result, at: 0)
        #expect((run.font?.pointSize ?? 0) >= 18 * ChapterStartTypography.dropCapScale - 0.5)
        #expect(run.color == config().accentColor)
    }

    @Test("negative headingLineLength — treated as no heading, no crash")
    func headingLineLengthNegative() {
        let text = "Body text with a negative heading length argument."
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(), headingLineLength: -5
        )
        #expect(result.string == text)
        var sawHeadingFont = false
        result.enumerateAttribute(.font, in: NSRange(location: 0, length: result.length)) { value, _, _ in
            if let f = value as? UIFont, f.pointSize == ChapterStartTypography.headingFontSize {
                sawHeadingFont = true
            }
        }
        #expect(!sawHeadingFont)
    }

    @Test("first body paragraph is empty / all-whitespace — drop-cap skipped, no crash")
    func emptyBodyParagraph() {
        let heading = "Chapter One"
        let text = "\(heading)\n   \nReal body text after the blank line."
        let headingLen = (heading as NSString).length
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(), headingLineLength: headingLen
        )
        #expect(result.string == text)
        #expect(result.length == (text as NSString).length)
    }

    @Test("all-whitespace heading line — no crash, string unchanged")
    func whitespaceHeadingLine() {
        let text = "   \nBody text content goes here in the paragraph."
        let result = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: config(), headingLineLength: 3
        )
        #expect(result.string == text)
        #expect(result.length == (text as NSString).length)
    }

    // MARK: - buildChapterStartSendable

    @Test("buildChapterStartSendable wraps the same result")
    func sendableVariant() {
        let text = "Chapter One\nBody text."
        let headingLen = ("Chapter One" as NSString).length
        let cfg = config()
        let direct = TXTAttributedStringBuilder.buildChapterStart(
            text: text, config: cfg, headingLineLength: headingLen
        )
        let wrapped = TXTAttributedStringBuilder.buildChapterStartSendable(
            text: text, config: cfg, headingLineLength: headingLen
        )
        #expect(wrapped.value.isEqual(to: direct))
    }

    // MARK: - renderingEquals

    @Test("renderingEquals is false when accentColor differs")
    func renderingEqualsAccentColor() {
        var a = TXTViewConfig()
        var b = TXTViewConfig()
        a.accentColor = .red
        b.accentColor = .blue
        #expect(!a.renderingEquals(b))
    }

    @Test("renderingEquals is false when chapterHeadingColor differs")
    func renderingEqualsHeadingColor() {
        var a = TXTViewConfig()
        var b = TXTViewConfig()
        a.chapterHeadingColor = .red
        b.chapterHeadingColor = .blue
        #expect(!a.renderingEquals(b))
    }

    @Test("renderingEquals is true when the two new colors match")
    func renderingEqualsDefaults() {
        let a = TXTViewConfig()
        let b = TXTViewConfig()
        #expect(a.renderingEquals(b))
    }
}
#endif
