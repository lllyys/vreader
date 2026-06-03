// Purpose: The thin @MainActor state-machine mirror over the off-actor
// WholeBookReducer (Feature #86 WI-5b). It owns ONLY the UI phase + progress; the
// chunking / prompting / reduction all run inside the reducer actor. Drives the
// context bar's Armed / Reading% / Ready / Partial states.
//
// Cancellation (Gate-2-approved): `cancel()` calls `reducer.cancel()` (NOT the
// consuming task), and the read keeps running until the reducer returns its
// terminal PARTIAL digest — so `.partial(coverage)` is always set from real
// structured coverage, never a phantom revert.
//
// @coordinates-with: WholeBookReducer.swift, ReaderAICoordinator.swift,
//   ChatRetrievalCluster.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/chat-ai-scope-sources.md`

import Foundation

@MainActor
@Observable
final class WholeBookRetrievalViewModel {

    enum Phase: Sendable, Equatable {
        case idle
        case armed                              // "Reads on your next question"
        case reading(done: Int, total: Int)     // "Reading the whole book… 38%"
        case ready(WholeBookCoverage)           // "Indexed · ready"
        case partial(WholeBookCoverage)         // cancelled / incomplete — NOT auto-ready
    }

    private(set) var phase: Phase = .idle
    private(set) var digest: WholeBookDigest?
    /// The consuming read task (exposed for tests to await; NOT the cancel lever).
    private(set) var readTask: Task<Void, Never>?

    private let reducer: WholeBookReducer

    init(reducer: WholeBookReducer = WholeBookReducer()) {
        self.reducer = reducer
    }

    /// Arms whole-book retrieval — the next question triggers the read.
    func arm() {
        switch phase {
        case .idle, .partial, .ready: phase = .armed
        case .armed, .reading: break
        }
    }

    /// Resets to idle (e.g. when the user switches away from whole-book scope).
    func disarm() {
        readTask?.cancel()
        phase = .idle
    }

    /// Requests cancellation of an in-flight read. Cancels the REDUCER (not the
    /// consuming task), so the read finishes with the partial digest and lands in
    /// `.partial`. Keeps everything already indexed.
    func cancel() {
        let reducer = self.reducer
        Task { await reducer.cancel() }
    }

    /// Starts a whole-book read. `condense` is the injected per-chunk AI call (the
    /// coordinator pins one provider snapshot). On completion the phase becomes
    /// `.ready` (full coverage) or `.partial` (cancelled / overflow).
    func read(
        fullText: String,
        chunkBudgetUTF16: Int,
        digestBudgetUTF16: Int,
        maxChunks: Int,
        condense: @escaping @Sendable (String) async throws -> String
    ) {
        readTask?.cancel()
        phase = .reading(done: 0, total: 0)
        let reducer = self.reducer
        readTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await reducer.reset()
            do {
                let digest = try await reducer.reduce(
                    fullText: fullText,
                    chunkBudgetUTF16: chunkBudgetUTF16,
                    digestBudgetUTF16: digestBudgetUTF16,
                    maxChunks: maxChunks,
                    condense: condense,
                    onProgress: { done, total in
                        await MainActor.run { [weak self] in
                            self?.phase = .reading(done: done, total: total)
                        }
                    }
                )
                self.digest = digest
                self.phase = digest.coverage.isComplete
                    ? .ready(digest.coverage)
                    : .partial(digest.coverage)
            } catch {
                // A read failure → partial with whatever coverage the reducer last
                // reported (or empty), so the UI never claims a phantom "ready".
                let coverage = self.digest?.coverage
                    ?? WholeBookCoverage(coveredSpans: [], totalUTF16: fullText.utf16.count, droppedSpans: [])
                self.phase = .partial(coverage)
            }
        }
    }

    /// 0…1 progress for the reading bar.
    var progressFraction: Double {
        switch phase {
        case let .reading(done, total): return total > 0 ? min(1, Double(done) / Double(total)) : 0
        case let .ready(c): return c.fraction
        case let .partial(c): return c.fraction
        case .idle, .armed: return 0
        }
    }

    /// The "23 / 61" unit label shown while reading (chunks read / total).
    var unitProgressLabel: String {
        if case let .reading(done, total) = phase, total > 0 { return "\(done) / \(total)" }
        return ""
    }

    /// Whether a whole-book digest is ready to use as the chat scope text.
    var isReady: Bool { if case .ready = phase { return true } else { return false } }

    /// The digest's context when `.ready` or `.partial` — usable as scope text.
    var availableContext: String? {
        switch phase {
        case .ready, .partial: return digest?.context
        case .idle, .armed, .reading: return nil
        }
    }
}
