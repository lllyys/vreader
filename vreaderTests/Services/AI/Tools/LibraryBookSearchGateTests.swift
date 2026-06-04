// Purpose: Feature #91 WI-6b — exhaustively pin the persistent-index SAFETY GATE,
// the risk core of search_other_books. Pure decision over (format, index state):
// not-indexed → excluded; TXT/MD stale-decode or nil-offsets → excluded (would
// silently drop results); TXT/MD good → searchable + restore offsets; EPUB/PDF →
// searchable directly. Mirrors ReaderSearchCoordinator.setup's guard set.
//
// @coordinates-with: LibraryBookSearchGate.swift,
//   dev-docs/plans/20260603-feature-91-agentic-tool-calling.md (WI-6b)

import Testing
import Foundation
@testable import vreader

@Suite("Feature #91 WI-6b — LibraryBookSearchGate")
struct LibraryBookSearchGateTests {

    private func state(
        indexed: Bool = true, reindex: Bool = false, offsets: [Int: Int]? = nil
    ) -> LibraryIndexState {
        LibraryIndexState(isIndexed: indexed, requiresReindex: reindex, segmentOffsets: offsets)
    }

    // MARK: - Not indexed (any format)

    @Test("a never-indexed book is excluded regardless of format", arguments: ["epub", "pdf", "txt", "md"])
    func notIndexedExcluded(format: String) {
        #expect(LibraryBookSearchGate.evaluate(format: format, state: state(indexed: false))
            == .excluded(.notIndexed))
    }

    // MARK: - EPUB / PDF need no offsets

    @Test("an indexed EPUB/PDF is searchable with no offsets to restore", arguments: ["epub", "pdf"])
    func epubPdfSearchableNoOffsets(format: String) {
        // Even with requiresReindex true / offsets nil, non-offset formats search
        // fine — those flags only matter for TXT/MD.
        #expect(LibraryBookSearchGate.evaluate(format: format, state: state(reindex: true, offsets: nil))
            == .searchable(restoreOffsets: nil))
    }

    // MARK: - TXT / MD staleness guards

    @Test("a TXT/MD book needing reindex is excluded (offsets may mis-align)", arguments: ["txt", "md"])
    func txtMdRequiresReindexExcluded(format: String) {
        #expect(LibraryBookSearchGate.evaluate(
            format: format, state: state(reindex: true, offsets: [0: 0]))
            == .excluded(.requiresReindex))
    }

    @Test("an indexed TXT/MD book with NIL offsets is excluded as stale", arguments: ["txt", "md"])
    func txtMdNilOffsetsExcluded(format: String) {
        #expect(LibraryBookSearchGate.evaluate(format: format, state: state(offsets: nil))
            == .excluded(.staleOffsets))
    }

    @Test("an indexed, non-stale TXT/MD book with offsets is searchable + restores them", arguments: ["txt", "md"])
    func txtMdGoodSearchableRestores(format: String) {
        let offsets = [0: 0, 1: 4096]
        #expect(LibraryBookSearchGate.evaluate(format: format, state: state(offsets: offsets))
            == .searchable(restoreOffsets: offsets))
    }

    // MARK: - requiresSegmentOffsets predicate

    @Test("only txt + md require segment offsets")
    func offsetFormats() {
        #expect(LibraryBookSearchGate.requiresSegmentOffsets("txt"))
        #expect(LibraryBookSearchGate.requiresSegmentOffsets("md"))
        #expect(!LibraryBookSearchGate.requiresSegmentOffsets("epub"))
        #expect(!LibraryBookSearchGate.requiresSegmentOffsets("pdf"))
    }
}
