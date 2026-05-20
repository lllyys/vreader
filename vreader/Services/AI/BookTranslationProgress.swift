// Purpose: Feature #56 WI-14 — value types for the global "translate
// entire book" flow. `BookTranslationProgress` is the snapshot the UI
// observes through `BookTranslationCoordinator.progressUpdates(...)`;
// `BookTranslationEstimate` is the up-front confirm-alert payload
// returned by `estimate(...)`.
//
// Key decisions:
// - Plain `Sendable` value types (struct + enum) so they can flow
//   across actor hops between the coordinator, the view model, and
//   notification userInfo dictionaries without isolation ceremony.
// - `fraction` is `0.0` on a zero-total book — NOT `Double.nan` from
//   `0/0`. The plan explicitly calls out the zero-unit book completing
//   at 0/0 with no error; the UI displays a progress bar at 0% (a
//   degenerate but valid state) rather than rendering NaN.
// - `phase` is a single enum rather than booleans so observers can
//   pattern-match exhaustively (idle / running / completed / cancelled
//   / failed). Convenience computed properties (`isRunning`, `isFinished`,
//   `isCancelled`) keep the consumer code readable.
//
// @coordinates-with: BookTranslationCoordinator.swift,
//   BookTranslationViewModel.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-14)

import Foundation

/// A snapshot of a global book-translation job. Emitted by
/// `BookTranslationCoordinator.progressUpdates(...)` so the UI badge,
/// banner, and status sheet can re-render whenever a unit finishes.
struct BookTranslationProgress: Sendable, Equatable {

    /// The lifecycle phase the job is currently in.
    enum Phase: String, Sendable, Equatable {
        /// No job has been started for this book yet.
        case idle
        /// A job is running — at least one unit has been claimed.
        case running
        /// Every translation unit finished successfully.
        case completed
        /// The user cancelled mid-run; `completed` carries the partial
        /// count of units that finished before cancellation.
        case cancelled
        /// A provider error stopped the job; `completed` carries the
        /// partial count of units that finished before the failure.
        case failed
    }

    let phase: Phase

    /// Number of translation units finished so far. Monotonic per phase
    /// (cancellation freezes the count; a fresh `start` zeroes it).
    let completed: Int

    /// Total translation units the job will cover. A book with zero
    /// units uses `total == 0` and completes immediately.
    let total: Int

    /// `true` while a job is actively claiming and translating units.
    var isRunning: Bool { phase == .running }

    /// `true` once every unit translated successfully.
    var isFinished: Bool { phase == .completed }

    /// `true` when the user cancelled before completion.
    var isCancelled: Bool { phase == .cancelled }

    /// Progress in `[0, 1]`. Zero-total books report `0.0` rather than
    /// `Double.nan` so a binding progress bar stays renderable.
    var fraction: Double {
        guard total > 0 else { return 0.0 }
        return Double(completed) / Double(total)
    }

    /// An idle snapshot for a freshly-loaded book — no completed units,
    /// known total.
    static func idle(total: Int) -> BookTranslationProgress {
        BookTranslationProgress(phase: .idle, completed: 0, total: total)
    }
}

/// The up-front estimate `BookTranslationCoordinator.estimate(...)`
/// returns so the confirm alert can show "N chapters, ~X tokens" without
/// committing the user to a multi-minute API operation.
struct BookTranslationEstimate: Sendable, Equatable {

    /// How many translation units the open book contains (the work the
    /// user is about to commit to).
    let unitCount: Int

    /// Rough upper-bound on input tokens the operation will spend, or
    /// `nil` when the coordinator could not sample enough unit text to
    /// produce a meaningful estimate. Computed as `≈ totalChars / 4`
    /// (a generous OpenAI/Anthropic rule-of-thumb for English; CJK
    /// counts slightly more per token but the 4:1 ratio is the
    /// standard public-facing approximation). Whole-book translation
    /// approximately doubles this in practice once output tokens are
    /// counted in.
    let approximateInputTokens: Int?

    init(unitCount: Int, approximateInputTokens: Int? = nil) {
        self.unitCount = unitCount
        self.approximateInputTokens = approximateInputTokens
    }
}
