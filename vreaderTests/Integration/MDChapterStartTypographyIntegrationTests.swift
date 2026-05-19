// Purpose: Feature #68 WI-3 — composition coverage for MD chapter-start
// typography. Drives the real render → decorate path
// (`MDAttributedStringRenderer.render` → `MDChapterStartDecorator.decorate`)
// the way `MDReaderViewModel.open` wires it, confirming the decoration
// lands while `renderedText` stays byte-identical to the undecorated
// render — the search / highlight / position offset-safety contract.
//
// Scope note: composition coverage of the public functions the
// ViewModel composes, not a SwiftUI-lifecycle test.
//
// @coordinates-with: MDAttributedStringRenderer.swift,
//   MDChapterStartDecorator.swift, MDReaderViewModel.swift

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("MD chapter-start typography — composition (feature #68 WI-3)")
struct MDChapterStartTypographyIntegrationTests {

    private func config() -> MDRenderConfig {
        var c = MDRenderConfig.default
        c.fontSize = 18
        c.accentColor = UIColor(red: 0.55, green: 0.18, blue: 0.18, alpha: 1.0)
        c.chapterHeadingColor = UIColor(white: 0.4, alpha: 1.0)
        return c
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

    @Test("leading-heading MD — decoration applied, renderedText byte-identical")
    func leadingHeadingDocumentDecorated() {
        let md = "# The First Chapter\n\nIt was a bright cold day in April."
        let info = MDAttributedStringRenderer.render(text: md, config: config())
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        // Decoration present.
        #expect(hasHeadingRestyle(decorated))
        #expect(hasDropCap(decorated))
        // Offset safety: backing string identical to the undecorated render.
        #expect(decorated.string == info.renderedText)
        #expect((decorated.string as NSString).length == info.renderedTextLengthUTF16)
    }

    @Test("no-leading-heading MD — drop-cap only, renderedText byte-identical")
    func noLeadingHeadingDocument() {
        let md = "It was a bright cold day, and the clocks were striking thirteen."
        let info = MDAttributedStringRenderer.render(text: md, config: config())
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(!hasHeadingRestyle(decorated))
        #expect(hasDropCap(decorated))
        #expect(decorated.string == info.renderedText)
    }

    @Test("first heading not at offset 0 — no heading restyle, drop-cap on first body para")
    func firstHeadingNotAtOffsetZero() {
        let md = "An opening prose paragraph.\n\n# A Mid-Document Heading\n\nMore prose."
        let info = MDAttributedStringRenderer.render(text: md, config: config())
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(!hasHeadingRestyle(decorated))
        #expect(hasDropCap(decorated))
        #expect(decorated.string == info.renderedText)
    }

    @Test("decoration is purely additive — undecorated and decorated strings match exactly")
    func decorationIsAdditiveOnly() {
        let md = "# Chapter\n\nThe quick brown fox jumps over the lazy dog."
        let info = MDAttributedStringRenderer.render(text: md, config: config())
        let decorated = MDChapterStartDecorator.decorate(
            info.renderedAttributedString, headings: info.headings, config: config()
        )
        #expect(decorated.string == info.renderedAttributedString.string)
        #expect(decorated.length == info.renderedAttributedString.length)
    }
}
#endif
