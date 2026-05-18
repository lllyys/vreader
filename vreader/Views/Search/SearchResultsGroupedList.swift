// Purpose: Feature #63 WI-2 — the grouped-by-`sourceContext` search
// results list. Extracted from `SearchView` so that file stays under
// the ~300-line guideline. Mirrors the design bundle's
// `SearchResultsList` from
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx`:
// a top "{N} matches in {M} sections" count line, then per group a
// serif header with a right-aligned per-group match count and a
// rounded faint-wash card holding hairline-divided result rows.
//
// Scope reconciliation:
// - Groups by the existing `sourceContext` string (plan §3) — no
//   `SearchResult` data-model change.
// - The design's `p.{page}` per-result badge is dropped (plan §2.4);
//   the group header carries the location instead.
// - Copy is format-neutral — "sections", not "chapters" (plan risk
//   §1) — because `sourceContext` granularity varies by format.
//
// Key decisions:
// - Grouping is the pure `SearchResultGrouping` namespace (unit-tested
//   in `SearchResultsGroupedListTests`); this view is render-only.
// - The pagination "Load more" affordance + the appending-spinner are
//   passed in as a trailing slot so `SearchView` keeps owning the
//   `SearchViewModel` interaction — behavior preserved.
//
// @coordinates-with: SearchView.swift, SearchResultGrouping.swift,
//   SearchResultRow.swift, ReaderThemeV2.swift, ReaderTypography.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-search.jsx`

import SwiftUI

/// The re-skinned grouped search results list.
struct SearchResultsGroupedList<Footer: View>: View {
    /// The results to render, in document order.
    let results: [SearchResult]
    /// The current query — forwarded to each row for match emphasis.
    let query: String
    /// Visual-identity-v2 theme tokens.
    let theme: ReaderThemeV2
    /// Invoked with the tapped result (forwards to reader navigation).
    let onSelect: (SearchResult) -> Void
    /// Trailing slot for the pagination affordance (Load more / spinner).
    @ViewBuilder let footer: () -> Footer

    private var groups: [SearchResultGroup] {
        SearchResultGrouping.group(results)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                countLine
                ForEach(groups) { group in
                    groupSection(group)
                }
                footer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("searchResultsList")
    }

    // MARK: - Count line

    /// "{N} matches in {M} sections" — the design's results summary,
    /// with format-neutral copy (plan risk §1).
    private var countLine: some View {
        Text(countText)
            .font(.system(size: 12))
            .foregroundStyle(Color(theme.subColor))
            .padding(.horizontal, 4)
    }

    private var countText: String {
        let matchCount = SearchResultGrouping.totalMatchCount(groups)
        let groupCount = groups.count
        let matchWord = matchCount == 1 ? "match" : "matches"
        let groupWord = groupCount == 1 ? "section" : "sections"
        return "\(matchCount) \(matchWord) in \(groupCount) \(groupWord)"
    }

    // MARK: - Group section

    @ViewBuilder
    private func groupSection(_ group: SearchResultGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            groupHeader(group)
            groupCard(group)
        }
    }

    /// Serif group header + right-aligned per-group match count.
    private func groupHeader(_ group: SearchResultGroup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(group.displayTitle)
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 13)))
                .fontWeight(.semibold)
                .foregroundStyle(Color(theme.inkColor))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(groupMatchText(group))
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }

    private func groupMatchText(_ group: SearchResultGroup) -> String {
        let count = group.results.count
        return count == 1 ? "1 match" : "\(count) matches"
    }

    /// Rounded faint-wash card holding the group's hairline-divided rows.
    private func groupCard(_ group: SearchResultGroup) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(group.results.enumerated()), id: \.element.id) { index, result in
                if index > 0 {
                    Rectangle()
                        .fill(Color(theme.ruleColor))
                        .frame(height: 0.5)
                }
                Button {
                    onSelect(result)
                } label: {
                    SearchResultRow(result: result, query: query, theme: theme)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("searchResult_\(result.id)")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(cardFillColor))
        )
    }

    // MARK: - Tokens

    /// Group-card fill — the design's `t.isDark ?
    /// 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)'` faint wash.
    private var cardFillColor: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.03)
            : UIColor.black.withAlphaComponent(0.02)
    }
}
