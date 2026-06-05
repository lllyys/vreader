// Purpose: Feature #94 WI-1 — the pure, testable core of the filterable
// TOC. A stateless namespace that narrows the already-loaded
// `[TOCEntry]` by title match and computes the non-overlapping match
// ranges used to tint the matched runs in each visible row.
//
// Matching contract (Gate-2 M1 — a DELIBERATE narrowing vs
// `SearchTextNormalizer`):
//   IN SCOPE — case-insensitive (ASCII + Unicode), diacritic-insensitive
//     (Café ≡ cafe), and CJK EXACT substring (剑 narrows a CJK TOC). The
//     match is Foundation `String.range(of:options:range:locale:)` with
//     `[.caseInsensitive, .diacriticInsensitive]` and `locale: nil`,
//     iterated from each match's `upperBound` to exhaustion so the
//     returned ranges are NON-OVERLAPPING and live in the ORIGINAL title
//     (so the highlight maps back to the un-folded characters).
//   OUT OF SCOPE — NFKC compatibility folding: full-width Latin (ＣＡＦＥ)
//     and ligatures (ﬁ) do NOT fold here, unlike the FTS search path.
//     `SearchTextNormalizer.normalize` is not length-preserving (NFKC +
//     CJK segmentation insert/replace characters), so ranges computed on
//     the normalized string would tint the WRONG characters in the
//     original title. The TOC filter is a lightweight title narrower; its
//     load-bearing case is CJK exact-substring, and a user wanting
//     full-text / NFKC matching falls back to "Open Search" (#2/#63).
//   `locale: nil` avoids Turkish-I-style locale-folding surprises.
//
// `filtered` enumerates FIRST then filters, so each surviving row carries
// its ORIGINAL list index (Gate-2 H1) — the row's chapter ordinal
// (`index + 1`) and current-row marker (`index == activeEntryIndex`) MUST
// derive from this original index, never the filtered position.
//
// `TOCFilterCountLabel` / `TOCFilterState` are the pure derivations the
// `TOCSheet` filter wiring drives (the live count label, the no-match
// branch predicate, the clear-restore transition) — split out so they are
// unit-testable without rendering (Gate-2 M3).
//
// @coordinates-with: TOCSheet.swift, TOCSheet+Filter.swift,
//   TOCFilterField.swift, TOCSheetRows.swift, TOCProvider.swift (TOCEntry)

import Foundation

/// Pure title-filtering logic for the Contents tab. Stateless + `Sendable`.
enum TOCTitleFilter {

    /// Foundation folding options shared by the predicate and the
    /// highlight so they never disagree.
    private static let foldingOptions: String.CompareOptions =
        [.caseInsensitive, .diacriticInsensitive]

    /// ALL non-overlapping occurrences of `query` in `title`,
    /// case-insensitive + diacritic-insensitive, as ranges in the
    /// ORIGINAL `title` (so a highlight maps to the un-folded characters).
    /// Empty / whitespace-only query → `[]`.
    static func matchRanges(in title: String, query: String) -> [Range<String.Index>] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchStart = title.startIndex
        while searchStart < title.endIndex,
              let found = title.range(
                of: trimmed,
                options: foldingOptions,
                range: searchStart..<title.endIndex,
                locale: nil
              ) {
            ranges.append(found)
            // Advance past this match (non-overlapping). A diacritic-fold
            // can in principle yield an empty range; guard against a
            // non-advancing loop by stepping at least one character.
            searchStart = found.upperBound > found.lowerBound
                ? found.upperBound
                : title.index(after: found.lowerBound)
        }
        return ranges
    }

    /// `true` when `title` contains `query` under the matching contract.
    /// An empty / whitespace-only query matches everything (today's
    /// unfiltered behavior).
    static func matches(_ title: String, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return !matchRanges(in: title, query: trimmed).isEmpty
    }

    /// `true` when there IS an active chapter and the current query has
    /// filtered it OUT of the results — the signal to pin the design's
    /// "Reading" row so the current location stays reachable (Gate-4 M1).
    /// False when not filtering, no active chapter, or the active chapter
    /// still matches. Pure form of `TOCSheet.pinnedCurrentEntry`.
    static func isActiveFilteredOut(
        entries: [TOCEntry],
        activeIndex: Int?,
        query: String
    ) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let active = activeIndex,
              entries.indices.contains(active)
        else { return false }
        return !filtered(entries, query: trimmed).contains { $0.index == active }
    }

    /// Narrows `entries` to those whose title matches `query`, carrying
    /// each survivor's ORIGINAL list index (Gate-2 H1). Empty query → all
    /// entries with their identity indices.
    static func filtered(
        _ entries: [TOCEntry],
        query: String
    ) -> [(index: Int, entry: TOCEntry)] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.enumerated().compactMap { offset, entry in
            matches(entry.title, query: trimmed)
                ? (index: offset, entry: entry)
                : nil
        }
    }
}

/// The live result-count label below the filter field. Pure so the
/// wording is unit-pinned without rendering.
enum TOCFilterCountLabel {
    /// `"N of M chapters"` while filtering, `"No chapters match"` on an
    /// empty result, or `nil` (hidden) when the query is empty.
    static func text(visibleCount: Int, totalCount: Int, trimmedQuery: String) -> String? {
        guard !trimmedQuery.isEmpty else { return nil }
        guard visibleCount > 0 else { return "No chapters match" }
        let noun = visibleCount == 1 ? "chapter" : "chapters"
        return "\(visibleCount) of \(totalCount) \(noun)"
    }
}

/// The pure branch / transition predicates the `TOCSheet` filter wiring
/// reads — the no-match empty-state branch and the clear-filter re-scroll
/// transition (Gate-2 M2 / M3).
enum TOCFilterState {
    /// `true` when the user is actively filtering AND nothing matched —
    /// the no-match empty state (the "Open Search" escape hatch), as
    /// opposed to a genuinely empty TOC (which has no query).
    static func isNoMatch(visibleIsEmpty: Bool, trimmedQuery: String) -> Bool {
        visibleIsEmpty && !trimmedQuery.isEmpty
    }

    /// `true` only on the transition from a non-empty filter back to an
    /// empty one — the moment the full list + current-row auto-scroll must
    /// be restored (Gate-2 M2). Whitespace-only counts as cleared.
    static func didClear(from oldValue: String, to newValue: String) -> Bool {
        let oldTrimmed = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let newTrimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return !oldTrimmed.isEmpty && newTrimmed.isEmpty
    }
}
