// Purpose: Feature #94 WI-1 — `TOCSheet`'s Contents-tab filter wiring,
// split out to keep `TOCSheet.swift` under the ~300-line guideline
// (`.claude/rules/50-codebase-conventions.md` §9) — the same cross-file
// extension pattern `TOCSheet+Support.swift` uses (and why `filterQuery`
// is `internal`, not `private`).
//
// This extension holds the derived values the Contents body reads:
//   - `visibleEntries` — `TOCTitleFilter.filtered(tocEntries, query:)`,
//     each survivor carrying its ORIGINAL index (Gate-2 H1).
//   - `trimmedFilterQuery` / `isFilterNoMatch` — the no-match branch
//     predicate (`AnnotationsEmptyStateView` with the "Open Search" CTA).
//   - DEBUG testing hooks for the filter derivations.
//
// @coordinates-with: TOCSheet.swift, TOCFilterField.swift,
//   TOCTitleFilter.swift (TOCFilterCountLabel / TOCFilterState),
//   AnnotationsEmptyStateView.swift

import SwiftUI

extension TOCSheet {

    // MARK: - Filter derivations

    /// The whitespace-trimmed filter query — the canonical form every
    /// predicate compares against.
    var trimmedFilterQuery: String {
        filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The visible Contents rows for the current query — survivors carry
    /// their ORIGINAL list index so the row's chapter ordinal (`index + 1`)
    /// and current-row marker (`index == activeEntryIndex`) stay correct
    /// under filtering (Gate-2 H1). Empty query → all entries.
    var visibleEntries: [(index: Int, entry: TOCEntry)] {
        TOCTitleFilter.filtered(tocEntries, query: filterQuery)
    }

    /// `true` when the user is filtering and nothing matched — the
    /// no-match empty state (the "Open Search" escape hatch), distinct
    /// from a genuinely empty TOC (which carries no query).
    var isFilterNoMatch: Bool {
        TOCFilterState.isNoMatch(
            visibleIsEmpty: visibleEntries.isEmpty,
            trimmedQuery: trimmedFilterQuery
        )
    }

    /// The current chapter to PIN above the filtered list — the design's
    /// "Reading" row — so the active location stays reachable even when the
    /// query has filtered it OUT of the results (`toc-filter-artboards.jsx`
    /// `PinnedCurrentRow`). Nil when not filtering, when there is no active
    /// chapter, or when the active chapter is still in `visibleEntries`.
    var pinnedCurrentEntry: TOCEntry? {
        guard let active = activeEntryIndex,
              TOCTitleFilter.isActiveFilteredOut(
                entries: tocEntries, activeIndex: active, query: filterQuery)
        else { return nil }
        return tocEntries[active]
    }

    // MARK: - Filter-aware auto-scroll (Gate-2 M2)

    /// The `.task(id:)` key for the current-chapter auto-scroll ladder.
    /// Folds in the unfiltered flag so the `filterQuery → ""` transition
    /// re-fires the ladder even though the target id is unchanged (Gate-2
    /// M2); while filtering, the key still changes but the ladder no-ops.
    var scrollLadderKey: String {
        "\(trimmedFilterQuery.isEmpty ? "1" : "0"):\(currentChapterScrollTarget ?? "")"
    }

    /// The Bug #282 retry ladder — issues an immediate (t=0) scroll then a
    /// short animated fallback for the not-yet-materialized `LazyVStack`
    /// case. No-ops while filtering: auto-scroll-to-current applies only to
    /// the full, unfiltered list (the filtered list is short). Clearing the
    /// filter re-runs this via `scrollLadderKey` (Gate-2 M2).
    func scrollToCurrentChapter(proxy: ScrollViewProxy) async {
        guard trimmedFilterQuery.isEmpty,
              let targetID = currentChapterScrollTarget else { return }
        var elapsed = 0
        for (attempt, cumulative) in Self.scrollRetryDelaysMilliseconds.enumerated() {
            // Sleep only the incremental gap to the next attempt so the
            // first (cumulative 0) attempt fires with no delay.
            let gap = cumulative - elapsed
            if gap > 0 {
                try? await Task.sleep(nanoseconds: UInt64(gap) * 1_000_000)
            }
            elapsed = cumulative
            guard !Task.isCancelled else { return }
            if attempt == 0 {
                proxy.scrollTo(targetID, anchor: .center)   // instant (Bug #282)
            } else {
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(targetID, anchor: .center)
                }
            }
        }
    }

