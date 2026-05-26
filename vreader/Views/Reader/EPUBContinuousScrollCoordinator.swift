// Purpose: Host-side window-transition decision logic for the EPUB
// continuous-scroll multi-chapter document (feature #71, WI-4). Owns the
// current `EPUBSpineWindow` and, on each `EPUBScrollBoundarySignal` from the
// in-page scroll observer (`EPUBContinuousScrollJS.continuousScrollObserverJS`),
// decides whether to materialize the next/previous chapter and which far-end
// chapters to evict — emitting the corresponding section JS through an
// injected async-throwing evaluator. No live WKWebView here; the bridge
// wiring lands in WI-5, so the whole policy is unit-testable with a recording
// stub evaluator + a stub chapter-body provider.
//
// Key decisions (carry the Gate-2 audit findings):
// - **Async-throwing evaluator** (`evaluate: @MainActor (String) async throws
//   -> Void`) — round-1 [H4]: a `(String) -> Void` closure cannot observe a
//   failed JS insert, but the policy REQUIRES "window state must not advance
//   if the DOM insert failed". The window mutates ONLY after a successful
//   `evaluate`.
// - **Generation token** (`UUID`, bumped via `bumpGeneration()` /
//   `reset(to:)` on mode-switch / reopen / book-change) — round-1 [H4]: a
//   stale `chapterBodyProvider` task that resolves AFTER a switch is
//   discarded (its post-await generation check fails) so it never evals or
//   mutates the new window.
// - **One materialization in flight per generation** — the idempotency guard:
//   a duplicate boundary signal arriving while a fetch+append is in flight is
//   ignored (no double-append). Tied to the generation so a post-`bump`
//   signal is NOT blocked by the prior generation's in-flight marker.
// - **Re-anchor to `visibleSpineIndex`** every signal (pure bookkeeping, no
//   DOM): `EPUBSpineWindow.reanchored(to:)` moves the eviction anchor to the
//   chapter the reader is actually in, so far-end eviction trims the chapters
//   behind/ahead of the reader — not the freshly-appended chapter.
//
// @coordinates-with: EPUBSpineWindow.swift, EPUBContinuousScrollJS.swift,
//   EPUBChapterBodyRewriter.swift (EPUBChapterBody),
//   EPUBWebViewBridge.swift (WI-5 caller),
//   dev-docs/plans/20260525-feature-71-epub-continuous-scroll.md (WI-4)

import Foundation
import OSLog

/// The parsed boundary signal posted by the continuous-scroll observer user
/// script. WI-5 decodes the `continuousScrollHandler` message into this;
/// WI-4's coordinator consumes it to decide window transitions.
struct EPUBScrollBoundarySignal: Equatable {
    /// The topmost spine index currently in the viewport.
    let visibleSpineIndex: Int
    /// How far through the visible section the viewport is (0...1).
    let intraFraction: Double
    /// The viewport is within the prefetch threshold of the column top.
    let nearTopBoundary: Bool
    /// The viewport is within the prefetch threshold of the column bottom.
    let nearBottomBoundary: Bool
}

/// `@MainActor` coordinator that turns boundary signals into materialize /
/// evict decisions over an `EPUBSpineWindow`, emitting section JS through an
/// async-throwing evaluator. The window mutates only after a successful eval.
@MainActor
final class EPUBContinuousScrollCoordinator {

    private static let log = Logger(subsystem: "com.vreader.app", category: "EPUBContinuousScroll")

    /// The currently-materialized chapter window. Mutated only after a
    /// successful section eval (extend/evict) or via re-anchor bookkeeping.
    private(set) var window: EPUBSpineWindow

    /// The current generation token. A materialization captures this at start
    /// and discards itself if it changes (mode-switch / reopen / book-change).
    private(set) var generation = UUID()

    /// The generation whose materialization is currently in flight (`nil` when
    /// idle). Gates re-entrancy: a second signal for the SAME generation is
    /// ignored while one is in flight, but a post-`bump` signal is not.
    private var inFlightGeneration: UUID?

    /// Max chapters kept materialized; the far-from-anchor end is evicted past
    /// this. Starts at 5 per the plan's memory budget (tuned in WI-6/WI-8).
    private let maxSpan: Int

    /// Supplies a rewritten chapter body for a spine index (WI-2 output).
    private let chapterBodyProvider: @MainActor (Int) async throws -> EPUBChapterBody

    /// Runs a JS snippet against the document; throws on failure so the window
    /// does not advance past a failed insert.
    private let evaluate: @MainActor (String) async throws -> Void

    /// Optional divider title for a spine index (chapter heading). `nil` ⇒ no
    /// divider. WI-6 supplies the TOC-title lookup; WI-4 defaults to none.
    private let dividerTitleProvider: @MainActor (Int) -> String?

