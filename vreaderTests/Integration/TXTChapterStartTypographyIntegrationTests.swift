// Purpose: Feature #68 WI-2 — composition coverage for TXT chapter-start
// typography. Exercises the real two-step data flow the
// TXTReaderContainerView `.task` performs —
// `TXTReaderViewModel.headingLineLength(chapterText:chapterTitle:)`
// feeding `TXTAttributedStringBuilder.buildChapterStart(...)` — with
// chapter-shaped fixture text for the regex, synthetic, and "前言"
// chapter shapes, plus the cross-builder offset-safety invariant.
//
// Scope note: this is composition coverage of the public functions the
// container wires together, NOT a SwiftUI-lifecycle test. The container
// `.task` is a SwiftUI hook and `currentChapterText` is `private(set)`,
// so driving the literal `.task` branch is out of scope here — the unit
// suites (`TXTReaderViewModelChapterHeadingTests`,
// `TXTAttributedStringBuilderChapterStartTests`,
// `TXTReaderContainerViewChapterStartTests`) cover the individual seams.
//
// @coordinates-with: TXTReaderViewModel.swift, TXTAttributedStringBuilder.swift

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("TXT chapter-start typography — composition (feature #68 WI-2)")
struct TXTChapterStartTypographyIntegrationTests {

    private func config() -> TXTViewConfig {
        var c = TXTViewConfig()
        c.fontSize = 18
        c.accentColor = UIColor(red: 0.55, green: 0.18, blue: 0.18, alpha: 1.0)
        c.chapterHeadingColor = UIColor(white: 0.4, alpha: 1.0)
        return c
    }

    private func hasDropCap(_ s: NSAttributedString, fontSize: CGFloat) -> Bool {
        var found = false
        s.enumerateAttribute(.font, in: NSRange(location: 0, length: s.length)) { value, _, _ in
            if let f = value as? UIFont,
               f.pointSize >= fontSize * ChapterStartTypography.dropCapScale - 0.5 {
                found = true
            }
        }
        return found
    }

    private func hasHeadingRun(_ s: NSAttributedString) -> Bool {
        var found = false
        s.enumerateAttribute(.font, in: NSRange(location: 0, length: s.length)) { value, _, _ in
            if let f = value as? UIFont,
               f.pointSize == ChapterStartTypography.headingFontSize {
                found = true
            }
        }
        return found
    }

    /// A regex-detected chapter: the heading line IS the first body line.
    @Test("regex chapter 1 — drop-cap + heading run both present")
    func regexChapterOneDecorated() {
        let title = "Chapter One"
        let chapterText = "\(title)\nIt was the best of times, it was the worst of times."
        let headingLen = TXTReaderViewModel.headingLineLength(
            chapterText: chapterText, chapterTitle: title
        )
        #expect(headingLen == (title as NSString).length)

        let attr = TXTAttributedStringBuilder.buildChapterStart(
            text: chapterText, config: config(), headingLineLength: headingLen
        )
        #expect(attr.string == chapterText)
        #expect(hasHeadingRun(attr))
        #expect(hasDropCap(attr, fontSize: 18))
    }

    /// A second regex chapter with a different heading — the treatment
    /// is chapter-index-independent (every regex chapter is decorated).
    @Test("second regex chapter — drop-cap + heading run both present")
    func regexMidBookChapterDecorated() {
        let title = "Chapter Seven"
        let chapterText = "\(title)\nFar out in the uncharted backwaters of the galaxy."
        let headingLen = TXTReaderViewModel.headingLineLength(
            chapterText: chapterText, chapterTitle: title
        )
        let attr = TXTAttributedStringBuilder.buildChapterStart(
            text: chapterText, config: config(), headingLineLength: headingLen
        )
        #expect(hasHeadingRun(attr))
        #expect(hasDropCap(attr, fontSize: 18))
        #expect(attr.string == chapterText)
    }

    /// A synthetic chapter: title is "Chapter 3" but the body opens with
    /// prose — no heading line in the body, so drop-cap only.
    @Test("synthetic chapter — drop-cap present, no heading run")
    func syntheticChapterDropCapOnly() {
        let chapterText = "Prose that opens this chapter without a heading line above."
        let headingLen = TXTReaderViewModel.headingLineLength(
            chapterText: chapterText, chapterTitle: "Chapter 3"
        )
        #expect(headingLen == 0)

        let attr = TXTAttributedStringBuilder.buildChapterStart(
            text: chapterText, config: config(), headingLineLength: headingLen
        )
        #expect(attr.string == chapterText)
        #expect(hasDropCap(attr, fontSize: 18))
        #expect(!hasHeadingRun(attr))
    }

    /// The "前言" shape: title not in the body. Drop-cap only.
    @Test("'前言' chapter — drop-cap eligible char skipped for CJK, no heading run")
    func qianyanChapterShape() {
        let chapterText = "这本书的开篇正文从这里开始展开叙述。"
        let headingLen = TXTReaderViewModel.headingLineLength(
            chapterText: chapterText, chapterTitle: "前言"
        )
        #expect(headingLen == 0)

        let attr = TXTAttributedStringBuilder.buildChapterStart(
            text: chapterText, config: config(), headingLineLength: headingLen
        )
        // CJK first char → drop-cap skipped (R4); no heading run; string intact.
        #expect(attr.string == chapterText)
        #expect(!hasHeadingRun(attr))
        #expect(!hasDropCap(attr, fontSize: 18))
    }

    /// Offset-safety: the decorated string's UTF-16 length is identical
    /// to the plain build, so highlight / search / position offsets hold.
    @Test("decorated chapter string is byte-identical to the plain build")
    func offsetSafetyAcrossBuilders() {
        let title = "Chapter Two"
        let chapterText = "\(title)\nThe quick brown fox jumps over the lazy dog."
        let headingLen = TXTReaderViewModel.headingLineLength(
            chapterText: chapterText, chapterTitle: title
        )
        let plain = TXTAttributedStringBuilder.build(
            text: chapterText, config: config()
        )
        let decorated = TXTAttributedStringBuilder.buildChapterStart(
            text: chapterText, config: config(), headingLineLength: headingLen
        )
        #expect(plain.string == decorated.string)
        #expect(plain.length == decorated.length)
    }
}
#endif
