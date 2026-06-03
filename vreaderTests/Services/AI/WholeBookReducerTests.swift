// Feature #86 WI-5a: the off-actor WholeBookReducer — hierarchical map-reduce,
// overflow policy, cancellation (partial digest, never throw), and the structured
// WholeBookCoverage. The per-chunk AI call is an injected `condense` closure, so
// these run with a fake — no AIService.

import Testing
import Foundation
@testable import vreader

/// Records condense calls (and can trigger a cancel mid-read deterministically).
private actor CondenseRecorder {
    private(set) var calls = 0
    private(set) var seenChunks: [String] = []
    func record(_ chunk: String) { calls += 1; seenChunks.append(chunk) }
}

@Suite("WholeBookReducer (Feature #86 WI-5a)")
struct WholeBookReducerTests {

    // MARK: - Chunking (pure)

    @Test func chunk_splitsAtBudget_withContiguousSpans() {
        let text = String(repeating: "a", count: 250)
        let chunks = WholeBookReducer.chunk(text, budgetUTF16: 100)
        #expect(chunks.count == 3)                       // 100 + 100 + 50
        #expect(chunks.allSatisfy { $0.text.utf16.count <= 100 })
        // Spans are contiguous and cover [0, 249].
        #expect(chunks.first?.span.lowerBound == 0)
        #expect(chunks.last?.span.upperBound == 249)
        for i in 1..<chunks.count {
            #expect(chunks[i].span.lowerBound == chunks[i - 1].span.upperBound + 1)
        }
    }

    @Test func chunk_cjkNeverSplitsAScalar() {
        let text = String(repeating: "字", count: 100)   // 100 UTF-16 units
        let chunks = WholeBookReducer.chunk(text, budgetUTF16: 30)
        for c in chunks {
            #expect(c.text.utf16.count <= 30)
            #expect(!c.text.unicodeScalars.contains("\u{FFFD}"))
        }
        #expect(chunks.map(\.text).joined() == text)     // lossless
    }

    @Test func chunk_emptyOrZeroBudget_isEmpty() {
        #expect(WholeBookReducer.chunk("", budgetUTF16: 100).isEmpty)
        #expect(WholeBookReducer.chunk("abc", budgetUTF16: 0).isEmpty)
    }

    @Test func group_batchesUnderBudget() {
        let pieces = ["aaa", "bbb", "ccc", "ddd"]   // 3 each; +2 separator
        let groups = WholeBookReducer.group(pieces, budgetUTF16: 8)
        #expect(groups.allSatisfy { $0.utf16.count <= 8 })
        #expect(groups.joined(separator: "\n\n").contains("aaa"))
    }

    // MARK: - reduce()

    private func runReduce(
        text: String, chunkBudget: Int, digestBudget: Int, maxChunks: Int,
        condense: @escaping @Sendable (String) async throws -> String
    ) async throws -> WholeBookDigest {
        let reducer = WholeBookReducer()
        return try await reducer.reduce(
            fullText: text, chunkBudgetUTF16: chunkBudget, digestBudgetUTF16: digestBudget,
            maxChunks: maxChunks, condense: condense, onProgress: { _, _ in }
        )
    }

    @Test func reduce_condensesEachChunk_coversWholeBook() async throws {
        let rec = CondenseRecorder()
        let text = String(repeating: "x", count: 300)   // 3 chunks at budget 100
        let digest = try await runReduce(text: text, chunkBudget: 100, digestBudget: 10_000, maxChunks: 10) { chunk in
            await rec.record(chunk)
            return "[sum:\(chunk.utf16.count)]"
        }
        #expect(await rec.calls == 3)                    // one per chunk, no reduce round needed
        #expect(digest.coverage.isComplete)              // whole book covered, nothing dropped
        #expect(digest.coverage.fraction == 1.0)
        #expect(digest.context.contains("[sum:100]"))
    }

    @Test func reduce_hierarchical_collapsesToBudget() async throws {
        let rec = CondenseRecorder()
        // 10 chunks; each condensation is ~50 chars → first-pass digest ~500 > 120
        // budget → forces at least one reduce round.
        let text = String(repeating: "y", count: 1000)
        let digest = try await runReduce(text: text, chunkBudget: 100, digestBudget: 120, maxChunks: 50) { chunk in
            await rec.record(chunk)
            return String(repeating: "S", count: 50)
        }
        #expect(digest.context.utf16.count <= 120)       // collapsed under budget
        #expect(await rec.calls > 10)                    // 10 map + ≥1 reduce-group call
        #expect(digest.coverage.isComplete)
    }

    @Test func reduce_overflow_boundedDigest_reportsDropped() async throws {
        let text = String(repeating: "z", count: 1000)   // 10 chunks at budget 100
        let digest = try await runReduce(text: text, chunkBudget: 100, digestBudget: 10_000, maxChunks: 3) { _ in "s" }
        #expect(!digest.coverage.isComplete)             // not the whole book
        #expect(!digest.coverage.droppedSpans.isEmpty)   // the 7 dropped chunks
        #expect(digest.coverage.coveredSpans.count == 3) // only maxChunks read
    }

