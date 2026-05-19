// Purpose: Feature #68 WI-5 — pins the chapter-start drop-cap rule
// `FoliateStyleMapper.themeCSS` emits for the AZW3/MOBI (Foliate)
// renderer when a non-nil `accentColor` is supplied. Asserts the pinned
// `body > p:first-of-type::first-letter` selector, the design
// declarations with `!important`, opt-out when `accentColor` is nil,
// and that a malicious accent string is neutralized by
// `FoliateJSEscaper.sanitizeCSSColor`.
//
// @coordinates-with: FoliateStyleMapper.swift, FoliateJSEscaper.swift,
//   ChapterStartTypography.swift

import Testing
@testable import vreader

@Suite("FoliateStyleMapper — chapter-start drop-cap (feature #68 WI-5)")
struct FoliateStyleMapperChapterStartTests {

    /// Extracts the `body > p:first-of-type::first-letter { ... }` rule
    /// body from the CSS. Returns nil when the rule is absent.
    private func dropCapBlock(_ css: String) -> String? {
        let selector = "body > p:first-of-type::first-letter {"
        guard let selRange = css.range(of: selector) else { return nil }
        guard let closeBrace = css[selRange.upperBound...].firstIndex(of: "}")
        else { return nil }
        return String(css[selRange.upperBound..<closeBrace])
    }

    @Test("non-nil accentColor emits the pinned child-combinator drop-cap rule")
    func emitsDropCapRule() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6, fontFamily: nil,
            textColor: "#1a1a1a", backgroundColor: "#ffffff",
            accentColor: "#8c2f2f"
        )
        #expect(css.contains("body > p:first-of-type::first-letter"),
                "Drop-cap rule must use the pinned child-combinator selector")
    }

    @Test("drop-cap rule block carries the full design declarations with !important")
    func dropCapDeclarations() throws {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6, fontFamily: nil,
            textColor: nil, backgroundColor: nil, accentColor: "#8c2f2f"
        )
        let block = try #require(dropCapBlock(css),
                                 "Drop-cap rule block must be present")
        #expect(block.contains("font-size: 2.6em !important"))
        #expect(block.contains("float: left !important"))
        #expect(block.contains("font-weight: 600 !important"))
        #expect(block.contains("line-height: 0.85 !important"))
        #expect(block.contains("color: #8c2f2f !important"))
        // Serif stack + margins — parity with the EPUB WI-4 rule
        // (ReaderThemeV2+EPUBCSS.dropCapCSSRule). A drift here would
        // silently desync the AZW3/MOBI drop-cap from the EPUB one.
        #expect(block.contains(
            "font-family: 'Source Serif 4', Georgia, 'Times New Roman', serif !important"))
        #expect(block.contains("margin-right: 0.06em !important"))
        #expect(block.contains("margin-top: 0.05em !important"))
    }

    @Test("every declaration in the drop-cap rule block carries !important")
    func everyDeclarationImportant() throws {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6, fontFamily: nil,
            textColor: nil, backgroundColor: nil, accentColor: "#8c2f2f"
        )
        let block = try #require(dropCapBlock(css))
        let declarations = block.components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for decl in declarations {
            #expect(decl.contains("!important"),
                    "Declaration <\(decl)> must carry !important (file convention)")
        }
    }

    @Test("drop-cap font-size is the ChapterStartTypography constant")
    func dropCapFontSizeConstant() throws {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6, fontFamily: nil,
            textColor: nil, backgroundColor: nil, accentColor: "#8c2f2f"
        )
        let block = try #require(dropCapBlock(css))
        #expect(block.contains(
            "font-size: \(ChapterStartTypography.dropCapCSSFontSizeEm) !important"))
    }

    @Test("nil accentColor emits no drop-cap rule (back-compat / opt-out)")
    func nilAccentNoDropCap() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6, fontFamily: nil,
            textColor: "#1a1a1a", backgroundColor: "#ffffff",
            accentColor: nil
        )
        #expect(!css.contains("::first-letter"),
                "nil accentColor must emit no drop-cap rule")
    }

    @Test("a malicious accentColor is neutralized — cannot break out of the declaration")
    func maliciousAccentNeutralized() {
        // An accent string attempting CSS injection: `sanitizeCSSColor`
        // rejects values containing `;`, `{`, `}` etc., so the drop-cap
        // rule is simply omitted — the injection cannot land.
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6, fontFamily: nil,
            textColor: nil, backgroundColor: nil,
            accentColor: "red; } body { display:none } /*"
        )
        // The injected `body { display:none }` must NOT appear, and no
        // drop-cap rule is emitted (the malicious value is rejected).
        #expect(!css.contains("display:none"),
                "Malicious accent must not inject a display:none rule")
        #expect(!css.contains("body > p:first-of-type::first-letter"),
                "A rejected accent emits no drop-cap rule")
    }

    @Test("existing themeCSS font-size / color output is unchanged with the new parameter")
    func existingOutputUnchanged() {
        // The new accentColor parameter must not disturb the existing
        // body font-size / color / background rules.
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 20, lineHeight: 1.5, fontFamily: nil,
            textColor: "#222222", backgroundColor: "#fafafa",
            accentColor: "#8c2f2f"
        )
        #expect(css.contains("font-size: 20px !important"))
        #expect(css.contains("color: #222222 !important"))
        #expect(css.contains("background: #fafafa !important"))
    }

    @Test("drop-cap rule omitted when accentColor is an empty string")
    func emptyAccentNoDropCap() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6, fontFamily: nil,
            textColor: nil, backgroundColor: nil, accentColor: ""
        )
        #expect(!css.contains("::first-letter"))
    }
}
