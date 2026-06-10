// Purpose: Feature #60 WI-4 — ReaderThemeV2 EPUB CSS injection.
// Pins the exact color tokens and Photo-theme background-image rule
// that the WKWebView consumes, so a refactor cannot silently drift
// the visual identity away from the design bundle.

import Testing
import UIKit
@testable import vreader

@Suite("ReaderThemeV2 - EPUB CSS")
struct EPUBThemeOverrideCSSV2Tests {

    /// Collapses runs of whitespace to a single space so selector →
    /// property assertions stay readable. CSS doesn't care about
    /// internal whitespace, and the emitted blob uses multi-space
    /// indents inherited from the source heredoc; we don't want test
    /// failures every time someone re-indents the CSS string.
    private func normalize(_ css: String) -> String {
        css.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
    }

    // MARK: - Selector → property contract per theme
    //
    // Codex Gate 4 round 1 (Medium): assert full selector→property
    // pairs so a regression that swaps html/body backgrounds, routes
    // accent through ::selection-color, or puts `sub` on `a:link`
    // would FAIL these tests. Substring-only assertions previously
    // would have passed those mis-wirings.

    @Test func paperThemeMapsTokensToTheirSelectors() {
        let css = normalize(ReaderThemeV2.paper.epubOverrideCSS(fontSize: 18))
        // html outer bg = paper.backgroundColor
        #expect(css.contains("html { background-color: rgb(244,238,224)"),
                "Paper outer bg pinned to html selector")
        // body paper surface = paper.paperColor
        #expect(css.contains("body { background-color: rgb(250,246,234)"),
                "Paper text-container surface pinned to body selector")
        // primary text color on html, body
        #expect(css.contains("color: rgb(29,26,20)"),
                "Paper ink applied to text")
        // accent on a:link
        #expect(css.contains("a:link { color: rgb(140,47,47)"),
                "Paper accent pinned to a:link")
        // sub on a:visited — Feature #84: light-family sub bumped ink@0.55 →
        // ink@0.68 (WCAG AA); `sub` is global so the a:visited colour darkens too.
        #expect(css.contains("a:visited { color: rgba(29,26,20,0.68)"),
                "Paper sub pinned to a:visited (alpha-blended over ink)")
        // rule on td/th + hr borders
        #expect(css.contains("border: 1px solid rgba(29,26,20,0.12)"),
                "Paper rule pinned to td/th border")
        #expect(css.contains("border-top: 1px solid rgba(29,26,20,0.12)"),
                "Paper rule pinned to hr border-top")
        // accent on ::selection
        #expect(css.contains("::selection { background-color: rgb(140,47,47)"),
                "Paper accent pinned to ::selection background")
    }

    @Test func sepiaThemeMapsTokensToTheirSelectors() {
        let css = normalize(ReaderThemeV2.sepia.epubOverrideCSS(fontSize: 18))
        #expect(css.contains("html { background-color: rgb(230,214,182)"),
                "Sepia outer bg on html")
        #expect(css.contains("body { background-color: rgb(237,223,194)"),
                "Sepia paper on body")
        #expect(css.contains("color: rgb(58,41,19)"), "Sepia ink")
        #expect(css.contains("a:link { color: rgb(122,58,31)"),
                "Sepia accent on a:link")
        #expect(css.contains("a:visited { color: rgba(58,41,19,0.68)"),
                "Sepia sub on a:visited (Feature #84: ink@0.68)")
        #expect(css.contains("border: 1px solid rgba(58,41,19,0.15)"),
                "Sepia rule on td/th border")
    }

    @Test func darkThemeMapsTokensToTheirSelectors() {
        let css = normalize(ReaderThemeV2.dark.epubOverrideCSS(fontSize: 18))
        #expect(css.contains("html { background-color: rgb(26,24,21)"),
                "Dark outer bg on html")
        #expect(css.contains("body { background-color: rgb(33,32,28)"),
                "Dark paper on body")
        #expect(css.contains("color: rgb(216,210,197)"), "Dark ink")
        #expect(css.contains("a:link { color: rgb(214,136,90)"),
                "Dark accent on a:link")
        #expect(css.contains("a:visited { color: rgba(216,210,197,0.50)"),
                "Dark sub on a:visited")
    }

    @Test func oledThemeMapsTokensToTheirSelectors() {
        let css = normalize(ReaderThemeV2.oled.epubOverrideCSS(fontSize: 18))
        #expect(css.contains("html { background-color: rgb(0,0,0)"),
                "OLED outer bg on html — true black")
        #expect(css.contains("body { background-color: rgb(5,5,5)"),
                "OLED paper on body")
        #expect(css.contains("color: rgb(185,182,176)"), "OLED ink")
        #expect(css.contains("a:link { color: rgb(214,136,90)"),
                "OLED accent on a:link (shared with dark)")
    }

    @Test func photoThemeMapsTokensToTheirSelectors() {
        let css = normalize(ReaderThemeV2.photo.epubOverrideCSS(fontSize: 18))
        #expect(css.contains("html { background-color: rgb(42,37,32)"),
                "Photo outer bg on html")
        #expect(css.contains("body { background-color: rgba(20,16,12,0.55)"),
                "Photo paper alpha overlay on body — translucent over outer bg")
        #expect(css.contains("color: rgb(232,224,208)"), "Photo ink")
        #expect(css.contains("a:link { color: rgb(232,180,101)"),
                "Photo accent on a:link (warm gold)")
    }

    // MARK: - Photo theme background-image rule

    @Test func photoThemeEmitsBackgroundImageWhenURLProvided() {
        let imgURL = URL(fileURLWithPath: "/tmp/vreader-photo-bg.jpg")
        let css = ReaderThemeV2.photo.epubOverrideCSS(
            fontSize: 18, backgroundImageURL: imgURL
        )
        #expect(css.contains("background-image: url("), "Photo emits background-image when URL passed")
        #expect(css.contains("vreader-photo-bg.jpg"), "Embeds the file URL path")
        #expect(css.contains("background-size: cover"), "Cover sizing across viewport")
        #expect(css.contains("background-attachment: fixed"), "Fixed across scroll")
    }

    @Test func photoThemeOmitsBackgroundImageWhenURLNil() {
        let css = ReaderThemeV2.photo.epubOverrideCSS(
            fontSize: 18, backgroundImageURL: nil
        )
        #expect(!css.contains("background-image: url("),
                "Photo with no URL falls back to flat alpha overlay")
    }

    @Test func nonPhotoThemesIgnoreBackgroundImageURL() {
        let imgURL = URL(fileURLWithPath: "/tmp/should-be-ignored.jpg")
        for theme in [ReaderThemeV2.paper, .sepia, .dark, .oled] {
            let css = theme.epubOverrideCSS(
                fontSize: 18, backgroundImageURL: imgURL
            )
            #expect(!css.contains("background-image: url("),
                    "\(theme.rawValue) theme must never emit background-image")
        }
    }

    // MARK: - CSS url(...) escape helper (direct)
    //
    // Codex Gate 4 round 2 (Low): test the helper directly. A test
    // against the full CSS string is fooled by `URL.absoluteString`'s
    // own percent-encoding pass — `"` gets encoded to `%22` before
    // ever reaching the helper, so a black-box test happens to pass
    // even if cssEscapeURL is deleted. Driving the helper with raw
    // strings proves the `\` → `\\` and `"` → `\"` transformations
    // happen in the right order.

    @Test func cssEscapeURL_escapesBackslash() {
        #expect(
            ReaderThemeV2.cssEscapeURL(#"a\b"#) == #"a\\b"#,
            "Backslash must be doubled for CSS string context"
        )
    }

    @Test func cssEscapeURL_escapesDoubleQuote() {
        #expect(
            ReaderThemeV2.cssEscapeURL(#"a"b"#) == #"a\"b"#,
            "Double-quote must be backslash-escaped so it can't terminate url(\"…\")"
        )
    }

    @Test func cssEscapeURL_orderingDoesNotDoubleEscape() {
        // Ensure backslash is escaped FIRST. If we escaped `"` first
        // (→ `\"`), then escaped `\` next (→ `\\\"`), the result would
        // be wrong. Correct: `\` first (a\b\"c → a\\b\\\"c) then `"`
        // (→ a\\b\\\"c with `"` already neutralised by the second pass).
        let raw = #"a\b"c"#
        let escaped = ReaderThemeV2.cssEscapeURL(raw)
        // The final string must contain exactly one `\` per source `\`
        // followed by a `\"`, never `\\\"` from double-escape.
        #expect(escaped == #"a\\b\"c"#,
                "Backslash-then-quote ordering preserves single-escape semantics")
    }

    @Test func cssEscapeURL_passthroughForCommonURLChars() {
        // Percent-encoded URL.absoluteString output (the common case)
        // contains none of the trigger characters and should round-trip
        // identical.
        let raw = "file:///tmp/some%20path/photo.jpg"
        #expect(ReaderThemeV2.cssEscapeURL(raw) == raw,
                "Already-safe URLs pass through unchanged")
    }

    @Test func photoCSSEmitsTheEscapedURLVerbatim() {
        // End-to-end: the URL.absoluteString → cssEscapeURL → CSS
        // path renders the escaped string inside `url("…")`. We
        // construct the expected blob explicitly so a regression that
        // bypassed the helper would fail this contract.
        let imgURL = URL(fileURLWithPath: "/tmp/clean.jpg")
        let css = ReaderThemeV2.photo.epubOverrideCSS(
            fontSize: 18, backgroundImageURL: imgURL
        )
        let expectedInside = ReaderThemeV2.cssEscapeURL(imgURL.absoluteString)
        #expect(css.contains("url(\"\(expectedInside)\")"),
                "Photo CSS embeds the cssEscapeURL output verbatim inside url(\"…\")")
    }

    @Test func photoCSSAcceptsBase64DataURLBackground() {
        // WI-12 / #795: EPUB Photo backgrounds are injected as base64
        // `data:` URLs — no file:// URL, so no dependency on the
        // WKWebView `allowingReadAccessTo` scope. A data URL's payload
        // characters (`;` `,` `/` `+` `=`) are none of the `\` / `"`
        // that cssEscapeURL neutralises, so it lands verbatim in url("…").
        let dataURL = URL(string: "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ==")!
        let css = ReaderThemeV2.photo.epubOverrideCSS(
            fontSize: 18, backgroundImageURL: dataURL
        )
        #expect(
            css.contains(#"background-image: url("data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ==")"#),
            "Photo EPUB CSS embeds a base64 data URL verbatim"
        )
        #expect(css.contains("background-attachment: fixed"), "Fixed across scroll")
    }

    // MARK: - Font integration (delegates to WI-1's ReaderTypography)

    @Test func epubCSSRoutesFontStackThroughTypographyRegistry() {
        let css = ReaderThemeV2.paper.epubOverrideCSS(
            fontSize: 18, fontFamily: .sourceSerif4
        )
        let expected = ReaderTypography.cssFontStack(for: .sourceSerif4)
        #expect(css.contains("font-family: \(expected)"),
                "Font stack must come from ReaderTypography (WI-1 single-source)")
    }

    @Test func epubCSSPinsFontSize() {
        let css = ReaderThemeV2.paper.epubOverrideCSS(fontSize: 22)
        #expect(css.contains("font-size: 22.0px"), "Font size pinned to caller-passed value")
    }

    @Test func epubCSSPinsLineHeight() {
        let css = ReaderThemeV2.paper.epubOverrideCSS(fontSize: 18, lineHeight: 1.8)
        #expect(css.contains("line-height: 1.80"), "Line height pinned")
    }

    // Bug #336: the #95 `text-align: justify` rule must carry hyphenation so
    // justified Latin lines break at hyphenation points instead of stretching
    // inter-word spaces (the "too many gaps between words" report). CJK is
    // unaffected (it doesn't hyphenate; justify stays clean).
    @Test func justifyRuleEnablesHyphenationForLatin() {
        let css = ReaderThemeV2.paper.epubOverrideCSS(fontSize: 18)
        #expect(css.contains("text-align: justify"))
        #expect(css.contains("-webkit-hyphens: auto"))
        #expect(css.contains("hyphens: auto"))
    }

    // MARK: - Legacy → V2 mapping

    @Test func legacyLightMapsToPaper() {
        #expect(ReaderTheme.light.asV2 == .paper)
    }

    @Test func legacySepiaMapsToSepia() {
        #expect(ReaderTheme.sepia.asV2 == .sepia)
    }

    @Test func legacyDarkMapsToDark() {
        #expect(ReaderTheme.dark.asV2 == .dark)
    }

    // MARK: - Feature #95 — justify default

    @Test func bodyProseIsJustifiedByDefault() {
        let css = normalize(ReaderThemeV2.paper.epubOverrideCSS(fontSize: 18))
        #expect(css.contains("text-align: justify !important"))
        // Scoped to prose <p>, guarded against intentional alignment. Bug #336
        // added hyphenation inside the same rule, so assert the selector + each
        // declaration rather than the exact rule body.
        #expect(css.contains("p:not([style*=\"text-align\"]):not([align]):not([class*=\"center\"]):not([class*=\"right\"]) { text-align: justify !important; -webkit-hyphens: auto; hyphens: auto; }"))
        // The justify selector is p-only — headings keep their own alignment.
        #expect(!css.contains("h1,h2,h3,h4,h5,h6 { text-align: justify"))
    }

    @Test(arguments: [ReaderThemeV2.paper, .dark, .sepia])
    func justifyAppliesAcrossThemes(_ theme: ReaderThemeV2) {
        let css = normalize(theme.epubOverrideCSS(fontSize: 18))
        #expect(css.contains("text-align: justify !important"))
    }
}
