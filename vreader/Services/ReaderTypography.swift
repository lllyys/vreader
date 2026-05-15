// Purpose: Feature #60 visual-identity v2 — bundled font registry.
// Resolves a `ReaderFontFamily` case to a UIFont for the reader body
// + UI chrome, with a documented fallback chain when the requested
// face isn't registered with the system.
//
// This is dormant infrastructure in WI-1: no view consumes
// `ReaderTypography` yet. WI-5 (TXT/MD theme injection) and WI-6
// (chrome re-skin) will plumb the registry through their respective
// surfaces. The cssFontStack(for:) hook is consumed by WI-4's EPUB
// CSS injection.
//
// **Font binary deferral**: WI-1 ships the Swift API + fallback
// chain, NOT the actual `Source Serif 4.otf` / `Inter.otf` binaries.
// Those require external asset fetching with licence verification —
// deferred to a separate WI-1b manual-ops step. The fallback chain
// keeps the API safe to call before WI-1b lands: a request for
// `.sourceSerif4` returns Georgia + serif system fallback; a request
// for `.inter` returns the platform system font.
//
// Key decisions:
// - **No service singleton**. `ReaderTypography` is a stateless namespace
//   (static methods only) — no per-call object allocation, threadsafe by
//   construction, no `@MainActor` needed.
// - **UIFont always non-nil**. The fallback chain guarantees a usable
//   UIFont for every ReaderFontFamily case; callers don't need to handle
//   nil. Critical because the reader views can't lay out text without a
//   font.
// - **CSS stack separate from UIFont**. EPUB WKWebView injection uses
//   `cssFontStack(for:)` (Web font names); TXT/MD bridges use
//   `body(for:size:)` (UIFont instances). One API per consumer keeps the
//   interface honest about the two rendering paths.
//
// @coordinates-with: TypographySettings.swift (ReaderFontFamily),
//   ReaderTheme.swift (cssFontStack legacy site — WI-4 will migrate),
//   future WI-5/WI-6 consumers.

import Foundation
#if canImport(UIKit)
import UIKit

enum ReaderTypography {

    // MARK: - Body face (UIFont)

    /// Returns a UIFont for the reader-body text in the requested
    /// `ReaderFontFamily`. When the requested face isn't registered
    /// (e.g., Source Serif 4 before WI-1b bundles the binary), falls
    /// back per the chain documented in the file header. Always
    /// returns a usable UIFont at the requested point size.
    static func body(for family: ReaderFontFamily, size: CGFloat) -> UIFont {
        switch family {
        case .system:
            return UIFont.systemFont(ofSize: size)
        case .serif:
            return UIFont(name: "Georgia", size: size)
                ?? UIFont.systemFont(ofSize: size)
        case .monospace:
            return UIFont(name: "Menlo", size: size)
                ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        case .sourceSerif4:
            // Try the bundled face first. `UIFont(name:size:)` expects a
            // fully-qualified face/PostScript name; Adobe's Source Serif 4
            // static releases ship `SourceSerif4-Regular` (the canonical
            // PostScript name). Codex Gate 4 round 1 (Medium): the prior
            // chain missed this and would have stayed on Georgia even
            // after WI-1b bundles the binary. Try the canonical name
            // first, then static variants, then family/full-name forms
            // a designer might also have shipped, then Georgia + system
            // fallback.
            let sourceSerifCandidates = [
                "SourceSerif4-Regular",   // canonical Adobe PostScript name
                "SourceSerif4",           // family-name lookup
                "Source Serif 4",         // display-name lookup
                "SourceSerifPro-Regular", // older typeface name some bundles use
                "Source Serif Pro",       // older typeface display name
            ]
            for name in sourceSerifCandidates {
                if let face = UIFont(name: name, size: size) { return face }
            }
            if let georgia = UIFont(name: "Georgia", size: size) { return georgia }
            return UIFont.systemFont(ofSize: size)
        case .inter:
            // Try Inter first; Adobe-ish naming convention for Inter
            // ships `Inter-Regular` (PostScript) plus `Inter` (family).
            // Fall through to the platform system font (already sans on
            // iOS — SF Pro by default).
            let interCandidates = [
                "Inter-Regular",     // canonical PostScript name
                "Inter",             // family-name lookup
            ]
            for name in interCandidates {
                if let face = UIFont(name: name, size: size) { return face }
            }
            return UIFont.systemFont(ofSize: size)
        }
    }

    // MARK: - CSS font-stack (for EPUB injection)

    /// Returns the CSS `font-family` stack for a given `ReaderFontFamily`.
    /// Consumed by WI-4's EPUB CSS injection. Each stack ends with the
    /// appropriate generic family (serif / sans-serif / monospace) so
    /// the WKWebView falls back gracefully when the named face isn't
    /// registered with WebKit. CJK glyphs naturally fall through to the
    /// system CJK font (PingFang SC / Hiragino) because Latin-only faces
    /// have no CJK coverage.
    ///
    /// NOTE: `ReaderTheme.cssFontStack(for:)` (the legacy site) covers
    /// the 3 historical families only. This new entry point covers all
    /// 5; WI-4 will switch ReaderTheme to delegate here.
    static func cssFontStack(for family: ReaderFontFamily) -> String {
        switch family {
        case .system:
            return "-apple-system, system-ui, sans-serif"
        case .serif:
            return "Georgia, 'Times New Roman', serif"
        case .monospace:
            return "'SF Mono', Menlo, 'Courier New', monospace"
        case .sourceSerif4:
            return "'Source Serif 4', Georgia, 'Times New Roman', serif"
        case .inter:
            return "Inter, -apple-system, system-ui, sans-serif"
        }
    }
}
#endif