    init(
        window: EPUBSpineWindow,
        maxSpan: Int = 5,
        chapterBodyProvider: @escaping @MainActor (Int) async throws -> EPUBChapterBody,
        evaluate: @escaping @MainActor (String) async throws -> Void,
        dividerTitleProvider: @escaping @MainActor (Int) -> String? = { _ in nil }
    ) {
        self.window = window
        self.maxSpan = max(maxSpan, 1)
        self.chapterBodyProvider = chapterBodyProvider
        self.evaluate = evaluate
        self.dividerTitleProvider = dividerTitleProvider
    }

    // MARK: - Generation control

    /// Bumps the generation token so any in-flight materialization is
    /// discarded before it can eval or mutate. Call on a live mode-switch.
    func bumpGeneration() {
        generation = UUID()
    }

    /// Replaces the window (e.g., a position-restore bootstrap window) and
    /// bumps the generation so a stale in-flight task does not mutate the new
    /// window.
    func reset(to window: EPUBSpineWindow) {
        self.window = window
        bumpGeneration()
    }

    // MARK: - Signal handling

    /// Processes one boundary signal: re-anchors to the visible chapter, then
    /// — if the viewport is near a book-interior edge — materializes the
    /// next/previous chapter and evicts the far end. A no-op at a book edge or
    /// when no boundary is near. Re-entrant-safe: one materialization per
    /// generation in flight.
    func handle(_ signal: EPUBScrollBoundarySignal) async {
        // One materialization per generation in flight (idempotency). Checked
        // FIRST so a duplicate signal arriving mid-flight is a complete no-op —
        // it must not mutate any shared state (incl. the eviction anchor).
        guard inFlightGeneration != generation else { return }

        // Re-anchor to the reader's visible chapter, but only as a LOCAL
        // snapshot — `window` (shared state) is committed solely after a
        // successful eval below, so a failed / no-op / blocked signal never
        // mutates the window or its eviction anchor (Gate-4 round-1 High).
        let anchored = window.reanchored(to: signal.visibleSpineIndex)

        let direction: Direction
        if signal.nearBottomBoundary, anchored.canExtendForward {
            direction = .forward
        } else if signal.nearTopBoundary, anchored.canExtendBackward {
            direction = .backward
        } else {
            return // at a book edge, or no boundary near → nothing to do
        }

        let gen = generation
        inFlightGeneration = gen
        defer { if inFlightGeneration == gen { inFlightGeneration = nil } }

        let targetIndex = direction == .forward ? anchored.hi + 1 : anchored.lo - 1

        // 1. Fetch the rewritten chapter body (may suspend).
        let body: EPUBChapterBody
        do {
            body = try await chapterBodyProvider(targetIndex)
        } catch {
            Self.log.error("chapterBodyProvider failed for spine \(targetIndex): \(String(describing: error), privacy: .public)")
            return // window NOT advanced
        }

        // Discard if a switch/reopen happened while we were fetching.
        guard generation == gen else { return }

        // 2. Emit the section JS — window advances ONLY on a successful eval.
        let title = dividerTitleProvider(targetIndex)
        let js = direction == .forward
            ? EPUBContinuousScrollJS.appendChapterSectionJS(body, dividerTitle: title)
            : EPUBContinuousScrollJS.prependChapterSectionJS(body, dividerTitle: title)
        do {
            try await evaluate(js)
        } catch {
            Self.log.error("section eval failed for spine \(targetIndex): \(String(describing: error), privacy: .public)")
            return // window NOT advanced
        }

        // Re-check after the eval await before mutating.
        guard generation == gen else { return }

        // 3. Commit the re-anchored + extended window together (only now), then
        //    evict the far end past maxSpan around the freshly-committed anchor.
        window = direction == .forward ? anchored.extendForward() : anchored.extendBackward()
        await evictIfNeeded(gen: gen)
    }

    // MARK: - Eviction

    /// Trims the window to `maxSpan`, emitting a remove-section JS for each
    /// evicted spine index. If a remove eval fails the window is left
    /// un-trimmed (a degraded, still-correct state — extra memory, not a
    /// wrong render).
    private func evictIfNeeded(gen: UUID) async {
        let trimmed = window.evictFarFromAnchor(maxSpan: maxSpan)
        guard trimmed != window else { return }

        let evicted = (window.lo...window.hi).filter { !trimmed.contains($0) }
        for index in evicted {
            guard generation == gen else { return }
            do {
                try await evaluate(EPUBContinuousScrollJS.removeChapterSectionJS(spineIndex: index))
            } catch {
                Self.log.error("evict eval failed for spine \(index): \(String(describing: error), privacy: .public)")
                return // leave the window un-trimmed; do not mutate on failure
            }
        }

        guard generation == gen else { return }
        window = trimmed
    }

    private enum Direction { case forward, backward }
}