    // MARK: - No-match empty state (filter-specific)

    /// The no-match empty state — same `AnnotationsEmptyStateView`
    /// component as the no-TOC state, but with a filter-specific message
    /// and the "Open Search" CTA wired to the full-text search escape
    /// hatch (#2/#63). NOT the "No table of contents" copy.
    @ViewBuilder
    var filterNoMatchBody: some View {
        AnnotationsEmptyStateView(
            theme: theme,
            accessibilityIdentifier: "tocFilterNoMatchState",
            art: AnyView(EmptyTOCArt(theme: theme)),
            title: "No chapters match",
            body: "Nothing in this book's contents matches “\(trimmedFilterQuery)”. "
                + "Looking for a phrase inside the text instead?",
            ctaLabel: "Search full text",
            ctaSystemImage: "magnifyingglass",
            onCTA: { onDismiss(); onOpenSearch() }
        )
    }

    // MARK: - The filtered chapter list (moved here for file size — Gate-4)

    /// The Contents chapter list: an inner `ScrollView` (the shared outer one
    /// was removed so the filter field can pin — Gate-2 H2) driven off
    /// `visibleEntries` (filtered survivors carrying their ORIGINAL index so
    /// the ordinal + current-row marker stay correct — Gate-2 H1). Per-row
    /// `.id` + the `.task(id: scrollLadderKey)` ladder restore + re-fire the
    /// auto-scroll-to-current-chapter (Bug #248 / Gate-2 M2).
    @ViewBuilder
    var tocEntryList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(visibleEntries, id: \.entry.id) { pair in
                        let entry = pair.entry
                        TOCContentsRow(
                            theme: theme,
                            chapterOrdinal: pair.index + 1,
                            title: entry.title,
                            matchRanges: TOCTitleFilter.matchRanges(in: entry.title, query: filterQuery),
                            page: Self.displayPage(entry.locator.page),
                            isCurrent: pair.index == activeEntryIndex,
                            // Bug #288: dismiss BEFORE navigating so the sheet is
                            // already animating out when `currentLocator` changes.
                            onTap: { onDismiss(); onNavigate(entry.locator) }
                        )
                        .id(entry.id)
                        .accessibilityIdentifier("tocRow-\(entry.id)")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 14)
            }
            .task(id: scrollLadderKey) { await scrollToCurrentChapter(proxy: proxy) }
        }
    }
}

// MARK: - Testing hooks

#if DEBUG
extension TOCSheet {
    /// The original indices of the rows currently visible under the filter
    /// — pins original-index preservation (Gate-2 H1) without rendering.
    var visibleEntryIndicesForTesting: [Int] {
        visibleEntries.map { $0.index }
    }

    /// The live count-line text the field would show — `nil` when hidden.
    var filterCountTextForTesting: String? {
        TOCFilterCountLabel.text(
            visibleCount: visibleEntries.count,
            totalCount: tocEntries.count,
            trimmedQuery: trimmedFilterQuery
        )
    }

    /// True when the Contents body would render the filter no-match empty
    /// state (query present, no survivors).
    var filterNoMatchShownForTesting: Bool { isFilterNoMatch }

    /// The pinned "Reading" entry the filtered Contents body would show
    /// above the list — nil unless the active chapter is filtered out.
    var pinnedCurrentEntryTitleForTesting: String? { pinnedCurrentEntry?.title }

    /// Invokes the no-match "Search full text" CTA — dismiss then search.
    func invokeFilterNoMatchCTAForTesting() {
        onDismiss()
        onOpenSearch()
    }
}
#endif
