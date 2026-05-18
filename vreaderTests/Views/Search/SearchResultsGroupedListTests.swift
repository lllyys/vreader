// Purpose: Feature #63 WI-2 — tests for the pure grouping logic behind
// the re-skinned grouped results list. The design groups in-book
// search results "by chapter"; production `SearchResult` carries a
// pre-formatted `sourceContext` location string (plan §3), so the
// grouping keys on that. These tests pin the order-preservation and
// match-count contract the grouped list renders.
//
// @coordinates-with: SearchResultGrouping.swift,
//   SearchResultsGroupedList.swift, SearchResult (SearchService.swift)

import Testing
import Foundation
@testable import vreader

@Suite("Search results grouping — feature #63 WI-2")
struct SearchResultsGroupedListTests {

    // MARK: - Fixtures

    private static let testFP = DocumentFingerprint(
        contentSHA256: "ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100",
        fileByteCount: 2048,
        format: .epub
    )

    private static func makeResult(
        id: String,
        context: String
    ) -> SearchResult {
        let locator = Locator(
            bookFingerprint: testFP,
            href: context, progression: 0, totalProgression: 0, cfi: nil,
            page: nil, charOffsetUTF16: nil,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        return SearchResult(
            id: id, snippet: "snippet \(id)", locator: locator,
            sourceContext: context
        )
    }

    // MARK: - Empty input

    @Test("Grouping an empty result set yields no groups")
    func emptyInputYieldsNoGroups() {
        let groups = SearchResultGrouping.group([])
        #expect(groups.isEmpty)
    }

    // MARK: - Single group

    @Test("All results sharing one context collapse into a single group")
    func singleGroup() {
        let results = [
            Self.makeResult(id: "a", context: "Chapter 1"),
            Self.makeResult(id: "b", context: "Chapter 1"),
            Self.makeResult(id: "c", context: "Chapter 1"),
        ]
        let groups = SearchResultGrouping.group(results)
        #expect(groups.count == 1)
        #expect(groups[0].context == "Chapter 1")
        #expect(groups[0].results.count == 3)
    }

    // MARK: - Many groups, document order preserved

    @Test("Groups appear in first-encountered document order")
    func groupsPreserveFirstEncounteredOrder() {
        let results = [
            Self.makeResult(id: "a", context: "Chapter 3"),
            Self.makeResult(id: "b", context: "Chapter 1"),
            Self.makeResult(id: "c", context: "Chapter 8"),
        ]
        let groups = SearchResultGrouping.group(results)
        #expect(groups.map(\.context) == ["Chapter 3", "Chapter 1", "Chapter 8"])
    }

    @Test("Results within a group preserve their original order")
    func resultsWithinGroupPreserveOrder() {
        let results = [
            Self.makeResult(id: "first", context: "Chapter 1"),
            Self.makeResult(id: "second", context: "Chapter 1"),
            Self.makeResult(id: "third", context: "Chapter 1"),
        ]
        let groups = SearchResultGrouping.group(results)
        #expect(groups[0].results.map(\.id) == ["first", "second", "third"])
    }

    @Test("Non-contiguous results with the same context join one group")
    func nonContiguousSameContextJoinsOneGroup() {
        // FTS5 hits for one chapter need not be physically adjacent in
        // the result page; they must still land in a single group, in
        // arrival order, and the group must keep its first-seen slot.
        let results = [
            Self.makeResult(id: "1", context: "Chapter 1"),
            Self.makeResult(id: "2", context: "Chapter 2"),
            Self.makeResult(id: "3", context: "Chapter 1"),
        ]
        let groups = SearchResultGrouping.group(results)
        #expect(groups.count == 2)
        #expect(groups.map(\.context) == ["Chapter 1", "Chapter 2"])
        #expect(groups[0].results.map(\.id) == ["1", "3"])
        #expect(groups[1].results.map(\.id) == ["2"])
    }

    // MARK: - One result per group

    @Test("Each result in a distinct context becomes its own group")
    func oneResultPerGroup() {
        let results = [
            Self.makeResult(id: "a", context: "Page 1"),
            Self.makeResult(id: "b", context: "Page 2"),
            Self.makeResult(id: "c", context: "Page 3"),
        ]
        let groups = SearchResultGrouping.group(results)
        #expect(groups.count == 3)
        #expect(groups.allSatisfy { $0.results.count == 1 })
    }

    // MARK: - Match count

    @Test("Total match count is the sum of every group's result count")
    func totalMatchCount() {
        let results = [
            Self.makeResult(id: "a", context: "Chapter 1"),
            Self.makeResult(id: "b", context: "Chapter 1"),
            Self.makeResult(id: "c", context: "Chapter 2"),
        ]
        let groups = SearchResultGrouping.group(results)
        #expect(SearchResultGrouping.totalMatchCount(groups) == 3)
        #expect(groups[0].results.count == 2)
        #expect(groups[1].results.count == 1)
    }

    // MARK: - Empty sourceContext fallback

    @Test("Results with an empty sourceContext fall back to a neutral label")
    func emptySourceContextFallsBackToNeutralLabel() {
        // EPUB chapters with no derivable name, or formats where the
        // resolver could not name the unit, yield an empty
        // `sourceContext`. The grouped list must still render a header.
        let results = [
            Self.makeResult(id: "a", context: ""),
            Self.makeResult(id: "b", context: ""),
        ]
        let groups = SearchResultGrouping.group(results)
        #expect(groups.count == 1)
        #expect(groups[0].context.isEmpty)
        #expect(groups[0].displayTitle == SearchResultGroup.unknownLocationTitle)
    }

    @Test("A named group's displayTitle is its sourceContext verbatim")
    func namedGroupDisplayTitleIsContext() {
        let groups = SearchResultGrouping.group(
            [Self.makeResult(id: "a", context: "Chapter 4")]
        )
        #expect(groups[0].displayTitle == "Chapter 4")
    }

    // MARK: - Group identity (stable List diffing)

    @Test("Each group has a stable identifier derived from its context")
    func groupHasStableIdentity() {
        let groups = SearchResultGrouping.group(
            [Self.makeResult(id: "a", context: "Chapter 1")]
        )
        #expect(groups[0].id == "Chapter 1")
    }
}
