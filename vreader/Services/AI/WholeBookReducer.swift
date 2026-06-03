// Purpose: The off-main-actor hierarchical map-reduce that condenses a whole book
// into a budget-capped digest for the AI Chat "Whole book" scope (Feature #86
// WI-5a). NOT linear accumulation: the per-request ceiling is ~12k UTF-16, so a
// 13M-char CJK book is split into bounded chunks, each condensed, then
// groups-of-condensations reduced again, repeating until the digest fits the
// budget.
//
// Design (Gate-2-approved):
// - An `actor` so all the chunking / slicing / prompting runs off the main actor.
// - The per-chunk AI call is an INJECTED `condense` closure (the production wiring
//   captures one pinned `ResolvedAIProviderConfig` and calls
//   `AIService.sendRequest(_:using:)`), so the reducer is fully unit-testable with
//   a fake closure and pins one provider snapshot for the whole job.
// - Progress is delivered through an `async` `onProgress` callback the caller
//   awaits, so updates are ORDERED (no reorder race) — the @MainActor VM hops via
//   `await MainActor.run`.
// - Cancellation: the VM calls `cancel()` (sets an actor flag, serialized by actor
//   reentrancy at the await points), NOT the consuming Task. `reduce` checks the
//   flag between chunks and returns a PARTIAL digest with structured coverage —
//   never throws on cancel, never drops what was already read.
// - Overflow policy: bound the total provider-call budget (`maxChunks`). A book
//   over the bound is read as a BOUNDED digest (a prefix of chunks) and reports a
//   non-complete `WholeBookCoverage` with logged `droppedSpans` — never a silent
//   truncation.
//
// @coordinates-with: WholeBookRetrievalViewModel.swift (WI-5b), AIService.swift,
//   ResolvedAIProviderConfig.swift, UTF16Clamp.swift,
//   `dev-docs/plans/20260603-feature-86-wi2-chat-scope-sources-retrieval.md`

import Foundation
import OSLog

/// Structured coverage of what a whole-book read actually covered.
struct WholeBookCoverage: Sendable, Equatable {
    /// UTF-16 spans (inclusive) actually read into the digest.
    let coveredSpans: [ClosedRange<Int>]
    /// Total UTF-16 length of the book.
    let totalUTF16: Int
    /// UTF-16 spans deliberately NOT read (overflow drop / cancel) — never silent.
    let droppedSpans: [ClosedRange<Int>]

    var coveredUTF16: Int {
        coveredSpans.reduce(0) { $0 + ($1.upperBound - $1.lowerBound + 1) }
    }
    /// Covered fraction of the book, clamped to [0, 1].
    var fraction: Double {
        guard totalUTF16 > 0 else { return 0 }
        return min(1, max(0, Double(coveredUTF16) / Double(totalUTF16)))
    }
    /// True only when nothing was dropped AND the whole book was covered.
    var isComplete: Bool {
        droppedSpans.isEmpty && coveredUTF16 >= totalUTF16
    }
}

/// The whole-book digest + its coverage. The digest becomes the Chat scope text
/// for the `.wholeBook` scope once `.ready`.
struct WholeBookDigest: Sendable, Equatable {
    let context: String
    let coverage: WholeBookCoverage

    static func empty(totalUTF16: Int) -> WholeBookDigest {
        WholeBookDigest(
            context: "",
            coverage: WholeBookCoverage(coveredSpans: [], totalUTF16: totalUTF16, droppedSpans: [])
        )
    }
}

