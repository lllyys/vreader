// Purpose: Feature #60 WI-4 — EPUB CSS injection driven by the V2
// token surface. Emits the `<style id="vreader-theme">` blob that
// `EPUBReaderContainerView` threads into `EPUBWebViewBridge`.
//
// The style-element id deliberately matches the legacy injection
// path's id (`vreader-theme`) because `EPUBWebViewBridgeJS.
// injectThemeCSSJS` strips the wrapper and re-injects under a fixed
// id — there is no runtime caller that needs to distinguish V2 from
// legacy CSS, so introducing a second id would only confuse future
// readers without buying anything.
//
// Replaces the legacy `ReaderTheme.epubOverrideCSS` call path for new
// EPUB renders. The legacy helper is left in place for tests and any
// surface still on the 3-theme enum until WI-5+ migrates them.
//
// Token mapping (per design bundle `dev-docs/designs/vreader-fidelity-v1/
// project/vreader-themes.jsx`):
//   - `html { background-color: bg }` — outer page-frame tint.
//   - `body { background-color: paper }` — text-container surface,
//     gives the paper-stack effect distinct from the outer frame.
//     Photo theme's paper is alpha-blended so the photo shows through.
//   - `color: ink` — primary text.
//   - `a:link { color: accent }` — single restrained accent across
//     chrome and links per the three-stop oxblood family.
//   - `a:visited { color: sub }` — secondary token.
//   - `hr, td, th { border: rule }` — hairline dividers, alpha-blended
//     over ink so they render correctly across paper tints.
//
// Photo theme: when a `backgroundImageURL` is passed in, also emits
// `html { background-image: url(...) }` plus cover/fixed sizing so the
// photo fills the viewport and stays fixed across scroll. Without a
// URL, falls back to the flat outer bg + alpha-blended paper overlay
// so the theme is still legible.
//
// @coordinates-with: ReaderThemeV2.swift (token surface),
//   ReaderTypography.swift (WI-1 font registry — single source for
//   the CSS font-family stack), EPUBReaderContainerView.swift (the
//   WI-4 call site that threads this CSS into the WKWebView).

import Foundation
#if canImport(UIKit)
import UIKit

