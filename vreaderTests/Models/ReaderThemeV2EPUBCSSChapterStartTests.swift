// Purpose: Feature #68 WI-4 — pins the chapter-start drop-cap rule
// appended to `ReaderThemeV2.epubOverrideCSS`. Asserts the exact pinned
// selector `body > p:first-of-type::first-letter` (the child combinator,
// NOT a loose `p:first-of-type`), the design declarations with
// `!important` on every one, per-theme accent color, and that the book's
// own heading rule is preserved.
//
// Every selector / declaration assertion runs against the EXTRACTED
// drop-cap rule block, not loose substrings of the whole stylesheet — so
// a regression that emits a second loose `p:first-of-type::first-letter`
// rule, or drops an `!important`, fails the test.
//
// @coordinates-with: ReaderThemeV2+EPUBCSS.swift, ChapterStartTypography.swift,
//   ReaderTypography.swift

#if canImport(UIKit)
import Testing
import UIKit
@testable import vreader

@Suite("ReaderThemeV2 EPUB CSS — chapter-start drop-cap (feature #68 WI-4)")
struct ReaderThemeV2EPUBCSSChapterStartTests {

    /// Collapses whitespace runs so block extraction + assertions stay
    /// stable across re-indentation (CSS ignores internal whitespace).
    private func normalize(_ css: String) -> String {
        css.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
    }

    /// Extracts the `body > p:first-of-type::first-letter { ... }` rule
    /// block (the `{...}` body) from the normalized CSS. Returns nil when
    /// the rule is absent.
    private func dropCapBlock(_ theme: ReaderThemeV2) -> String? {
        let css = normalize(theme.epubOverrideCSS(fontSize: 18))
        let selector = "body > p:first-of-type::first-letter {"
        guard let selRange = css.range(of: selector) else { return nil }
        guard let closeBrace = css[selRange.upperBound...].firstIndex(of: "}")
        else { return nil }
        return String(css[selRange.upperBound..<closeBrace])
    }

    @Test("emits exactly the pinned child-combinator drop-cap selector")
    func emitsPinnedSelector() {
        let css = normalize(ReaderThemeV2.paper.epubOverrideCSS(fontSize: 18))
        #expect(css.contains("body > p:first-of-type::first-letter"),
                "Drop-cap selector must use the child combinator")
        // There must be NO loose `p:first-of-type::first-letter` rule —
        // i.e. every occurrence of `p:first-of-type::first-letter` must be
        // preceded by the `body > ` child combinator (R6 guard).
        var searchStart = css.startIndex
        while let r = css.range(of: "p:first-of-type::first-letter",
                                range: searchStart..<css.endIndex) {
            let prefixStart = css.index(r.lowerBound, offsetBy: -7,
                                        limitedBy: css.startIndex) ?? css.startIndex
            let prefix = String(css[prefixStart..<r.lowerBound])
            #expect(prefix == "body > ",
                    "Every p:first-of-type::first-letter must be a child-combinator selector — found a loose one")
            searchStart = r.upperBound
        }
    }

    @Test("only one ::first-letter rule is emitted")
    func singleFirstLetterRule() {
        let css = normalize(ReaderThemeV2.paper.epubOverrideCSS(fontSize: 18))
        let count = css.components(separatedBy: "::first-letter").count - 1
        #expect(count == 1, "Exactly one ::first-letter rule expected, found \(count)")
    }

    @Test("drop-cap rule block carries the design declarations with !important")
    func dropCapDeclarations() throws {
        let block = try #require(dropCapBlock(.paper),
                                 "Drop-cap rule block must be present")
        #expect(block.contains("font-size: 2.6em !important"))
        #expect(block.contains("float: left !important"))
        #expect(block.contains("font-weight: 600 !important"))
        #expect(block.contains("line-height: 0.85 !important"))
        #expect(block.contains("margin-right: 0.06em !important"))
        #expect(block.contains("margin-top: 0.05em !important"))
    }

    @Test("every declaration in the drop-cap rule block carries !important")
    func everyDeclarationImportant() throws {
        let block = try #require(dropCapBlock(.paper))
        // Each `;`-terminated declaration must contain `!important`.
        let declarations = block.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for decl in declarations {
            #expect(decl.contains("!important"),
                    "Declaration <\(decl)> must carry !important")
        }
    }

    @Test("drop-cap font-family is the Source Serif 4 stack")
    func dropCapSerifFontStack() throws {
        let block = try #require(dropCapBlock(.paper))
        let expected = "font-family: \(ReaderTypography.cssFontStack(for: .sourceSerif4)) !important"
        #expect(block.contains(expected),
                "Drop-cap font-family must be the ReaderTypography Source Serif 4 stack")
    }

    @Test("drop-cap font-size is the ChapterStartTypography constant")
    func dropCapFontSizeConstant() throws {
        let block = try #require(dropCapBlock(.paper))
        #expect(block.contains(
            "font-size: \(ChapterStartTypography.dropCapCSSFontSizeEm) !important"))
    }

    @Test("every theme's drop-cap rule carries its own accent color with !important")
    func perThemeAccentColor() throws {
        // Expected accent rgb per theme (ReaderThemeV2.accentColor).
        let expected: [ReaderThemeV2: String] = [
            .paper: "rgb(140,47,47)",
            .sepia: "rgb(122,58,31)",
            .dark:  "rgb(214,136,90)",
            .oled:  "rgb(214,136,90)",
            .photo: "rgb(232,180,101)",
        ]
        for theme in ReaderThemeV2.allCases {
            let block = try #require(dropCapBlock(theme),
                                     "Theme \(theme) must emit the drop-cap rule")
            let color = try #require(expected[theme])
            #expect(block.contains("color: \(color) !important"),
                    "Theme \(theme) drop-cap color must be \(color) with !important")
        }
    }

    @Test("Paper and Dark drop-cap colors differ")
    func dropCapColorVariesPerTheme() throws {
        let paper = try #require(dropCapBlock(.paper))
        let dark = try #require(dropCapBlock(.dark))
        #expect(paper.contains("rgb(140,47,47)"))
        #expect(dark.contains("rgb(214,136,90)"))
        #expect(!paper.contains("rgb(214,136,90)"))
    }

    @Test("the book's own h1..h6 rule is still present — no heading regression")
    func headingRulePreserved() {
        let css = normalize(ReaderThemeV2.paper.epubOverrideCSS(fontSize: 18))
        // The existing `h1,h2,h3,h4,h5,h6 { font-size: revert ... }` rule
        // must remain — feature #68 does NOT restyle EPUB headings, and
        // a VReader heading is never injected (no duplicate heading).
        #expect(css.contains("h1,h2,h3,h4,h5,h6"),
                "The book's own heading rule must be preserved (no EPUB heading restyle in v1)")
        #expect(css.contains("font-size: revert"),
                "h1..h6 font-size: revert must remain so book headings render at their own size")
    }

    @Test("all five themes emit the drop-cap rule")
    func allThemesEmitDropCap() {
        for theme in ReaderThemeV2.allCases {
            let css = normalize(theme.epubOverrideCSS(fontSize: 18))
            #expect(css.contains("body > p:first-of-type::first-letter"),
                    "Theme \(theme) must emit the drop-cap rule")
        }
    }
}
#endif
