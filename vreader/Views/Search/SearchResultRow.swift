// Purpose: Row view for a single search result with a highlighted
// snippet.
//
// Re-skinned for feature #63 visual-identity v2 (WI-2): the snippet
// uses the design bundle's serif treatment
// (`dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx`'s
// `SnippetText` — Source Serif 4, 13.5pt) and the row carries a
// trailing chevron. The group header (rendered by
// `SearchResultsGroupedList`) now carries the location, so the
// per-row `sourceContext` secondary line is dropped. The design's
// `p.{page}` per-result badge is dropped — most formats have no page
// number (plan §2.4).
//
// Key decisions:
// - Reuses `HighlightedSnippet.highlight(…)` for FTS5-match emphasis —
//   it already strips `<b>…</b>` tags and handles CJK / multi-word
//   matches and has existing tests. No new snippet renderer is
//   introduced (plan §4, Gate-2 round-1 finding 3).
// - Theme tokens (`ReaderThemeV2`) drive ink / accent / chevron color.
// - Accessibility label combines the cleaned snippet + source context
//   so VoiceOver still announces the location the visible header shows.
//
// @coordinates-with SearchResultsGroupedList.swift,
//   SearchResult (SearchService.swift), HighlightedSnippet.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx`

import SwiftUI

/// Row view for a single search result — the design's grouped-list row.
struct SearchResultRow: View {
    let result: SearchResult
    /// The current search query, used to bold matching terms.
    var query: String = ""
    /// Visual-identity-v2 theme tokens. Defaults to `.paper` so
    /// previews / callers that omit it keep working.
    var theme: ReaderThemeV2 = .paper

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(snippetText)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(theme.subColor))
                .padding(.top, 3)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("searchResultRow")
    }

    // MARK: - Private

    /// The serif-styled, match-emphasised snippet. `HighlightedSnippet`
    /// strips FTS5 `<b>…</b>` markers and bolds the query terms; the
    /// base font is the design's Source Serif 4 at 13.5pt.
    private var snippetText: AttributedString {
        var attributed = HighlightedSnippet.highlight(
            snippet: result.snippet,
            query: query,
            baseFont: Font(ReaderTypography.body(for: .sourceSerif4, size: 13.5))
        )
        attributed.foregroundColor = Color(theme.inkColor)
        return attributed
    }

    private var accessibilityText: String {
        let clean = result.snippet
            .replacingOccurrences(of: "<b>", with: "")
            .replacingOccurrences(of: "</b>", with: "")
        if result.sourceContext.isEmpty {
            return clean
        }
        return "\(clean), \(result.sourceContext)"
    }
}
