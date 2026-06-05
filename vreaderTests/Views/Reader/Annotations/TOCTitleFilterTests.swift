// Purpose: Feature #94 WI-1 — pins the pure-logic core of the filterable
// TOC: `TOCTitleFilter`'s matching + filtering, and the pure derivations
// the `TOCSheet` filter wiring drives (original-index preservation,
// current-row-under-filter, the count label, the no-match CTA predicate,
// and the clear-restore predicate).
//
// The matching contract (documented in `TOCTitleFilter.swift`): Foundation
// case-insensitive + diacritic-insensitive substring over the ORIGINAL
// title, non-overlapping ranges, CJK exact-substring. NFKC / full-width /
// ligature folding is OUT OF SCOPE (a deliberate narrowing vs
// `SearchTextNormalizer`).
//
// @coordinates-with: TOCTitleFilter.swift, TOCSheet+Filter.swift,
//   TOCProvider.swift (TOCEntry)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #94 — TOCTitleFilter")
struct TOCTitleFilterTests {

    // MARK: - Fixtures

    private func entry(_ title: String, href: String = "x.xhtml") -> TOCEntry {
        TOCEntry(
            title: title,
            level: 0,
            locator: makeEPUBLocator(href: href, progression: 0)
        )
    }

    private func entries(_ titles: [String]) -> [TOCEntry] {
        titles.enumerated().map { i, t in entry(t, href: "ch\(i).xhtml") }
    }

    // MARK: - matches

    @Test("Empty query matches every title")
    func emptyQueryMatchesAll() {
        #expect(TOCTitleFilter.matches("Loomings", query: ""))
        #expect(TOCTitleFilter.matches("", query: ""))
    }

    @Test("Whitespace-only query matches every title (trimmed to empty)")
    func whitespaceQueryMatchesAll() {
        #expect(TOCTitleFilter.matches("Loomings", query: "   "))
        #expect(TOCTitleFilter.matches("Loomings", query: "\t \n"))
    }

    @Test("Matching is case-insensitive")
    func caseInsensitiveMatch() {
        #expect(TOCTitleFilter.matches("Mr. Darcy", query: "DARCY"))
        #expect(TOCTitleFilter.matches("Mr. Darcy", query: "darcy"))
        #expect(TOCTitleFilter.matches("The Spouter-Inn", query: "INN"))
    }

    @Test("Matching is diacritic-insensitive")
    func diacriticInsensitiveMatch() {
        #expect(TOCTitleFilter.matches("Café Society", query: "cafe"))
        #expect(TOCTitleFilter.matches("Cafe Society", query: "café"))
        #expect(TOCTitleFilter.matches("naïve résumé", query: "naive"))
    }

    @Test("CJK single-character substring matches (the motivating case)")
    func cjkSingleCharMatch() {
        // 剑 (sword) appears in 断剑重铸 but not in 残阳如血.
        #expect(TOCTitleFilter.matches("第二章 · 断剑重铸", query: "剑"))
        #expect(TOCTitleFilter.matches("第三章 · 残阳如血", query: "剑") == false)
        // Two-char CJK substring.
        #expect(TOCTitleFilter.matches("第四章 · 故人来信", query: "故人"))
    }

    @Test("No match returns false for a non-empty query")
    func noMatch() {
        #expect(TOCTitleFilter.matches("Loomings", query: "zzqx") == false)
    }

    @Test("Query longer than the title does not match")
    func queryLongerThanTitle() {
        #expect(TOCTitleFilter.matches("Inn", query: "The Spouter-Inn") == false)
    }

    @Test("Empty title never matches a non-empty query")
    func emptyTitleNoMatch() {
        #expect(TOCTitleFilter.matches("", query: "a") == false)
    }

    // MARK: - matchRanges

    @Test("Single occurrence yields one range in the ORIGINAL title")
    func singleOccurrenceRange() {
        let title = "The Street"
        let ranges = TOCTitleFilter.matchRanges(in: title, query: "street")
        #expect(ranges.count == 1)
        // The range maps back to the original-cased substring.
        #expect(String(title[ranges[0]]) == "Street")
    }

    @Test("Multiple occurrences yield all non-overlapping ranges")
    func multipleOccurrencesNonOverlapping() {
        let title = "The other theory"
        let ranges = TOCTitleFilter.matchRanges(in: title, query: "the")
        // "the" occurs 3×: leading "The", "o(the)r", "(the)ory" — every
        // occurrence is marked, non-overlapping, in order.
        #expect(ranges.count == 3)
        // Non-overlapping + ascending.
        #expect(ranges[0].upperBound <= ranges[1].lowerBound)
        #expect(ranges[1].upperBound <= ranges[2].lowerBound)
        for r in ranges {
            #expect(String(title[r]).lowercased() == "the")
        }
    }

