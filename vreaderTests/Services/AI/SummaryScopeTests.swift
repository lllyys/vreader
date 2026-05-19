// Purpose: Tests for SummaryScope — the breadth-of-summary enum that
// drives the AI Summarize tab's scope chips (feature #69 WI-1).
// Pins the design-string labels, the chip-order contract, raw-value
// round-trip, and Equatable.

import Testing
@testable import vreader

@Suite("SummaryScope")
struct SummaryScopeTests {

    // MARK: - displayName (design strings)

    @Test func sectionDisplayNameMatchesDesign() {
        #expect(SummaryScope.section.displayName == "Section")
    }

    @Test func chapterDisplayNameMatchesDesign() {
        #expect(SummaryScope.chapter.displayName == "Chapter")
    }

    @Test func bookSoFarDisplayNameMatchesDesign() {
        #expect(SummaryScope.bookSoFar.displayName == "Book so far")
    }

    // MARK: - allCases order (drives the chip ForEach)

    @Test func allCasesAreInDesignOrder() {
        #expect(SummaryScope.allCases == [.section, .chapter, .bookSoFar])
    }

    // MARK: - Raw value round-trip (stable key)

    @Test func rawValueRoundTrips() {
        for scope in SummaryScope.allCases {
            #expect(SummaryScope(rawValue: scope.rawValue) == scope)
        }
    }

    @Test func rawValuesAreStable() {
        #expect(SummaryScope.section.rawValue == "section")
        #expect(SummaryScope.chapter.rawValue == "chapter")
        #expect(SummaryScope.bookSoFar.rawValue == "bookSoFar")
    }

    @Test func unknownRawValueIsNil() {
        #expect(SummaryScope(rawValue: "paragraph") == nil)
    }

    // MARK: - Equatable

    @Test func equalScopesCompareEqual() {
        #expect(SummaryScope.chapter == SummaryScope.chapter)
    }

    @Test func differentScopesCompareUnequal() {
        #expect(SummaryScope.section != SummaryScope.bookSoFar)
    }

    // MARK: - Sendable

    @Test func scopeIsSendable() {
        let scope: any Sendable = SummaryScope.chapter
        #expect(scope is SummaryScope)
    }
}
