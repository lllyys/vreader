// Purpose: Feature #75 WI-1 — the per-document page axis for EPUB paged mode and
// the pure seam that resolves it. A loaded spine document's writing direction is
// resolved from its COMPUTED writing-mode / direction (the authoritative values
// from a load-time getComputedStyle probe), with the document `dir` attribute,
// `lang`, and the book-level `readingDirection` hint resolving `.auto` /
// ambiguous cases. Resolution is PER-DOCUMENT (the Gate-2 audit established that
// vertical writing can vary per spine item), never book-level.
//
// Kept pure (no WKWebView, no I/O) so the precedence rules are unit-testable.
//
// @coordinates-with: EPUBPaginationHelper.swift (consumes PageAxis), EPUBTypes.swift
//   (ReadingDirection hint), the EPUB load-time computed-style probe (WI-3).

import Foundation

/// The page-flow axis of a loaded EPUB spine document in paged mode.
///
/// EPUB scope (#75) is horizontal LTR/RTL + `vertical-rl`; `vertical-lr` is
/// deferred and falls back to horizontal resolution.
enum PageAxis: Equatable, Sendable {
    /// Left-to-right horizontal columns (the default) — pages flow on `scrollLeft`.
    case horizontalLTR
    /// Right-to-left horizontal columns (Arabic/Hebrew) — WebKit negative `scrollLeft`.
    case horizontalRTL
    /// Vertical-rl columns (CJK) — pages flow on the horizontal axis, right-to-left.
    case verticalRL
}

enum PageAxisResolver {
    /// Resolve the page axis for a loaded spine document.
    ///
    /// Precedence:
    /// 1. `writing-mode: vertical-rl` → `.verticalRL` (authoritative; other
    ///    vertical modes are out of scope and fall through to horizontal).
    /// 2. Horizontal: the COMPUTED `direction` (`ltr`/`rtl`) is authoritative.
    /// 3. If computed direction is empty/unknown: the document `dir` attribute,
    ///    then the book-level `readingDirection` hint, then (for `.auto`) the
    ///    `lang` primary subtag; defaulting to `.horizontalLTR`.
    ///
    /// - Parameters:
    ///   - writingMode: computed `writing-mode` (e.g. `"vertical-rl"`, `"horizontal-tb"`).
    ///   - direction: computed `direction` (`"ltr"`/`"rtl"`/`""`).
    ///   - dir: the document element's `dir` attribute, if any.
    ///   - lang: the document/publication language tag, for `.auto` resolution.
    ///   - readingDirectionHint: the book-level parsed `readingDirection`.
    static func resolve(
        writingMode: String,
        direction: String,
        dir: String?,
        lang: String?,
        readingDirectionHint: ReadingDirection
    ) -> PageAxis {
        if normalize(writingMode).hasPrefix("vertical-rl") {
            return .verticalRL
        }
        return resolveHorizontal(
            direction: direction, dir: dir, lang: lang,
            readingDirectionHint: readingDirectionHint
        )
    }

    /// Lowercase + whitespace-trim a CSS/attribute string for comparison.
    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func resolveHorizontal(
        direction: String,
        dir: String?,
        lang: String?,
        readingDirectionHint: ReadingDirection
    ) -> PageAxis {
        // Computed direction is authoritative when present.
        switch normalize(direction) {
        case "rtl": return .horizontalRTL
        case "ltr": return .horizontalLTR
        default: break
        }
        // Then the document dir attribute.
        switch dir.map(normalize) {
        case "rtl": return .horizontalRTL
        case "ltr": return .horizontalLTR
        default: break
        }
        // Then the book-level hint; `.auto` resolves from the language.
        switch readingDirectionHint {
        case .rtl: return .horizontalRTL
        case .ltr: return .horizontalLTR
        case .auto:
            return isRTLLanguage(lang) ? .horizontalRTL : .horizontalLTR
        }
    }

    /// Whether a BCP-47 language tag's primary subtag is a right-to-left script.
    private static func isRTLLanguage(_ lang: String?) -> Bool {
        guard let lang else { return false }
        let normalized = normalize(lang)
        guard !normalized.isEmpty else { return false }
        let primary = normalized.split(separator: "-").first.map(String.init) ?? ""
        // Common RTL language primary subtags, including legacy/ISO variants
        // (`iw`=he, `prs`=Dari, `ckb`=Sorani, `syr`=Syriac).
        // `ckb` (Sorani) is RTL; bare `ku` is omitted — Kurmanji Kurdish is
        // Latin/LTR, so the primary subtag alone is ambiguous.
        let rtl: Set<String> = [
            "ar", "he", "iw", "fa", "prs", "ur", "ps", "sd", "ug", "yi",
            "dv", "ckb", "syr",
        ]
        return rtl.contains(primary)
    }
}
