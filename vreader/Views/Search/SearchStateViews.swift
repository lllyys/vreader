// Purpose: Feature #63 WI-2 — the re-skinned empty / no-results states
// for the search sheet. Extracted from `SearchView` so that file stays
// under the ~300-line guideline. Mirrors the design bundle's
// `SearchEmptyState` and `NoResults` from
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx`.
//
// Scope reconciliation:
// - **`SearchNoResultsView`** — the design's circular search-glyph
//   disc + serif "No matches for …" headline + a sub line. The
//   design's sub copy says "switch the scope to all books"; the
//   "All books" scope is OUT of scope for #63 (plan §2.1), so the copy
//   ships WITHOUT any scope-switching suggestion (plan risk §3).
// - **`SearchPromptView`** — the empty-query state. The design's
//   `SearchEmptyState` has a "Recent" searches block and FTS5
//   syntax-hint chips. "Recent searches" query-history persistence
//   does not exist (plan §2.2) — omitted. The hint chips
//   (`chapter:1`, `highlighted:yellow`, `note:`, boolean operators,
//   quoted phrases) imply FTS5 operators: the production query path
//   (`SearchTokenizer.escapeFTS5Query`) double-quotes EVERY whitespace-
//   separated token, so it supports neither boolean operators NOR
//   honoured quoted phrases — no hint chip would be faithful, so the
//   chips are omitted entirely (plan §2.3 — "ship just those two or
//   omit the chips"). The FTS5-capability explanation copy is kept,
//   trimmed to claims the query path actually satisfies.
//
// @coordinates-with: SearchView.swift, ReaderThemeV2.swift,
//   ReaderTypography.swift, SearchTokenizer.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx`

import SwiftUI

// MARK: - No results

/// The "no matches" state — design `vreader-search.jsx` `NoResults`.
struct SearchNoResultsView: View {
    /// The query that produced no results — shown in the headline.
    let query: String
    /// Visual-identity-v2 theme tokens.
    let theme: ReaderThemeV2

    var body: some View {
        VStack(spacing: 8) {
            glyphDisc
            Text("No matches for \u{201C}\(query)\u{201D}")
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 16)))
                .fontWeight(.medium)
                .foregroundStyle(Color(theme.inkColor))
                .padding(.top, 4)
            Text("Try a different spelling or a partial word.")
                .font(.system(size: 12))
                .foregroundStyle(Color(theme.subColor))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 60)
        .accessibilityIdentifier("searchNoResultsView")
    }

    /// The design's 40pt circular faint-wash disc with a search glyph.
    private var glyphDisc: some View {
        Image(systemName: "magnifyingglass")
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(Color(theme.subColor))
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color(discFillColor)))
    }

    private var discFillColor: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.05)
            : UIColor.black.withAlphaComponent(0.04)
    }
}

// MARK: - Empty prompt

/// The empty-query state — design `vreader-search.jsx`
/// `SearchEmptyState`, trimmed to the in-scope content (no "Recent"
/// block, no syntax-hint chips — see the file header).
struct SearchPromptView: View {
    /// Visual-identity-v2 theme tokens.
    let theme: ReaderThemeV2

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Search this book")
            Text(explanation)
                .font(.system(size: 12.5))
                .foregroundStyle(Color(theme.subColor))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .accessibilityIdentifier("searchEmptyPromptView")
    }

    /// The design's `SectionLabel` — 12pt uppercase tracked sub-color.
    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Color(theme.subColor))
    }

    /// FTS5-capability copy — trimmed to claims the production query
    /// path actually satisfies: full-text word indexing with CJK
    /// tokenization. Phrase-operator claims are dropped because
    /// `SearchTokenizer.escapeFTS5Query` quotes every token
    /// independently (see the file header) — the copy must not
    /// overpromise quoted-phrase semantics.
    private var explanation: String {
        "Full-text search finds words anywhere in the book. "
        + "CJK text is tokenized, so Chinese, Japanese, and Korean "
        + "passages are searchable too."
    }
}