    @Test func reduce_cancelMidRead_returnsPartial_doesNotThrow() async throws {
        let reducer = WholeBookReducer()
        let rec = CondenseRecorder()
        let text = String(repeating: "w", count: 1000)   // 10 chunks at budget 100
        // The condense closure cancels the reducer on the 2nd chunk call.
        let digest = try await reducer.reduce(
            fullText: text, chunkBudgetUTF16: 100, digestBudgetUTF16: 10_000, maxChunks: 50,
            condense: { chunk in
                await rec.record(chunk)
                if await rec.calls == 2 { await reducer.cancel() }
                return "s"
            },
            onProgress: { _, _ in }
        )
        // EXACTLY 2 chunks condensed before the cancel breaks the loop (Gate-4: the
        // re-check after onProgress prevents a 3rd call).
        #expect(await rec.calls == 2)
        #expect(digest.coverage.coveredSpans.count == 2)
        #expect(!digest.coverage.isComplete)
        #expect(digest.coverage.droppedSpans.count == 8)   // the 8 unread chunks
    }

    /// Gate-4 High: a cancel DURING a hierarchical reduce round discards the partial
    /// round and keeps the last fully-completed level — never dropping covered text.
    @Test func reduce_cancelDuringReduceRound_keepsFullMapLevel() async throws {
        let reducer = WholeBookReducer()
        let rec = CondenseRecorder()
        let text = String(repeating: "y", count: 1000)   // 10 chunks
        // 10 summaries × 50 chars = ~500 joined > 120 budget → forces a reduce round;
        // cancel on call #11 (the first reduce-group condense).
        let digest = try await reducer.reduce(
            fullText: text, chunkBudgetUTF16: 100, digestBudgetUTF16: 120, maxChunks: 50,
            condense: { input in
                await rec.record(input)
                if await rec.calls == 11 { await reducer.cancel() }
                return String(repeating: "S", count: 50)
            },
            onProgress: { _, _ in }
        )
        // The MAP covered the whole book (10 chunks) before the reduce-round cancel.
        #expect(digest.coverage.coveredSpans.count == 10)
        #expect(digest.coverage.isComplete)               // book fully read; only the reduce was cut
        #expect(digest.context.utf16.count <= 120)        // still clamped to the budget
    }

    /// Gate-4 High: an oversized `condense` output is re-chunked before the next
    /// round, so NO recursive condense input ever exceeds `chunkBudgetUTF16`.
    @Test func reduce_oversizedSummary_neverExceedsChunkBudget() async throws {
        let reducer = WholeBookReducer()
        let rec = CondenseRecorder()
        let text = String(repeating: "y", count: 600)    // 6 chunks at budget 100
        // condense returns a 250-char summary (> the 100 chunk budget) → without the
        // normalize re-chunk, a reduce group would feed an over-budget input back in.
        _ = try await reducer.reduce(
            fullText: text, chunkBudgetUTF16: 100, digestBudgetUTF16: 200, maxChunks: 50,
            condense: { input in await rec.record(input); return String(repeating: "S", count: 250) },
            onProgress: { _, _ in }
        )
        let inputs = await rec.seenChunks
        #expect(inputs.allSatisfy { $0.utf16.count <= 100 })   // every condense input within budget
    }

    @Test func reduce_invalidBudget_nonEmptyBook_reportsAllDropped() async throws {
        let digest = try await runReduce(text: "abc", chunkBudget: 100, digestBudget: 100, maxChunks: 0) { _ in "s" }
        #expect(digest.context.isEmpty)
        #expect(!digest.coverage.isComplete)
        #expect(digest.coverage.droppedSpans == [0...2])    // whole non-empty book dropped, honestly
    }

    @Test func reduce_emptyBook_isEmptyDigest() async throws {
        let digest = try await runReduce(text: "", chunkBudget: 100, digestBudget: 100, maxChunks: 10) { _ in "s" }
        #expect(digest.context.isEmpty)
        #expect(digest.coverage.coveredSpans.isEmpty)
    }

    // MARK: - WholeBookCoverage

    @Test func coverage_fractionAndComplete() {
        let full = WholeBookCoverage(coveredSpans: [0...99], totalUTF16: 100, droppedSpans: [])
        #expect(full.fraction == 1.0)
        #expect(full.isComplete)

        let partial = WholeBookCoverage(coveredSpans: [0...49], totalUTF16: 100, droppedSpans: [50...99])
        #expect(partial.fraction == 0.5)
        #expect(!partial.isComplete)

        let empty = WholeBookCoverage(coveredSpans: [], totalUTF16: 0, droppedSpans: [])
        #expect(empty.fraction == 0)
    }
}
