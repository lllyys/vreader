// Purpose: Tests for ChapterTranslationChunker — groups translation segment
// indices into provider-budget-bounded chunks for feature #56 bilingual reading.
//
// @coordinates-with: ChapterTranslationChunker.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-4)

import Testing
import Foundation
@testable import vreader

@Suite("ChapterTranslationChunker")
struct ChapterTranslationChunkerTests {

    @Test func emptySegmentsYieldNoChunks() {
        let chunks = ChapterTranslationChunker.chunk(segments: [], maxCharsPerChunk: 100)
        #expect(chunks.isEmpty)
    }

    @Test func singleSmallSegmentIsOneChunk() {
        let chunks = ChapterTranslationChunker.chunk(segments: ["hello"], maxCharsPerChunk: 100)
        #expect(chunks == [[0]])
    }

    @Test func manyTinySegmentsPackIntoFewChunks() {
        // 6 segments of 10 chars each, budget 25 → chunks of 2 ([0,1],[2,3],[4,5]).
        let segments = Array(repeating: String(repeating: "x", count: 10), count: 6)
        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 25)
        #expect(chunks == [[0, 1], [2, 3], [4, 5]])
    }

    @Test func segmentsNeverSplitAcrossChunks() {
        // Every index appears exactly once, in order, with no index dropped.
        let segments = (0..<20).map { String(repeating: "y", count: $0 % 7 + 1) }
        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 12)
        let flattened = chunks.flatMap { $0 }
        #expect(flattened == Array(0..<20))
    }

    @Test func oneOverBudgetSegmentGetsItsOwnChunk() {
        // A segment larger than the whole budget cannot be split — it occupies
        // its own chunk (edge case (a)). Recombination is the caller's job.
        let segments = ["small", String(repeating: "z", count: 500), "tiny"]
        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 100)
        #expect(chunks.contains([1]))
        // The over-budget segment is isolated; small + tiny are not lost.
        let flattened = chunks.flatMap { $0 }
        #expect(Set(flattened) == [0, 1, 2])
    }

    @Test func consecutiveOverBudgetSegmentsEachGetOwnChunk() {
        let big = String(repeating: "b", count: 200)
        let segments = [big, big, big]
        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 100)
        #expect(chunks == [[0], [1], [2]])
    }

    @Test func exactBoundary_segmentsSummingToExactlyBudgetShareAChunk() {
        // Two 50-char segments, budget 100 → they fit together in one chunk.
        let segments = [String(repeating: "a", count: 50), String(repeating: "b", count: 50)]
        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 100)
        #expect(chunks == [[0, 1]])
    }

    @Test func exactBoundary_oneOverStartsANewChunk() {
        // 50 + 51 = 101 > 100 → the 51-char segment starts a new chunk.
        let segments = [String(repeating: "a", count: 50), String(repeating: "b", count: 51)]
        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 100)
        #expect(chunks == [[0], [1]])
    }

    @Test func cjkCharactersCountedByCharacterNotByte() {
        // CJK chars are multi-byte in UTF-8 but the budget is a CHARACTER count.
        // 4 CJK chars × 3 segments, budget 8 chars → chunks of 2 segments.
        let segments = Array(repeating: "你好世界", count: 3)
        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 8)
        #expect(chunks == [[0, 1], [2]])
    }

    @Test func emptyStringSegmentsAreStillIndexed() {
        // Empty segments cost 0 chars but still occupy an index.
        let segments = ["", "", "real"]
        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 10)
        let flattened = chunks.flatMap { $0 }
        #expect(flattened == [0, 1, 2])
    }

    @Test func zeroBudgetIsCoercedToOne_eachNonEmptySegmentOwnsAChunk() {
        // A non-positive budget is defensively coerced to 1 (documented) — the
        // function never divides by zero or loops, and the flattening
        // invariant still holds.
        let segments = ["a", "b", "c"]
        let chunks = ChapterTranslationChunker.chunk(segments: segments, maxCharsPerChunk: 0)
        #expect(chunks.flatMap { $0 } == [0, 1, 2])
        #expect(chunks.count == 3)
    }

    @Test func negativeBudgetIsAlsoCoercedSafely() {
        let chunks = ChapterTranslationChunker.chunk(segments: ["x", "y"], maxCharsPerChunk: -5)
        #expect(chunks.flatMap { $0 } == [0, 1])
    }

    // MARK: - Bug #330: subSplit (oversized-paragraph sub-splitting)

    @Test func subSplit_underBudget_returnsUnchanged() {
        #expect(ChapterTranslationChunker.subSplit("hello", maxChars: 10) == ["hello"])
        #expect(ChapterTranslationChunker.subSplit("", maxChars: 10) == [""])
    }

    @Test func subSplit_overBudget_piecesAreUnderBudget_andRejoinLossless() {
        let text = "one two three four five six seven eight"  // spaced, > 10
        let pieces = ChapterTranslationChunker.subSplit(text, maxChars: 10)
        #expect(pieces.count > 1)
        #expect(pieces.allSatisfy { $0.count <= 10 })
        #expect(pieces.joined() == text, "concatenation is lossless")
    }

    @Test func subSplit_breaksAtWhitespace_notMidWord() {
        // "alpha beta" is 10 chars; the split should keep "alpha " then "beta".
        let pieces = ChapterTranslationChunker.subSplit("alpha beta gamma", maxChars: 10)
        #expect(pieces.first == "alpha ", "broke at the whitespace within the window")
        #expect(pieces.joined() == "alpha beta gamma")
    }

    @Test func subSplit_cjkNoWhitespace_hardSplitsAtBudget() {
        let text = String(repeating: "字", count: 25)   // 25 CJK chars, no spaces
        let pieces = ChapterTranslationChunker.subSplit(text, maxChars: 10)
        #expect(pieces.map(\.count) == [10, 10, 5])
        #expect(pieces.joined() == text)
    }

    @Test func subSplit_multiScalarGraphemes_neverSplitAGrapheme() {
        // Family emoji are single Characters made of multiple scalars/surrogates.
        let text = String(repeating: "👨‍👩‍👧", count: 8)  // 8 graphemes
        let pieces = ChapterTranslationChunker.subSplit(text, maxChars: 3)
        #expect(pieces.allSatisfy { $0.count <= 3 })
        #expect(pieces.joined() == text, "no grapheme/surrogate split — lossless rejoin")
    }
}