extension ReaderThemeV2 {
    /// Generates the `<style id="vreader-theme">` blob applied to
    /// EPUB content via `EPUBWebViewBridge`. The id deliberately
    /// matches the legacy injection path (see file header for why).
    ///
    /// - Parameters:
    ///   - fontSize: caller-passed CSS pixel size for body text.
    ///   - lineHeight: multiplier (1.6 by default; matches legacy).
    ///   - letterSpacing: em offset; 0 means `letter-spacing: normal`.
    ///   - fontFamily: drives the CSS font stack via
    ///     `ReaderTypography.cssFontStack(for:)` so the stack
    ///     definitions live in one place.
    ///   - backgroundImageURL: Photo theme only. When non-nil and
    ///     `usesBackgroundImage` is true, emits an additional
    ///     `html { background-image: url(...) }` rule. For all other
    ///     themes the URL is ignored; passing one does not change the
    ///     output. Non-Photo themes never emit a background-image rule.
    func epubOverrideCSS(
        fontSize: CGFloat,
        lineHeight: CGFloat = 1.6,
        letterSpacing: CGFloat = 0,
        fontFamily: ReaderFontFamily = .system,
        backgroundImageURL: URL? = nil
    ) -> String {
        let outerBG = Self.cssColor(self.backgroundColor)
        let paperBG = Self.cssColor(self.paperColor)
        let ink = Self.cssColor(self.inkColor)
        let sub = Self.cssColor(self.subColor)
        let rule = Self.cssColor(self.ruleColor)
        let accent = Self.cssColor(self.accentColor)

        let size = String(format: "%.1f", fontSize)
        let lh = String(format: "%.2f", lineHeight)
        let ls = letterSpacing > 0
            ? String(format: "%.2fem", letterSpacing)
            : "normal"
        let fontStack = ReaderTypography.cssFontStack(for: fontFamily)

        let imageRule = Self.backgroundImageRule(
            for: self, url: backgroundImageURL, outerBG: outerBG
        )

        // Feature #68: chapter-start drop-cap. `body > p:first-of-type`
        // (child combinator) targets the first top-level <p> directly
        // under <body> — exactly one drop-cap for the common flat-<p>
        // EPUB shape; a section-wrapped first <p> is safely missed (no
        // wrong drop-cap). `accent` is the theme's oxblood token,
        // already computed above. The book's own <h1>..<h6> rule is
        // untouched — no VReader heading is injected (no duplicate).
        let dropCapRule = Self.dropCapCSSRule(accent: accent)

        // The style-id is "vreader-theme" (not "-v2") because
        // `EPUBWebViewBridgeJS.injectThemeCSSJS` extracts the inner CSS
        // and reinserts it under the fixed id "vreader-theme" so a
        // theme switch can locate-and-replace the previous element.
        // Emitting "-v2" here would be misleading documentation.
        return """
        <style id="vreader-theme">\
        html { \
          background-color: \(outerBG) !important; \
        }\
        \(imageRule)\
        html, body { \
          color: \(ink) !important; \
          font-size: \(size)px !important; \
          font-family: \(fontStack) !important; \
          line-height: \(lh) !important; \
          letter-spacing: \(ls) !important; \
          -webkit-text-size-adjust: 100%; \
          text-rendering: optimizeLegibility; \
          word-break: break-word; \
          overflow-wrap: break-word; \
        }\
        body { \
          background-color: \(paperBG) !important; \
          padding: 2em 16px !important; \
          margin: 0 !important; \
        }\
        p, div, span, li, td, th, dd, dt, blockquote, figcaption, section, article, aside, main, header, footer, figure, font { \
          font-size: inherit !important; \
          line-height: inherit !important; \
          color: inherit !important; \
        }\
        h1,h2,h3,h4,h5,h6 { \
          font-size: revert !important; \
          line-height: 1.3 !important; \
          color: \(ink) !important; \
        }\
        body * { \
          font-family: inherit !important; \
        }\
        pre, code, samp, kbd, pre *, code *, samp *, kbd * { \
          font-family: ui-monospace, 'SF Mono', Menlo, 'Courier New', monospace !important; \
          font-size: 0.85em !important; \
          line-height: 1.45 !important; \
          white-space: pre-wrap !important; \
          word-break: break-all !important; \
        }\
        a:link { color: \(accent) !important; text-decoration: underline; }\
        a:visited { color: \(sub) !important; text-decoration: underline; }\
        \(dropCapRule)\
        img, svg, video { \
          max-width: 100% !important; \
          height: auto !important; \
          object-fit: contain; \
        }\
        table { \
          max-width: 100% !important; \
          border-collapse: collapse; \
          font-size: 0.9em !important; \
          overflow-x: auto; \
          display: block; \
        }\
        td, th { \
          padding: 4px 8px; \
          border: 1px solid \(rule); \
        }\
        hr { \
          border: none; \
          border-top: 1px solid \(rule); \
          margin: 1em 0; \
        }\
        ::selection { \
          background-color: \(accent); \
          color: \(paperBG); \
        }\
        \(Self.bilingualCSSRule(accent: accent, sub: sub))\
        </style>
        """
    }

    /// Feature #56 WI-10: CSS for the bilingual interlinear blocks
    /// injected by `EPUBBilingualJS.bilingualInjectJS`. Pinned to the
    /// design's spec (`vreader-bilingual.jsx`):
    ///   - 0.88× the body font size
    ///   - sub-text color
    ///   - line-height 1.55
    ///   - 0.7em left padding + 2px solid accent (33% alpha) left border
    ///   - 6px top margin from the source paragraph
    ///   - user-select: none so the selection / highlight pipelines
    ///     never target translation blocks
    /// The accent border colour uses the theme's full accent — the
    /// 33% alpha mentioned in the design is approximated by appending
    /// `55` (≈ 33% in hex) when the accent is in hex. Since our cssColor
    /// helper emits hex tokens, the concatenation is safe; non-hex
    /// fallbacks degrade to the solid accent (still readable).
    /// Bug #304: the `.vreader-bilingual` interlinear rule for THIS theme, for
    /// injection into the modern engines that don't thread `epubOverrideCSS` —
    /// the Readium spine (via `bilingualInjectJS`'s `<style>`) and the Foliate
    /// `setStyles` pipeline. Harmless when no bilingual content exists (the
    /// selector matches nothing). Uses the same accent/sub tokens as
    /// `epubOverrideCSS`, so all three engines render the interlinear block
    /// identically.
    func bilingualBlockCSSRule() -> String {
        Self.bilingualCSSRule(
            accent: Self.cssColor(self.accentColor),
            sub: Self.cssColor(self.subColor))
    }

