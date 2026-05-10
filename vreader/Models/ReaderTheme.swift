// Purpose: Reader theme enum defining background, text, and secondary text colors.
// Each theme provides WCAG AA-compliant color pairs for reading content.
//
// Key decisions:
// - Three themes: light (default), sepia (warm), dark.
// - Codable + RawRepresentable for @AppStorage compatibility.
// - Uses static UIColor instances (not dynamic/semantic) so themes are fully controlled.
// - WCAG AA: primary text >= 4.5:1, secondary text >= 3.0:1 contrast ratio.
//
// @coordinates-with: TypographySettings.swift, ReaderSettingsStore.swift

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Reader color theme.
enum ReaderTheme: String, Codable, CaseIterable, Sendable {
    case light
    case sepia
    case dark

    /// The default theme for new users.
    static var `default`: ReaderTheme { .light }

    #if canImport(UIKit)
    // MARK: - Cached Color Values

    private static let lightBg = UIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
    private static let sepiaBg = UIColor(red: 0.96, green: 0.93, blue: 0.87, alpha: 1.0)
    private static let darkBg = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)

    private static let lightText = UIColor(red: 0.10, green: 0.10, blue: 0.10, alpha: 1.0)
    private static let sepiaText = UIColor(red: 0.23, green: 0.17, blue: 0.09, alpha: 1.0)
    private static let darkText = UIColor(red: 0.92, green: 0.92, blue: 0.93, alpha: 1.0)

    private static let lightSecondary = UIColor(red: 0.40, green: 0.40, blue: 0.40, alpha: 1.0)
    private static let sepiaSecondary = UIColor(red: 0.45, green: 0.38, blue: 0.28, alpha: 1.0)
    private static let darkSecondary = UIColor(red: 0.60, green: 0.60, blue: 0.62, alpha: 1.0)

    /// Background color for the reading area.
    var backgroundColor: UIColor {
        switch self {
        case .light: return Self.lightBg
        case .sepia: return Self.sepiaBg
        case .dark: return Self.darkBg
        }
    }

    /// Primary text color.
    var textColor: UIColor {
        switch self {
        case .light: return Self.lightText
        case .sepia: return Self.sepiaText
        case .dark: return Self.darkText
        }
    }

    /// Secondary/muted text color (for metadata, timestamps, etc.).
    var secondaryTextColor: UIColor {
        switch self {
        case .light: return Self.lightSecondary
        case .sepia: return Self.sepiaSecondary
        case .dark: return Self.darkSecondary
        }
    }

    /// Generates a `<style>` tag with CSS overrides for EPUB content rendering.
    /// Injected into WKWebView to apply the reader theme to XHTML content.
    ///
    /// Issue 10: Forces an explicit allowlist of body text elements
    /// (`p, div, span, li, td, th, dd, dt, blockquote, figcaption`) to inherit
    /// the user-chosen font size with `!important`, beating per-element rules
    /// from book stylesheets. Headings (`h1`-`h6`) keep their relative sizing
    /// via `font-size: revert !important`. `pre`/`code`/`samp`/`kbd` keep their
    /// browser-default monospace font for semantic correctness.
    ///
    /// Bug #168: `fontFamily` is injected on `html, body`, then forced on
    /// every descendant via `body * { font-family: inherit !important; }` so
    /// per-element book-CSS declarations (`p { font-family: ... }`, attribute
    /// selectors, etc.) can't beat the user's pick. Inline
    /// `style="font-family: ... !important"` declarations still win because
    /// inline author-important has higher specificity than stylesheet rules,
    /// and `::before`/`::after` pseudo-elements are not targeted by this
    /// sweep — both are rare in real EPUBs and accepted as residual gaps.
    /// `pre`/`code`/`samp`/`kbd` and their descendants are intentionally
    /// pinned to a semantic monospace stack (`ui-monospace, 'SF Mono', Menlo,
    /// 'Courier New', monospace`) so code blocks stay legible regardless of
    /// body-font choice. The CJK fallback is automatic: Latin-only faces
    /// (Georgia, Menlo, etc.) have no CJK glyphs, so the platform falls
    /// through to the system CJK font (PingFang SC / Hiragino).
    func epubOverrideCSS(
        fontSize: CGFloat,
        lineHeight: CGFloat = 1.6,
        letterSpacing: CGFloat = 0,
        fontFamily: ReaderFontFamily = .system
    ) -> String {
        let bg = cssColor(backgroundColor)
        let fg = cssColor(textColor)
        let secondary = cssColor(secondaryTextColor)
        let size = String(format: "%.1f", fontSize)
        let lh = String(format: "%.2f", lineHeight)
        let ls = letterSpacing > 0 ? String(format: "%.2fem", letterSpacing) : "normal"
        let linkColor = self == .dark ? "rgb(120,170,255)" : "rgb(0,90,180)"
        let fontStack = Self.cssFontStack(for: fontFamily)
        return """
        <style id="vreader-theme">\
        html, body { \
          background-color: \(bg) !important; \
          color: \(fg) !important; \
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
          padding: 0 16px !important; \
          margin: 0 !important; \
        }\
        p, div, span, li, td, th, dd, dt, blockquote, figcaption { \
          font-size: inherit !important; \
          line-height: inherit !important; \
          color: inherit !important; \
        }\
        h1,h2,h3,h4,h5,h6 { \
          font-size: revert !important; \
          line-height: 1.3 !important; \
          color: \(fg) !important; \
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
        a:link { color: \(linkColor) !important; text-decoration: underline; }\
        a:visited { color: \(secondary) !important; text-decoration: underline; }\
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
          border: 1px solid \(secondary); \
        }\
        hr { \
          border: none; \
          border-top: 1px solid \(secondary); \
          margin: 1em 0; \
        }\
        ::selection { \
          background-color: rgba(0,102,204,0.3); \
        }\
        </style>
        """
    }

    /// CSS `font-family` stack for a given `ReaderFontFamily`.
    ///
    /// Each stack ends with the appropriate generic family so the platform can
    /// fall back gracefully. CJK glyphs naturally fall through to the system
    /// CJK font (PingFang SC / Hiragino) because Georgia / Menlo / etc. carry
    /// only Latin coverage.
    fileprivate static func cssFontStack(for family: ReaderFontFamily) -> String {
        switch family {
        case .system:
            return "-apple-system, system-ui, sans-serif"
        case .serif:
            return "Georgia, 'Times New Roman', serif"
        case .monospace:
            return "'SF Mono', Menlo, 'Courier New', monospace"
        }
    }

    /// Converts a UIColor to a CSS rgb() string.
    private func cssColor(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)))"
    }

    /// Preferred color scheme for toolbars and system chrome.
    var preferredColorScheme: ColorScheme {
        switch self {
        case .light, .sepia: return .light
        case .dark: return .dark
        }
    }
    #endif
}
