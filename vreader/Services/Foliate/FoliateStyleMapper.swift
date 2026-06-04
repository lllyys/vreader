// Purpose: Pure functions that generate CSS and JavaScript strings for
// the Foliate-js reader engine's setStyles() and setLayout() APIs.
// Maps VReader reader settings to Foliate-js configuration.
//
// Key decisions:
// - Enum with static methods (no instances needed for pure functions).
// - All CSS rules use !important to override book-embedded styles.
// - Optional parameters (fontFamily, colors) are omitted from output when nil/empty.
// - layoutJS generates a complete readerAPI.setLayout() call string.
// - All values are sanitized via FoliateJSEscaper before interpolation.
// - Numeric values are clamped to safe ranges.
//
// @coordinates-with: ReaderSettingsStore.swift, ReaderTheme.swift, FoliateViewBridge.swift,
//   FoliateJSEscaper.swift

import Foundation

/// Generates CSS and JavaScript configuration strings for Foliate-js.
enum FoliateStyleMapper {

    /// Generate CSS string for Foliate-js setStyles() from reader settings.
    ///
    /// - Parameters:
    ///   - fontSize: Font size in points (will be emitted as px).
    ///   - lineHeight: Line height multiplier (e.g. 1.6).
    ///   - fontFamily: Optional font family name. Omitted from CSS when nil or empty.
    ///   - textColor: Optional CSS color string (e.g. "#1a1a1a"). Omitted when nil.
    ///   - backgroundColor: Optional CSS color string (e.g. "#ffffff"). Omitted when nil.
    ///   - accentColor: Optional CSS color string for the feature #68
    ///     chapter-start drop-cap (`body > p:first-of-type::first-letter`).
    ///     Omitted when nil/empty or when `sanitizeCSSColor` rejects it.
    /// - Returns: A CSS string suitable for Foliate-js setStyles().
    static func themeCSS(
        fontSize: Int,
        lineHeight: Double,
        fontFamily: String?,
        textColor: String?,
        backgroundColor: String?,
        accentColor: String? = nil
    ) -> String {
        let clampedSize = FoliateJSEscaper.clampFontSize(fontSize)
        let clampedHeight = FoliateJSEscaper.clampLineHeight(lineHeight)
        var rules: [String] = []

        // Font size and line height are always included. Bug #261: pin BOTH
        // `html` and `body` (not `body` alone) so a book's `rem`-based CSS
        // resolves against the calibrated size, not the 16px UA root default.
        // Mirrors the EPUB path's `html, body { font-size: <n>px }` base rule
        // (`ReaderThemeV2+EPUBCSS.swift`).
        rules.append("html, body { font-size: \(clampedSize)px !important; line-height: \(formatLineHeight(clampedHeight)) !important; }")

        // Bug #261: cascade-flatten. AZW3/MOBI (Kindle) books frequently carry
        // their own `em`/`%`-based font-size CSS on text containers, which
        // compounds against the injected `body` base — device-measured 31px
        // body → 35.65px paragraphs at unified 28 with a book `p{font-size:
        // 1.15em}`. Forcing the common text containers to `font-size: inherit`
        // makes them resolve to the inherited body px instead of compounding,
        // so AZW3/MOBI body text renders at the same flat per-format size EPUB
        // already delivers (bug #57 / feature #70). The base list mirrors EPUB
        // (`ReaderThemeV2+EPUBCSS.swift`); Kindle KFX/MOBI output additionally
        // wraps content in HTML5 semantic containers (`section`, `article`,
        // `figure`, etc.) that often carry their own `em` font-size, so those
        // are added here to widen compounding immunity beyond EPUB's list
        // (Gate-4 audit Medium). `color` is deliberately omitted from THIS
        // (unconditional) rule — the descendant color reset for AZW/MOBI
        // theme-color parity (feature #93) lives in the `textColor` branch
        // below, so it is emitted only when a theme color is actually applied
        // (resetting color here, with no theme ink to inherit, would overreach
        // the font-size-only path). `line-height: inherit` keeps descendant
        // line-height from fighting the body value.
        rules.append(
            "p, div, span, li, td, th, dd, dt, blockquote, figcaption, "
            + "section, article, aside, main, header, footer, figure { "
            + "font-size: inherit !important; line-height: inherit !important; }"
        )

        // Bug #261: headings revert to the UA-default proportional scale
        // (matching EPUB) so they still scale WITH the body size but do not
        // compound off the book's arbitrary base.
        rules.append("h1,h2,h3,h4,h5,h6 { font-size: revert !important; }")

        // Font family only when provided and non-empty; sanitized for CSS.
        if let family = fontFamily, !family.isEmpty {
            let safeFamily = FoliateJSEscaper.escapeForCSS(family)
            rules.append("body { font-family: \"\(safeFamily)\" !important; }")
        }

        // Text color — omitted when nil or empty.
        if let color = FoliateJSEscaper.sanitizeCSSColor(textColor) {
            rules.append("body { color: \(color) !important; }")

            // Feature #93: AZW3/MOBI theme-color parity. `body { color }` alone
            // is not enough — a publisher's per-element ink (`<span style>`,
            // legacy `<font color>`, heading colors, container colors) survives
            // the body rule and stays dark on a dark theme. Mirror EPUB's
            // `epubOverrideCSS` descendant `color: inherit !important` reset so
            // descendant ink resolves to the inherited (theme) body color. The
            // selector list mirrors the font-size flatten rule above PLUS
            // headings `h1`-`h6` (Gate-4: publisher chapter-title colors must
            // also yield, matching EPUB's `h1...h6 { color }`) and legacy
            // `font` (Kindle/MOBI content frequently uses `<font color>`).
            // Emitted ONLY when a text color is applied, so the font-size-only
            // path (feature #70, nil textColor) is unchanged.
            rules.append(
                "h1, h2, h3, h4, h5, h6, p, div, span, li, td, th, dd, dt, "
                + "blockquote, figcaption, section, article, aside, main, "
                + "header, footer, figure, font { color: inherit !important; }"
            )
        }

        // Background color — omitted when nil or empty.
        if let bg = FoliateJSEscaper.sanitizeCSSColor(backgroundColor) {
            rules.append("body { background: \(bg) !important; }")
        }

        // Feature #68: chapter-start drop-cap. The accent is sanitized
        // through `FoliateJSEscaper.sanitizeCSSColor` exactly like the
        // other colors — a value with injection characters is rejected
        // and the rule is omitted. `body > p:first-of-type` (child
        // combinator) targets the first top-level <p> directly under
        // <body>; a section-wrapped first <p> is safely missed.
        if let accent = FoliateJSEscaper.sanitizeCSSColor(accentColor) {
            rules.append(dropCapRule(accent: accent))
        }

        return rules.joined(separator: "\n")
    }