    /// Feature #77: the inline bilingual LOADING shimmer rule + `@keyframes vreaderBilingualShim`.
    /// Shared by all three bilingual engines (Readium / legacy EPUB / Foliate) so a
    /// `.vreader-bilingual.vreader-bilingual-loading` decoration renders the design's
    /// animated shimmer bars (`BilingualLoadingSlot`, #1024 §L) while a unit is being
    /// fetched, distinct from the offline (dashed) state. Theme-aware gradient.
    func bilingualLoadingCSSRule() -> String {
        Self.bilingualLoadingCSSRule(isDark: self.isDark)
    }

    static func bilingualLoadingCSSRule(isDark: Bool) -> String {
        // The design's theme-aware shimmer gradient (4% → 12% → 4%).
        let gradient = isDark
            ? "linear-gradient(90deg, rgba(255,255,255,0.04), rgba(255,255,255,0.12), rgba(255,255,255,0.04))"
            : "linear-gradient(90deg, rgba(20,14,4,0.04), rgba(20,14,4,0.10), rgba(20,14,4,0.04))"
        return """
        @keyframes vreaderBilingualShim { 0% { background-position: 100% 0; } 100% { background-position: -100% 0; } } \
        .vreader-bilingual.vreader-bilingual-loading[data-vreader-decoration] { \
          border-left-color: transparent !important; \
        } \
        .vreader-bilingual-loading .vreader-shimmer-bar { \
          height: 0.62em !important; \
          margin: 0 0 5px 0 !important; \
          border-radius: 3px !important; \
          background: \(gradient) !important; \
          background-size: 200% 100% !important; \
          animation: vreaderBilingualShim 1.4s ease-in-out infinite !important; \
        } \
        .vreader-bilingual-loading .vreader-shimmer-bar:last-child { margin-bottom: 0 !important; }
        """
    }

    private static func bilingualCSSRule(accent: String, sub: String) -> String {
        // Use a solid 2px border in the accent token; a translucent
        // overlay would require parsing rgb()/hex which is outside
        // this PR's scope. The pin in `EPUBBilingualJSTests` checks
        // the inject JS emits user-select rules; this CSS rule
        // controls the visual styling.
        return """
        .vreader-bilingual[data-vreader-decoration] { \
          font-size: 0.88em !important; \
          line-height: 1.55 !important; \
          color: \(sub) !important; \
          margin: 6px 0 0 0 !important; \
          padding: 0 0 0 0.7em !important; \
          border-left: 2px solid \(accent) !important; \
          user-select: none !important; \
          -webkit-user-select: none !important; \
        }
        """
    }

    // MARK: - Helpers

    /// Feature #68: builds the chapter-start drop-cap CSS rule appended
    /// to the EPUB override blob. The selector `body > p:first-of-type::
    /// first-letter` uses the child combinator so it matches the first
    /// `<p>` that is a *direct* child of `<body>` — exactly one drop-cap
    /// for the flat-top-level-`<p>` EPUB shape. A `<p>` nested inside a
    /// section wrapper is not matched (a safe miss — no wrong drop-cap).
    /// Declarations mirror the design (`vreader-reader.jsx:383-390`) and
    /// the `ChapterStartTypography` constants; `accent` is the theme's
    /// oxblood token.
    private static func dropCapCSSRule(accent: String) -> String {
        let serifStack = ReaderTypography.cssFontStack(for: .sourceSerif4)
        return """
        body > p:first-of-type::first-letter { \
          font-family: \(serifStack) !important; \
          font-size: \(ChapterStartTypography.dropCapCSSFontSizeEm) !important; \
          font-weight: 600 !important; \
          line-height: 0.85 !important; \
          float: left !important; \
          margin-right: 0.06em !important; \
          margin-top: 0.05em !important; \
          color: \(accent) !important; \
        }
        """
    }