    @Test("Multiple adjacent occurrences are non-overlapping")
    func adjacentOccurrences() {
        let title = "aaaa"
        let ranges = TOCTitleFilter.matchRanges(in: title, query: "aa")
        // Non-overlapping scan from each match's upperBound → "aa", "aa" → 2.
        #expect(ranges.count == 2)
        #expect(ranges[0].upperBound <= ranges[1].lowerBound)
    }

    @Test("CJK occurrence yields a range over the matched characters")
    func cjkOccurrenceRange() {
        let title = "第二章 · 断剑重铸"
        let ranges = TOCTitleFilter.matchRanges(in: title, query: "剑")
        #expect(ranges.count == 1)
        #expect(String(title[ranges[0]]) == "剑")
    }

    @Test("Empty / whitespace query yields no ranges")
    func emptyQueryNoRanges() {
        #expect(TOCTitleFilter.matchRanges(in: "Loomings", query: "").isEmpty)
        #expect(TOCTitleFilter.matchRanges(in: "Loomings", query: "   ").isEmpty)
    }

    @Test("Query longer than the title yields no ranges")
    func queryLongerThanTitleNoRanges() {
        #expect(TOCTitleFilter.matchRanges(in: "Inn", query: "The Spouter-Inn").isEmpty)
    }

    @Test("Diacritic-insensitive match maps to the ORIGINAL accented run")
    func diacriticRangeMapsToOriginal() {
        let title = "Café"
        let ranges = TOCTitleFilter.matchRanges(in: title, query: "cafe")
        #expect(ranges.count == 1)
        // The highlighted run is the accented original, not the folded form.
        #expect(String(title[ranges[0]]) == "Café")
    }

    // MARK: - filtered (original-index preservation — Gate-2 H1)

    @Test("filtered narrows the list and PRESERVES original indices")
    func filteredPreservesOriginalIndices() {
        let list = entries(["Loomings", "The Carpet-Bag", "The Spouter-Inn", "Breakfast"])
        let result = TOCTitleFilter.filtered(list, query: "the")
        // Two survivors: index 1 (Carpet-Bag) and 2 (Spouter-Inn).
        #expect(result.count == 2)
        #expect(result[0].index == 1)
        #expect(result[1].index == 2)
        #expect(result[0].entry.title == "The Carpet-Bag")
        #expect(result[1].entry.title == "The Spouter-Inn")
    }

    @Test("filtered keeps original order")
    func filteredPreservesOrder() {
        let list = entries(["Sword A", "Plain", "Sword B", "Sword C"])
        let result = TOCTitleFilter.filtered(list, query: "sword")
        #expect(result.map { $0.index } == [0, 2, 3])
    }

    @Test("Empty query returns all entries with identity indices")
    func filteredEmptyQueryIdentity() {
        let list = entries(["A", "B", "C"])
        let result = TOCTitleFilter.filtered(list, query: "")
        #expect(result.count == 3)
        #expect(result.map { $0.index } == [0, 1, 2])
        #expect(result.map { $0.entry.title } == ["A", "B", "C"])
    }

    @Test("No match yields an empty result")
    func filteredNoMatch() {
        let list = entries(["A", "B", "C"])
        #expect(TOCTitleFilter.filtered(list, query: "zzqx").isEmpty)
    }

    @Test("filtered narrows a CJK list by a single character")
    func filteredCJK() {
        let titles = [
            "第一章 · 夜雨入孤城",
            "第二章 · 断剑重铸",
            "第三章 · 残阳如血",
            "第四章 · 剑影横江",
        ]
        let result = TOCTitleFilter.filtered(entries(titles), query: "剑")
        #expect(result.map { $0.index } == [1, 3])
    }

    @Test("Mixed Latin+CJK title matches on either script")
    func mixedScriptTitle() {
        let list = entries(["Chapter 剑 One", "Chapter Two"])
        #expect(TOCTitleFilter.filtered(list, query: "剑").map { $0.index } == [0])
        #expect(TOCTitleFilter.filtered(list, query: "chapter").map { $0.index } == [0, 1])
    }

    // MARK: - Pure derivations the TOCSheet filter wiring drives (Gate-2 M3)