    /// Generate a JavaScript call string for Foliate-js setLayout().
    ///
    /// - Parameters:
    ///   - flow: Layout flow mode — "paginated" or "scrolled".
    ///   - margin: Margin in pixels.
    ///   - maxInlineSize: Maximum content width in pixels.
    ///   - maxColumnCount: Number of columns (1 or 2).
    /// - Returns: A JavaScript string calling `readerAPI.setLayout({...})`.
    static func layoutJS(
        flow: String,
        margin: Int,
        maxInlineSize: Int,
        maxColumnCount: Int
    ) -> String {
        let safeFlow = FoliateJSEscaper.sanitizeFlow(flow)
        let safeMargin = FoliateJSEscaper.clampNonNegative(margin)
        let safeInlineSize = FoliateJSEscaper.clampNonNegative(maxInlineSize)
        let safeColumnCount = min(max(maxColumnCount, 1), 2)
        return "readerAPI.setLayout({flow: '\(safeFlow)', margin: \(safeMargin), maxInlineSize: \(safeInlineSize), maxColumnCount: \(safeColumnCount)})"
    }

    // MARK: - Private

    /// Format line height to one decimal place for consistent CSS output.
    private static func formatLineHeight(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Feature #68: builds the chapter-start drop-cap rule for Foliate
    /// `setStyles`. Same selector + declarations as the EPUB path
    /// (`ReaderThemeV2+EPUBCSS.dropCapCSSRule`); `accent` has already
    /// passed `FoliateJSEscaper.sanitizeCSSColor`. Every declaration
    /// carries `!important`, matching this file's stated convention.
    private static func dropCapRule(accent: String) -> String {
        let serifStack = "'Source Serif 4', Georgia, 'Times New Roman', serif"
        return "body > p:first-of-type::first-letter { "
            + "font-family: \(serifStack) !important; "
            + "font-size: \(ChapterStartTypography.dropCapCSSFontSizeEm) !important; "
            + "font-weight: 600 !important; "
            + "line-height: 0.85 !important; "
            + "float: left !important; "
            + "margin-right: 0.06em !important; "
            + "margin-top: 0.05em !important; "
            + "color: \(accent) !important; }"
    }
}
