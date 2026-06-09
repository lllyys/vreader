// Purpose: Tests for FoliateStyleMapper — pure functions that generate CSS/JS
// strings for the Foliate-js reader engine's setStyles() and setLayout() APIs.

import Testing
@testable import vreader

@Suite("FoliateStyleMapper")
struct FoliateStyleMapperTests {

    // MARK: - themeCSS: Font Size

    @Test func themeCSSIncludesFontSizeWithPxUnit() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("font-size: 18px"), "Must include font-size with px unit")
    }

    @Test func themeCSSIncludesLargeFontSize() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 32, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("font-size: 32px"), "Must handle large font size")
    }

    /// Bug #166 (partial fix): app-side `TypographySettings.fontSizeRange`
    /// upper bound raised from 32 to 64, and Foliate's own style mapper
    /// sanitizes input to `8...72` (verified by Codex audit), so 64
    /// passes through unchanged. Pin this so a future Foliate sanitizer
    /// regression that drops the upper bound below 64 surfaces here.
    @Test func themeCSSAcceptsAppMaxFontSize64() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 64, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("font-size: 64px"), "App's max font size (64pt per TypographySettings.fontSizeRange) must pass through Foliate's style mapper unchanged.")
    }

    @Test func themeCSSIncludesSmallFontSize() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 12, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("font-size: 12px"), "Must handle min font size")
    }

    // Feature #95: prose <p> justified by default, guarded against intentional alignment.
    @Test func themeCSSJustifiesProseParagraphs() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.5,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("text-align: justify !important"))
        #expect(css.contains("p:not([style*=\"text-align\"]):not([align]):not([class*=\"center\"]):not([class*=\"right\"])"))
    }

    // MARK: - themeCSS: Line Height

    @Test func themeCSSIncludesLineHeight() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("line-height: 1.6"), "Must include line-height value")
    }

    @Test func themeCSSIncludesTightLineHeight() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.0,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("line-height: 1.0"), "Must handle minimum line height")
    }

    @Test func themeCSSIncludesLooseLineHeight() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 2.0,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("line-height: 2.0"), "Must handle maximum line height")
    }

    // MARK: - themeCSS: Font Family

    @Test func themeCSSWithFontFamilyIncludesFontFamilyRule() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: "Georgia", textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("font-family:"), "Must include font-family when provided")
        #expect(css.contains("Georgia"), "Must include the font name")
    }

    @Test func themeCSSWithoutFontFamilyOmitsFontFamilyRule() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(!css.contains("font-family"), "Must omit font-family when nil")
    }

    @Test func themeCSSWithEmptyFontFamilyOmitsFontFamilyRule() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: "", textColor: nil, backgroundColor: nil
        )
        #expect(!css.contains("font-family"), "Must omit font-family when empty string")
    }

    @Test func themeCSSFontFamilyIsQuoted() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: "Georgia", textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("\"Georgia\""), "Font family name must be quoted")
    }

    // MARK: - themeCSS: Colors

    @Test func themeCSSWithColorsIncludesColorAndBackground() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: "#1a1a1a", backgroundColor: "#ffffff"
        )
        #expect(css.contains("color: #1a1a1a"), "Must include text color")
        #expect(css.contains("background: #ffffff"), "Must include background color")
    }

    @Test func themeCSSWithoutColorsOmitsColorRules() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(!css.contains("color:"), "Must omit color when nil")
        #expect(!css.contains("background:"), "Must omit background when nil")
    }

    @Test func themeCSSWithOnlyTextColorOmitsBackground() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: "#1a1a1a", backgroundColor: nil
        )
        #expect(css.contains("color: #1a1a1a"), "Must include text color")
        #expect(!css.contains("background:"), "Must omit background when nil")
    }

    @Test func themeCSSWithOnlyBackgroundOmitsTextColor() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: "#eeeded"
        )
        #expect(!css.contains("color:"), "Must omit text color when nil")
        #expect(css.contains("background: #eeeded"), "Must include background color")
    }

    // MARK: - themeCSS: !important

    @Test func themeCSSUsesImportantOnAllRules() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: "Georgia", textColor: "#1a1a1a", backgroundColor: "#ffffff"
        )
        // Count occurrences of !important — should be at least 4
        // (font-size, line-height, font-family, color, background)
        let importantCount = css.components(separatedBy: "!important").count - 1
        #expect(importantCount >= 4, "All CSS rules must use !important, found \(importantCount)")
    }

    @Test func themeCSSFontSizeHasImportant() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("font-size: 18px !important"), "font-size must have !important")
    }

    @Test func themeCSSLineHeightHasImportant() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("line-height: 1.6 !important"), "line-height must have !important")
    }

    // MARK: - themeCSS: Full Output

    @Test func themeCSSFullOutputContainsAllParts() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 20, lineHeight: 1.5,
            fontFamily: "Menlo", textColor: "#333333", backgroundColor: "#f5f5f5"
        )
        #expect(css.contains("font-size: 20px !important"))
        #expect(css.contains("line-height: 1.5 !important"))
        #expect(css.contains("\"Menlo\""))
        #expect(css.contains("font-family:"))
        #expect(css.contains("color: #333333 !important"))
        #expect(css.contains("background: #f5f5f5 !important"))
    }

    @Test func themeCSSMinimalOutputOnlyHasFontRules() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("font-size:"), "Must have font-size")
        #expect(css.contains("line-height:"), "Must have line-height")
        #expect(!css.contains("font-family"), "Must not have font-family")
        #expect(!css.contains("color:"), "Must not have color")
        #expect(!css.contains("background:"), "Must not have background")
    }

    // MARK: - themeCSS: Empty Color Handling

    @Test func themeCSSWithEmptyTextColorOmitsColorRule() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: "", backgroundColor: nil
        )
        #expect(!css.contains("color:"), "Must omit color when empty string")
    }

    @Test func themeCSSWithEmptyBackgroundColorOmitsBackgroundRule() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: ""
        )
        #expect(!css.contains("background:"), "Must omit background when empty string")
    }

    // MARK: - themeCSS: Font Size Clamping

    @Test func themeCSSClampsFontSizeBelow8() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 4, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("font-size: 8px"), "Font size below 8 must clamp to 8")
        #expect(!css.contains("font-size: 4px"), "Must not emit unclamped value")
    }

    @Test func themeCSSClampsFontSizeAbove72() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 100, lineHeight: 1.6,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("font-size: 72px"), "Font size above 72 must clamp to 72")
        #expect(!css.contains("font-size: 100px"), "Must not emit unclamped value")
    }

    // MARK: - themeCSS: Line Height Clamping

    @Test func themeCSSClampsLineHeightBelow0_8() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 0.3,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("line-height: 0.8"), "Line height below 0.8 must clamp to 0.8")
    }

    @Test func themeCSSClampsLineHeightAbove3_0() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 5.0,
            fontFamily: nil, textColor: nil, backgroundColor: nil
        )
        #expect(css.contains("line-height: 3.0"), "Line height above 3.0 must clamp to 3.0")
    }

    // MARK: - themeCSS: Font Family Sanitization

    @Test func themeCSSFontFamilyStripsInjection() {
        let css = FoliateStyleMapper.themeCSS(
            fontSize: 18, lineHeight: 1.6,
            fontFamily: "Evil\"; } body { display: none; } .x { \"", textColor: nil, backgroundColor: nil
        )
        // escapeForCSS strips quotes, semicolons, braces, backslashes, and newlines.
        // The injection can't break out because there are no unescaped quotes, semicolons,
        // or braces in the sanitized output. Words like "display" may survive as harmless
        // text trapped inside the quoted font-family value.
        //
        // Security invariant (robust to future legitimate rule additions —
        // Gate-4 audit Low): assert the injection did NOT break out of the
        // quoted font-family value, WITHOUT coupling to the exact number of
        // rule blocks the mapper emits. The safety comes from `escapeForCSS`
        // stripping `" ' \ ; { } \n \r`, so:
        //  (a) the font-family declaration is still emitted (sanitized), and
        //  (b) the malicious `}` that would close the font-family rule and
        //      `{` that would open the injected `body { display: none }` block
        //      are gone — so no `body { display` / `.x {` block can appear.
        #expect(
            css.contains("font-family:"),
            "The font-family rule must still be emitted with the sanitized value"
        )
        // The injected payload's WORDS (`display`, `none`, `body`) survive only
        // as inert text inside the quoted font-family value — that is the
        // documented harmless behavior, so we do NOT assert their absence.
        // What must NOT appear is the STRUCTURAL breakout: a `}` closing the
        // font-family rule followed by a new selector `{`. `escapeForCSS`
        // strips both braces and the `;`, so no `} body {` / `}.x{` can form.
        #expect(
            !css.contains("} body {") && !css.contains("}body{"),
            "Injection must not break out into a new `body` rule block"
        )
        #expect(
            !css.contains("} .x {") && !css.contains("}.x{"),
            "Injection must not break out into the trailing `.x` rule block"
        )
        // The number of `{` equals the number of `}` — every rule block the
        // mapper opens, it closes; the injection's unbalanced brace was
        // stripped, so the structure stays balanced regardless of how many
        // legitimate rules the mapper emits.
        let openBraces = css.filter { $0 == "{" }.count
        let closeBraces = css.filter { $0 == "}" }.count
        #expect(
            openBraces == closeBraces,
            "Brace structure must stay balanced — injection added no unbalanced brace (open=\(openBraces), close=\(closeBraces))"
        )
    }

    // MARK: - layoutJS: Flow Sanitization

    @Test func layoutJSSanitizesInvalidFlow() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "invalid'; alert('xss", margin: 48, maxInlineSize: 720, maxColumnCount: 2
        )
        #expect(js.contains("flow: 'paginated'"), "Invalid flow must default to paginated")
        #expect(!js.contains("alert"), "Injection attempt must be blocked")
    }

    // MARK: - layoutJS: Negative Value Clamping

    @Test func layoutJSClampsNegativeMargin() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: -10, maxInlineSize: 720, maxColumnCount: 2
        )
        #expect(js.contains("margin: 0"), "Negative margin must clamp to 0")
    }

    @Test func layoutJSClampsNegativeMaxInlineSize() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: -100, maxColumnCount: 2
        )
        #expect(js.contains("maxInlineSize: 0"), "Negative maxInlineSize must clamp to 0")
    }

    @Test func layoutJSClampsNegativeMaxColumnCount() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: 720, maxColumnCount: -1
        )
        #expect(js.contains("maxColumnCount: 1"), "Negative maxColumnCount must clamp to 1 (minimum valid)")
    }

    // MARK: - layoutJS: Flow

    @Test func layoutJSIncludesFlowValue() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: 720, maxColumnCount: 2
        )
        #expect(js.contains("paginated"), "Must include flow value")
    }

    @Test func layoutJSWithScrolledFlow() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "scrolled", margin: 48, maxInlineSize: 720, maxColumnCount: 1
        )
        #expect(js.contains("scrolled"), "Must include scrolled flow value")
    }

    @Test func layoutJSWithPaginatedFlow() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: 720, maxColumnCount: 2
        )
        #expect(js.contains("paginated"), "Must include paginated flow value")
    }

    // MARK: - layoutJS: Margin

    @Test func layoutJSIncludesMarginValue() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: 720, maxColumnCount: 2
        )
        #expect(js.contains("48"), "Must include margin value")
    }

    @Test func layoutJSWithZeroMargin() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 0, maxInlineSize: 720, maxColumnCount: 2
        )
        #expect(js.contains("margin: 0"), "Must handle zero margin")
    }

    // MARK: - layoutJS: Max Inline Size

    @Test func layoutJSIncludesMaxInlineSize() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: 720, maxColumnCount: 2
        )
        #expect(js.contains("720"), "Must include maxInlineSize value")
    }

    @Test func layoutJSIncludesLargeMaxInlineSize() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: 1200, maxColumnCount: 2
        )
        #expect(js.contains("1200"), "Must handle large maxInlineSize")
    }

    // MARK: - layoutJS: Max Column Count

    @Test func layoutJSIncludesMaxColumnCount() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: 720, maxColumnCount: 2
        )
        #expect(js.contains("maxColumnCount: 2"), "Must include maxColumnCount value")
    }

    @Test func layoutJSSingleColumn() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: 720, maxColumnCount: 1
        )
        #expect(js.contains("maxColumnCount: 1"), "Must handle single column")
    }

    // MARK: - layoutJS: Valid JS

    @Test func layoutJSContainsReaderAPISetLayout() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: 720, maxColumnCount: 2
        )
        #expect(js.contains("readerAPI.setLayout("), "Must call readerAPI.setLayout")
    }

    @Test func layoutJSIsCompleteFunctionCall() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: 720, maxColumnCount: 2
        )
        #expect(js.hasPrefix("readerAPI.setLayout("), "Must start with readerAPI.setLayout(")
        #expect(js.hasSuffix(")"), "Must end with closing paren")
    }

    @Test func layoutJSFlowValueIsQuoted() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "paginated", margin: 48, maxInlineSize: 720, maxColumnCount: 2
        )
        #expect(
            js.contains("flow: 'paginated'") || js.contains("flow: \"paginated\""),
            "Flow value must be quoted as a JS string"
        )
    }

    // MARK: - layoutJS: Full Output

    @Test func layoutJSFullOutputContainsAllFields() {
        let js = FoliateStyleMapper.layoutJS(
            flow: "scrolled", margin: 24, maxInlineSize: 600, maxColumnCount: 1
        )
        #expect(js.contains("flow:"), "Must include flow field")
        #expect(js.contains("margin:"), "Must include margin field")
        #expect(js.contains("maxInlineSize:"), "Must include maxInlineSize field")
        #expect(js.contains("maxColumnCount:"), "Must include maxColumnCount field")
        #expect(js.contains("scrolled"), "Must include scrolled flow value")
        #expect(js.contains("24"), "Must include margin 24")
        #expect(js.contains("600"), "Must include maxInlineSize 600")
        #expect(js.contains("maxColumnCount: 1"), "Must include maxColumnCount 1")
    }
}