    /// Photo-only: emits the `html { background-image: ... }` rule when
    /// the caller supplied a URL. Returns an empty string for all other
    /// theme/URL combinations so the parent CSS stays untouched.
    ///
    /// The URL is taken from `URL.absoluteString` (percent-encoded for
    /// file:// URLs) and then run through `cssEscapeURL` to neutralise
    /// the two characters that can still break out of the `url("…")`
    /// context: `\` and `"`. `outerBG` is kept as a fallback so a
    /// slow-loading or missing image still has a visible background.
    ///
    /// **Caller note**: `EPUBReaderContainerView` (feature #60 WI-12,
    /// GH #795) supplies a base64 `data:` URL from
    /// `ThemeBackgroundStore.backgroundImageDataURL`, not a `file://`
    /// URL. A `data:` URL carries the image bytes inline, so it needs no
    /// WKWebView `allowingReadAccessTo` grant — a `file://` URL into
    /// `ThemeBackgroundStore` (Application Support) would sit outside the
    /// EPUB extraction directory the bridge scopes access to, and
    /// WKWebView would refuse it. This rule is URL-shape agnostic: any
    /// non-nil URL on the Photo theme emits the background-image rule.
    private static func backgroundImageRule(
        for theme: ReaderThemeV2, url: URL?, outerBG: String
    ) -> String {
        guard theme.usesBackgroundImage, let url else { return "" }
        let safeURL = cssEscapeURL(url.absoluteString)
        return """
        html { \
          background-image: url("\(safeURL)") !important; \
          background-color: \(outerBG) !important; \
          background-size: cover !important; \
          background-position: center !important; \
          background-attachment: fixed !important; \
          background-repeat: no-repeat !important; \
        }
        """
    }

    /// Escapes the two characters that can break out of CSS
    /// `url("…")` quoting: backslash (`\`) and the double-quote (`"`).
    /// Other unsafe characters are typically already percent-encoded
    /// in `URL.absoluteString` for file:// URLs. Order matters:
    /// escape the backslash first so a subsequently-inserted `\"` is
    /// not itself escaped again.
    ///
    /// `internal` (not `private`) so unit tests in `vreaderTests` can
    /// exercise the helper directly — a black-box test through the
    /// CSS string is fooled by URL's own percent-encoding pass.
    static func cssEscapeURL(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Feature #93: theme colors as CSS strings (Foliate AZW3/MOBI parity)

    /// The theme's text-container surface as a CSS color string (`rgb(...)`),
    /// for the Foliate book iframe `body { background }`. Mirrors the color
    /// EPUB paints onto `body { background-color }` in `epubOverrideCSS`.
    var paperColorCSS: String { Self.cssColor(self.paperColor) }

    /// The theme's primary body-text color as a CSS color string. Mirrors
    /// EPUB's `color: ink`.
    var inkColorCSS: String { Self.cssColor(self.inkColor) }

    /// Renders a UIColor as a CSS `rgb(...)` or `rgba(...)` string,
    /// preserving the alpha channel that the design tokens encode on
    /// `paperColor` / `subColor` / `ruleColor`. Opaque colors emit
    /// `rgb(...)` for parity with legacy `ReaderTheme.cssColor` so
    /// existing CSS-substring assertions in other tests don't break.
    private static func cssColor(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let R = Int((r * 255).rounded())
        let G = Int((g * 255).rounded())
        let B = Int((b * 255).rounded())
        if a >= 0.999 {
            return "rgb(\(R),\(G),\(B))"
        }
        return String(format: "rgba(%d,%d,%d,%.2f)", R, G, B, Double(a))
    }
}

#endif