/// The off-actor whole-book reducer.
actor WholeBookReducer {

    private let log = Logger(subsystem: "com.vreader.app", category: "WholeBookReducer")
    private var isCancelled = false

    /// Requests cancellation. The in-flight `reduce` sees it at its next
    /// between-chunk check (actor reentrancy at the await points serializes this)
    /// and returns a partial digest. Idempotent.
    func cancel() { isCancelled = true }

    /// Resets the cancelled flag for a fresh read (a re-arm after a partial).
    func reset() { isCancelled = false }

    /// One chunk of the book: its text + its UTF-16 span in the full text.
    /// Internal (not private) so the pure static `chunk(_:budgetUTF16:)` can return
    /// it and unit tests can assert on the spans.
    struct Chunk: Sendable, Equatable {
        let text: String
        let span: ClosedRange<Int>
    }

    /// Condenses `fullText` into a digest of at most `digestBudgetUTF16` UTF-16
    /// units, calling `condense` once per chunk (and again per reduce-group when
    /// the first pass overflows). Reports progress through `onProgress` (awaited,
    /// so ordered). Returns a partial digest on cancellation — never throws on
    /// cancel.
    ///
    /// - Parameters:
    ///   - chunkBudgetUTF16: max UTF-16 per chunk fed to `condense` (≤ the request ceiling).
    ///   - digestBudgetUTF16: the final digest's UTF-16 ceiling.
    ///   - maxChunks: overflow bound on total `condense` calls in the first pass.
    ///   - condense: the per-chunk AI condensation (injected; pins the provider).
    ///   - onProgress: awaited progress (done, total) callback — ordered.
    func reduce(
        fullText: String,
        chunkBudgetUTF16: Int,
        digestBudgetUTF16: Int,
        maxChunks: Int,
        condense: @Sendable (String) async throws -> String,
        onProgress: @Sendable (Int, Int) async -> Void
    ) async throws -> WholeBookDigest {
        let totalUTF16 = fullText.utf16.count
        guard totalUTF16 > 0 else { return .empty(totalUTF16: 0) }
        // Invalid budgets on a NON-empty book → honest "all dropped" coverage,
        // not an empty span set (Gate-4 Low).
        guard chunkBudgetUTF16 > 0, digestBudgetUTF16 > 0, maxChunks > 0 else {
            return WholeBookDigest(
                context: "",
                coverage: WholeBookCoverage(coveredSpans: [], totalUTF16: totalUTF16,
                                            droppedSpans: [0...(totalUTF16 - 1)])
            )
        }

        let allChunks = Self.chunk(fullText, budgetUTF16: chunkBudgetUTF16)
        // Overflow policy: keep the first `maxChunks`; the remainder is dropped
        // (logged + reported), never silently truncated.
        let kept = Array(allChunks.prefix(maxChunks))
        let droppedChunks = Array(allChunks.dropFirst(maxChunks))
        if !droppedChunks.isEmpty {
            log.info("whole-book overflow: \(droppedChunks.count) of \(allChunks.count) chunks dropped (maxChunks=\(maxChunks))")
        }

        // Map: condense each kept chunk, checking cancellation around EVERY await
        // (Gate-4 Medium — a cancel during `onProgress` must not start one more call).
        var condensed: [String] = []
        var coveredSpans: [ClosedRange<Int>] = []
        let total = kept.count
        for (index, chunk) in kept.enumerated() {
            if isCancelled { break }
            await onProgress(index, total)
            if isCancelled { break }
            let result = try await condense(chunk.text)
            condensed.append(result)
            coveredSpans.append(chunk.span)
        }
        if !isCancelled { await onProgress(condensed.count, total) }

        // Reduce: hierarchically re-condense until the digest fits the budget.
        // Commit a round's output ONLY when the round COMPLETES — a cancel
        // mid-round discards the partial round and keeps the last full level
        // (Gate-4 High: never drop what was already condensed).
        var digestText = condensed.joined(separator: "\n\n")
        var guardRounds = 0
        while digestText.utf16.count > digestBudgetUTF16, !isCancelled, guardRounds < 8 {
            guardRounds += 1
            // Normalize: re-chunk any piece that grew past the chunk budget so every
            // recursive `condense` input stays ≤ chunkBudget (Gate-4 High).
            let normalized = condensed.flatMap { piece -> [String] in
                piece.utf16.count <= chunkBudgetUTF16
                    ? [piece]
                    : Self.chunk(piece, budgetUTF16: chunkBudgetUTF16).map(\.text)
            }
            let groups = Self.group(normalized, budgetUTF16: chunkBudgetUTF16)
            var nextLevel: [String] = []
            var roundCancelled = false
            for group in groups {
                if isCancelled { roundCancelled = true; break }
                nextLevel.append(try await condense(group))
            }
            if roundCancelled { break }   // discard partial round; keep `digestText`
            condensed = nextLevel
            digestText = condensed.joined(separator: "\n\n")
        }

        // The dropped (overflow) + the uncovered-on-cancel spans.
        var droppedSpans = droppedChunks.map(\.span)
        if isCancelled {
            // Spans of kept chunks we never reached.
            let reached = coveredSpans.count
            droppedSpans.append(contentsOf: kept.dropFirst(reached).map(\.span))
        }

        let coverage = WholeBookCoverage(
            coveredSpans: coveredSpans, totalUTF16: totalUTF16, droppedSpans: droppedSpans
        )
        return WholeBookDigest(
            context: UTF16Clamp.clamp(digestText, maxUTF16: digestBudgetUTF16),
            coverage: coverage
        )
    }

    // MARK: - Chunking (pure, static — testable in isolation)

    /// Splits `text` into chunks of at most `budgetUTF16` UTF-16 units at
    /// Character boundaries (CJK-safe), recording each chunk's UTF-16 span.
    static func chunk(_ text: String, budgetUTF16: Int) -> [Chunk] {
        guard budgetUTF16 > 0, !text.isEmpty else { return [] }
        var chunks: [Chunk] = []
        var spanStart = 0           // UTF-16 offset of the current chunk start
        var current = ""
        var currentUTF16 = 0
        for ch in text {
            let chLen = ch.utf16.count
            if currentUTF16 + chLen > budgetUTF16, !current.isEmpty {
                chunks.append(Chunk(text: current, span: spanStart...(spanStart + currentUTF16 - 1)))
                spanStart += currentUTF16
                current = ""
                currentUTF16 = 0
            }
            current.append(ch)
            currentUTF16 += chLen
        }
        if !current.isEmpty {
            chunks.append(Chunk(text: current, span: spanStart...(spanStart + currentUTF16 - 1)))
        }
        return chunks
    }

    /// Groups already-condensed strings into joined batches of at most
    /// `budgetUTF16` UTF-16 units, for the next reduce level.
    static func group(_ pieces: [String], budgetUTF16: Int) -> [String] {
        guard budgetUTF16 > 0 else { return pieces }
        var groups: [String] = []
        var current = ""
        for piece in pieces {
            let candidate = current.isEmpty ? piece : current + "\n\n" + piece
            if candidate.utf16.count > budgetUTF16, !current.isEmpty {
                groups.append(current)
                current = piece
            } else {
                current = candidate
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
}