    @Test("Current-row marker tracks the ORIGINAL index under filtering")
    func currentRowUnderFilter() {
        // 4 entries, active is index 2. Filter to "the" keeps indices 1 + 2.
        let list = entries(["Loomings", "The Carpet-Bag", "The Spouter-Inn", "Breakfast"])
        let activeIndex = 2
        let result = TOCTitleFilter.filtered(list, query: "the")
        // The surviving active entry still reports current by its ORIGINAL
        // index — not by its filtered position (which is 1).
        let currentFlags = result.map { $0.index == activeIndex }
        #expect(currentFlags == [false, true])
        // Chapter ordinals derive from the original index, not the filtered
        // position — so the surviving rows read "2" and "3", not "1" and "2".
        let ordinals = result.map { $0.index + 1 }
        #expect(ordinals == [2, 3])
    }

    @Test("Count label: N of M chapters while filtering")
    func countLabelFiltering() {
        let label = TOCFilterCountLabel.text(visibleCount: 3, totalCount: 16, trimmedQuery: "the")
        #expect(label == "3 of 16 chapters")
    }

    @Test("Count label: singular 'chapter' for a single match")
    func countLabelSingular() {
        // Per the design (`toc-filter-artboards.jsx`): `count === 1 ?
        // 'chapter' : 'chapters'` — a single match reads "1 of 16 chapter".
        let label = TOCFilterCountLabel.text(visibleCount: 1, totalCount: 16, trimmedQuery: "inn")
        #expect(label == "1 of 16 chapter")
    }

    @Test("Count label: 'No chapters match' on an empty result")
    func countLabelNoMatch() {
        let label = TOCFilterCountLabel.text(visibleCount: 0, totalCount: 16, trimmedQuery: "zzqx")
        #expect(label == "No chapters match")
    }

    @Test("Count label: hidden (nil) when the query is empty")
    func countLabelHiddenWhenEmpty() {
        #expect(TOCFilterCountLabel.text(visibleCount: 16, totalCount: 16, trimmedQuery: "") == nil)
    }

    @Test("No-match predicate: empty visible AND non-empty trimmed query")
    func noMatchPredicate() {
        // Has a query, no survivors → the no-match branch (Open Search CTA).
        #expect(TOCFilterState.isNoMatch(visibleIsEmpty: true, trimmedQuery: "zzqx"))
        // No query → not the no-match branch (the list is just empty/normal).
        #expect(TOCFilterState.isNoMatch(visibleIsEmpty: true, trimmedQuery: "") == false)
        // Has survivors → never no-match.
        #expect(TOCFilterState.isNoMatch(visibleIsEmpty: false, trimmedQuery: "zzqx") == false)
    }

    @Test("Clear-restore predicate: only the transition back to empty re-scrolls")
    func clearRestorePredicate() {
        // Transition non-empty → empty: re-fire the current-row scroll.
        #expect(TOCFilterState.didClear(from: "the", to: ""))
        #expect(TOCFilterState.didClear(from: "the", to: "   "))   // whitespace == cleared
        // Still filtering: no re-scroll.
        #expect(TOCFilterState.didClear(from: "th", to: "the") == false)
        // Already empty → empty (e.g. focus toggles): not a clear transition.
        #expect(TOCFilterState.didClear(from: "", to: "") == false)
        // Starting to filter (empty → non-empty): not a clear.
        #expect(TOCFilterState.didClear(from: "", to: "the") == false)
    }

    // MARK: - isActiveFilteredOut (pinned "Reading" row — Gate-4 M1)

    @Test("isActiveFilteredOut is true when the active chapter is filtered out")
    func activeFilteredOut_whenHidden() {
        let list = entries(["Loomings", "The Carpet-Bag", "The Spouter-Inn"])
        // Active = index 0 ("Loomings"); query "the" keeps only 1 & 2 → 0 hidden.
        #expect(TOCTitleFilter.isActiveFilteredOut(entries: list, activeIndex: 0, query: "the") == true)
    }

    @Test("isActiveFilteredOut is false when the active chapter still matches")
    func activeFilteredOut_whenVisible() {
        let list = entries(["Loomings", "The Carpet-Bag", "The Spouter-Inn"])
        // Active = index 1 ("The Carpet-Bag"); query "the" keeps it → not hidden.
        #expect(TOCTitleFilter.isActiveFilteredOut(entries: list, activeIndex: 1, query: "the") == false)
    }

    @Test("isActiveFilteredOut is false with no query / no active / out-of-range index")
    func activeFilteredOut_edgeCases() {
        let list = entries(["Loomings", "The Carpet-Bag"])
        #expect(TOCTitleFilter.isActiveFilteredOut(entries: list, activeIndex: 0, query: "") == false)
        #expect(TOCTitleFilter.isActiveFilteredOut(entries: list, activeIndex: nil, query: "the") == false)
        #expect(TOCTitleFilter.isActiveFilteredOut(entries: list, activeIndex: 9, query: "the") == false)
    }
}
