// Purpose: Feature #71 WI-4 — the @MainActor host-side coordinator for EPUB
// continuous cross-chapter scroll. It owns the materialized `EPUBSpineWindow`
// and turns the JS scroll observer's boundary signals into window transitions:
// when the viewport nears a materialized end, it materializes the adjacent
// chapter (`chapterBodyProvider`), emits the append/prepend section JS through
// an async-throwing evaluator, and — only after the eval SUCCEEDS — advances
// the window and evicts far chapters (emitting their remove JS).
//
// Key decisions (Gate-2 audit, thread 019e5f97):
// - **Async-throwing evaluator** (round-1 [H4]): a `(String) -> Void` closure
//   can't observe a failed `evaluateJavaScript`. The window must NOT advance if
//   the DOM insert failed, so the evaluator is `@MainActor (String) async throws`.
// - **Generation token** (round-1 [H4]): a `UUID` bumped on mode-switch / reopen
//   / book-change. A `chapterBodyProvider` task that resolves AFTER the token
//   bumped is discarded, so a stale chapter can't be stitched into a rebuilt doc.
// - **Single in-flight extension** (idempotency): a re-entrant boundary signal
//   while an extension is materializing is dropped, so a burst of near-boundary
//   signals appends exactly one chapter.
// - **Re-anchor to the reading chapter**: each signal re-anchors the window to
//   `visibleSpineIndex` (when inside the window) so eviction trims chapters
//   behind the reader, not the one being read. Re-anchor is a pure metadata
//   change (no `lo`/`hi` shift) — no DOM eval needed.
//
// This file is WI-4's decision logic: it is unit-testable with a recording stub
// evaluator + stub `chapterBodyProvider`, no live `WKWebView`. The bridge
// integration (script/handler injection, signal parsing) is WI-5.
//
// @coordinates-with: EPUBSpineWindow.swift, EPUBContinuousScrollJS.swift,
//   EPUBChapterBodyRewriter.swift (EPUBChapterBody),
//   EPUBWebViewBridge.swift (WI-5 consumer),
//   dev-docs/plans/20260525-feature-71-epub-continuous-scroll.md (WI-4)

import Foundation
import OSLog

/// The throttled report the continuous-scroll JS observer posts back to Swift
/// (`EPUBContinuousScrollJS.continuousScrollObserverJS`). WI-4 consumes only the
/// boundary flags for window decisions + `visibleSpineIndex` for re-anchoring;
/// `intraFraction` rides along for the WI-5/WI-6 progress mapping.
struct EPUBScrollBoundarySignal: Equatable, Sendable {
    /// The spine index of the section whose top boundary the viewport is past.
    let visibleSpineIndex: Int
    /// Progress (0...1) within that section.
    let intraFraction: Double
    /// The viewport is within the prefetch margin of the TOP of the materialized doc.
    let nearTopBoundary: Bool
    /// The viewport is within the prefetch margin of the BOTTOM of the materialized doc.
    let nearBottomBoundary: Bool
    /// Bug #329 (round 3) eviction-guard geometry: px of materialized content
    /// above the viewport top (= `scrollTop`). `nil` when the signal source
    /// doesn't carry geometry (legacy observer, synthetic test/DebugBridge
    /// signals) — eviction then falls back to the span-only rule.
    var pxAbove: Int? = nil
    /// Px of materialized content below the viewport bottom.
    var pxBelow: Int? = nil
    /// Each materialized section's height (px), in DOM order — index 0 is the
    /// window's `lo` section, last is `hi`. Lets the eviction guard compute how
    /// much trailing content a candidate eviction would leave.
    var sectionHeights: [Int]? = nil
    /// Bug #329 (round 4): a pan gesture is in progress. A JS `scrollTop`
    /// compensation issued mid-gesture is overridden by the scroller's gesture
    /// anchor (the content leaps by the removed height and the boundary
    /// re-fires — the measured chapter runaway), so while this is true the
    /// coordinator DEFERS evictions and backward prepends; forward appends
    /// (no compensation) stay allowed. `false` for synthetic/test signals.
    var touchActive: Bool = false
}

@MainActor
final class EPUBContinuousScrollCoordinator {

    private static let log = Logger(subsystem: "com.vreader.app", category: "EPUBContinuousScroll")

    /// The currently-materialized contiguous chapter window. Mutates only after
    /// a successful section eval (or a pure re-anchor).
    private(set) var window: EPUBSpineWindow

    /// Max materialized span (chapter count) before eviction trims the far side.
    private let maxSpan: Int

    /// Bug #329 round 4: how many sections past `maxSpan` the window may grow
    /// while a gesture defers evictions, before appends pause too. One pan +
    /// momentum rarely traverses more than 2–3 sections; the ceiling bounds
    /// DOM/memory growth for pathological gesture streams.
    static let touchGrowthCeilingSlack = 3

    /// Bug #347: the HARD in-gesture cap. The soft ceiling above no longer
    /// blocks appends (it starved the lookahead under chained flings — the
    /// gesture window never settles, deferred evictions never drain, and the
    /// reader bottomed out at the stitch edge). Forward appends are
    /// gesture-safe (they never write scrollTop — round 4's own analysis),
    /// and every boundary-driven append represents genuinely consumed
    /// content, so they continue past the soft ceiling.
    ///
    /// Round 2 (the device-confirmed re-report): the original slack of 12
    /// (span 15) was reachable by a HUMAN chained-fling session — the
    /// 2026-06-11 in-page sweep hit it at fling 8 of 25 and the reader sat
    /// pinned at the stitch edge (below = 0) for 18 straight flings, because
    /// chains never settle and the deferred backlog never drains. The
    /// oscillation storm this cap originally guarded CANNOT occur mid-gesture
    /// (evictions + prepends — the compensation writers — are deferred while
    /// `touchActive`, so no spurious boundary re-fires exist; only genuine
    /// travel produces in-gesture nearBottom signals). The cap therefore
    /// survives only as a far-out DOM/memory bound no human chain reaches
    /// (span 50 ≈ minutes of unbroken robotic flinging).
    static let touchGrowthHardCapSlack = 47

    /// Bug #347 round 2 facet 2: the per-extend eviction budget. The settle
    /// report used to drain the WHOLE deferred backlog in one signal — after
    /// a long chain that is a dozen+ removes whose compensations land in one
    /// frame burst (the sweep measured scrollTop 30600 → 1960 with a −262 px
    /// overshoot — the user-visible "jump" at stall release). Each extend now
    /// trims at most this many trailing chapters; the backlog converges to
    /// `maxSpan` across the subsequent reading-pace signals, visually silent.
    static let maxEvictionsPerExtend = 2
    /// Materializes a chapter's rewritten body for a spine index (off-main I/O).
    private let chapterBodyProvider: @MainActor (Int) async throws -> EPUBChapterBody
    /// Evaluates section JS against the live `WKWebView`. Async-throwing so a
    /// failed DOM insert is observable (the window does not advance on failure).
    private let evaluate: @MainActor (String) async throws -> Void
    /// Optional per-chapter divider title (chapter heading shown at the seam).
    private let dividerTitle: (@MainActor (Int) -> String?)?

    /// Feature #71 WI-7 (Gate-4 round-2 MEDIUM 2): invoked with a spine index
    /// AFTER its remove (eviction) JS eval succeeds, so a far-side trim signals
    /// downstream consumers (the bilingual orchestrator drops that section's
    /// stale block bucket). Fires only on a successful remove — a failed remove
    /// leaves the section in the DOM, so the callback must not fire and the
    /// bucket must stay. Default no-op for callers (tests, paged mode) that
    /// don't track per-section state.
    private let onSectionEvicted: (@MainActor (Int) -> Void)?

    /// Bug #347 round 2 (mechanism a — append latency): the single-slot
    /// forward body pre-materialization. After a forward extend commits, the
    /// NEXT chapter's body is fetched + rewritten in the background, so the
    /// boundary-driven append that follows is just one DOM eval instead of a
    /// provider round-trip — at fling speed the provider latency was the
    /// other half of the lookahead starvation. Gen-guarded; consumed (and
    /// cleared) by the next forward extend; invalidated on reset.
    private var prefetchedBody: EPUBChapterBody?
    private var prefetchTask: Task<Void, Never>?

    /// Bumped on mode-switch / reopen / book-change to discard stale in-flight
    /// `chapterBodyProvider` results.
    private(set) var generation = UUID()
    /// True while an extension is materializing — drops re-entrant signals so a
    /// burst of near-boundary reports appends exactly one chapter.
    private(set) var isExtending = false

    /// Bug #329: ignore the SINGLE spurious boundary signal that an eviction
    /// echoes. A forward extend evicts the trailing section;
    /// `removeChapterSectionJS` compensates with `scrollTop -= removedHeight`,
    /// which can drop `scrollTop` below the observer's `nearTop` prefetch
    /// threshold — so the very next report falsely says `nearTop` even though the
    /// reader is scrolling forward. Honoring it would reload the just-evicted
    /// section → the window oscillates and forward progress stalls. So after a
    /// forward eviction we ignore the next `nearTop` (and symmetrically the next
    /// `nearBottom` after a backward eviction). This suppresses ONLY the echo —
    /// it never blocks the reader's actual travel direction (the matching
    /// `nearBottom`/`nearTop` is always honored), and a genuine reversal is at
    /// most one signal delayed. (The earlier sticky-direction approach inferred
    /// direction from `visibleSpineIndex + intraFraction`, but the eviction
    /// corrupts that very signal, so it could wedge forward progress — regression
    /// fixed here.)
    private var ignoreNextNearTop = false
    private var ignoreNextNearBottom = false

    /// WI-6b-iii: intra-chapter progression (0...1) to scroll the anchor section
    /// to after the initial window materializes (saved-position restore). Nil /
    /// ≤0 opens at the chapter top.
    private let restoreFraction: Double?

    init(
        initialWindow: EPUBSpineWindow,
        maxSpan: Int = 3,
        chapterBodyProvider: @escaping @MainActor (Int) async throws -> EPUBChapterBody,
        evaluate: @escaping @MainActor (String) async throws -> Void,
        dividerTitle: (@MainActor (Int) -> String?)? = nil,
        restoreFraction: Double? = nil,
        onSectionEvicted: (@MainActor (Int) -> Void)? = nil
    ) {
        self.window = initialWindow
        self.maxSpan = max(maxSpan, 1)
        self.chapterBodyProvider = chapterBodyProvider
        self.evaluate = evaluate
        self.dividerTitle = dividerTitle
        self.restoreFraction = restoreFraction
        self.onSectionEvicted = onSectionEvicted
    }

    /// Discards any in-flight materialization and resets the busy flag. Call on
    /// mode-switch / reopen / book-change before re-bootstrapping the window.
    func invalidate() {
        generation = UUID()
        isExtending = false
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchedBody = nil
        prefetchInFlightIndex = nil  // r2 audit Medium: a stale in-flight
        // index would no-op the SAME chapter's re-schedule after a reopen.
        ignoreNextNearTop = false      // Bug #329: a reopen carries no pending echo.
        ignoreNextNearBottom = false
    }

    /// React to a scroll boundary signal: re-anchor to the reading chapter, then
    /// extend the window toward whichever boundary the viewport is near (if any
    /// adjacent chapter remains). A no-op at the book's first/last chapter (no
    /// bounce JS) and while an extension is already in flight.
    func handleBoundarySignal(_ signal: EPUBScrollBoundarySignal) async {
        // Re-anchor to the reading chapter (pure metadata; no DOM change) so
        // eviction trims behind the reader.
        if window.contains(signal.visibleSpineIndex) {
            window = window.reanchored(to: signal.visibleSpineIndex)
        }
        // Bug #329: consume the eviction-echo suppression for THIS signal. A
        // forward eviction in a prior signal set `ignoreNextNearTop`; the spurious
        // post-eviction `nearTop` arrives in this next signal and must be ignored
        // (else it reloads the just-evicted section → oscillation + stall).
        // Suppress ONLY the echoed boundary — never the reader's travel direction.
        let suppressNearTop = ignoreNextNearTop
        let suppressNearBottom = ignoreNextNearBottom
        ignoreNextNearTop = false
        ignoreNextNearBottom = false

        guard !isExtending else { return }
        // Extend toward whichever boundary the viewport is near. `extend` arms the
        // opposite-side echo suppression iff it evicts (Bug #329). Eviction stays
        // DIRECTIONAL (`evictTrailing`, Bug #327) and — round 3 — px-GUARDED: the
        // signal's geometry rides along so eviction can never strand the trailing
        // side below the prefetch threshold (the sustained-oscillation source).
        if signal.nearBottomBoundary, !suppressNearBottom, window.canExtendForward {
            // Bug #329 round 4 → Bug #347: the original soft ceiling
            // (maxSpan + touchGrowthCeilingSlack) starved forward appends
            // under chained flings — touchActive never cleared (settle needs
            // 160ms of quiescence), deferred evictions never drained, and
            // once the ceiling hit, the reader scrolled to the stitch edge.
            // Forward appends never write scrollTop (gesture-safe), and a
            // near-bottom boundary signal means the user genuinely consumed
            // the lookahead — so appends now continue past the soft ceiling
            // and only the HARD cap (storm guard) defers them. The settle
            // report still drains the whole eviction backlog.
            if signal.touchActive, window.span >= maxSpan + Self.touchGrowthHardCapSlack {
                Self.log.debug("in-gesture HARD growth cap reached (span \(self.window.span)); deferring append")
                return
            }
            if signal.touchActive, window.span >= maxSpan + Self.touchGrowthCeilingSlack {
                Self.log.debug("in-gesture span \(self.window.span) past the soft ceiling; edge-driven append continues (Bug #347)")
            }
            await extend(forward: true, geometry: signal)
            // Bug #329 (Codex hotfix-audit, High): if that forward extend EVICTED
            // it armed `ignoreNextNearTop`. In a DUAL-boundary signal (short window
            // → nearTop AND nearBottom both true) the `nearTop` below is the same
            // eviction's echo, but `suppressNearTop` was captured before this await
            // so it wouldn't catch it. Skip the backward branch now — otherwise we
            // immediately reload the just-evicted section and the oscillation
            // returns. The next-signal echo is still covered by `ignoreNextNearTop`.
            if ignoreNextNearTop { return }
        }
        if signal.nearTopBoundary, !suppressNearTop, window.canExtendBackward {
            // Bug #329 (round 4): a backward extend PREPENDS above the viewport
            // — its `scrollTop += h` compensation would be overridden by a live
            // gesture anchor (the content leaps a section and the boundary
            // re-fires). Defer it; the observer emits an extra report on
            // touchend, which re-enters here with `touchActive == false`.
            if signal.touchActive {
                Self.log.debug("deferring backward extend during active touch")
                return
            }
            await extend(forward: false, geometry: signal)
        }
    }

    /// Feature #71 WI-6b-i: materialize the INITIAL window into the (empty)
    /// bootstrap document. WI-4's `extend` assumes the window's chapters are
    /// already in the DOM; on a fresh open NONE are, so this seeds the anchor
    /// chapter's section first, then extends ±1 (no-op at the book edges). A
    /// failed anchor append aborts with the window unchanged (the same [H4]
    /// "don't advance on a failed eval" posture as `extend`), so a bootstrap
    /// whose first chapter can't render leaves a clean empty document rather
    /// than a half-stitched one. Call once after the bridge loads the bootstrap.
    /// Materialize the anchor window on the freshly-loaded bootstrap. Holds the
    /// mutation lane (`isExtending`) across the whole sequence (Gate-4 round-2
    /// Critical) so a navigate / boundary signal arriving while the anchor
    /// provider is suspended is dropped, not interleaved over the initial DOM.
    func materializeInitialWindow() async {
        guard !isExtending else { return }
        let wasExtending = isExtending
        isExtending = true
        defer { isExtending = wasExtending }
        let gen = generation
        let anchor = window.anchor
        let body: EPUBChapterBody
        do {
            body = try await chapterBodyProvider(anchor)
        } catch {
            Self.log.error("initial anchor \(anchor) materialize failed: \(String(describing: error), privacy: .public)")
            return
        }
        guard gen == generation, body.spineIndex == anchor else { return }
        do {
            try await evaluate(
                EPUBContinuousScrollJS.appendChapterSectionJS(body, dividerTitle: dividerTitle?(anchor))
            )
        } catch {
            Self.log.error("initial anchor \(anchor) append failed: \(String(describing: error), privacy: .public)")
            return
        }
        guard gen == generation else { return }
        await fillNeighboursAndScroll(anchor: anchor, scrollFraction: restoreFraction)
    }

    /// WI-8: navigate the continuous reader to `target` spine index + the
    /// intra-chapter `fraction` (TOC / bookmark / search-result jump). This is
    /// the continuous-mode replacement for the single-chapter `loadFileURL`
    /// navigate path — without it, `.readerNavigateToLocator` no-ops in
    /// continuous mode (the WI-6b-i Critical that gated the feature behind a
    /// flag). In-window targets just scroll (+ re-anchor so eviction trims
    /// behind the new reading point); an out-of-window target rebuilds the
    /// window around it (atomic clear-and-insert, then re-seed ±1).
    ///
    /// Serialized against initial-materialize / `extend` / another `navigate` via
    /// `isExtending` (Gate-4): a jump arriving while the mutation lane is busy is
    /// DROPPED, not interleaved into a half-built DOM. Returns `true` only when
    /// the reader actually moved, so the caller updates the persisted position
    /// only on a real navigation (Gate-4 round-2).
    @discardableResult
    func navigate(toSpineIndex target: Int, fraction: Double) async -> Bool {
        guard target >= 0, target < window.spineCount else { return false }
        guard !isExtending else { return false }
        // Hold the mutation lane for the WHOLE navigate — in-window scroll AND
        // out-of-window rebuild (Gate-4 round-3): two rapid jumps, or a boundary
        // signal arriving while an in-window scroll eval is in flight, are
        // serialized. The inner `extend` calls save/restore the flag, keeping it
        // held through the ±1 fill.
        isExtending = true
        defer { isExtending = false }
        let gen = generation

        if window.contains(target) {
            // Re-anchor only AFTER a successful scroll (Gate-4): a failed eval
            // means the reader didn't move, so the eviction anchor must not.
            do {
                try await evaluate(
                    EPUBContinuousScrollJS.scrollToSpineFractionJS(spineIndex: target, fraction: fraction)
                )
            } catch {
                Self.log.error("navigate scroll to \(target) failed: \(String(describing: error), privacy: .public)")
                return false
            }
            guard gen == generation else { return false }
            window = window.reanchored(to: target)
            return true
        }

        // Out-of-window rebuild. Fetch the target BEFORE touching the DOM (Gate-4
        // round-2): a provider failure aborts with the old window still intact.
        let body: EPUBChapterBody
        do {
            body = try await chapterBodyProvider(target)
        } catch {
            Self.log.error("navigate provider \(target) failed: \(String(describing: error), privacy: .public)")
            return false
        }
        guard gen == generation, body.spineIndex == target else { return false }
        // ONE transactional eval clears the old sections AND inserts the new
        // anchor (Gate-4 round-2): the DOM is never left empty under a stale
        // window — it's either fully replaced or untouched.
        do {
            try await evaluate(
                EPUBContinuousScrollJS.clearAllAndInsertSectionJS(body, dividerTitle: dividerTitle?(target))
            )
        } catch {
            Self.log.error("navigate clear+insert \(target) failed: \(String(describing: error), privacy: .public)")
            return false
        }
        guard gen == generation,
              let committed = EPUBSpineWindow.initial(anchor: target, spineCount: window.spineCount) else {
            return false
        }
        // Commit the rebuilt window AFTER the anchor is in the DOM.
        window = committed
        // force: a TOC/bookmark/search jump must land deterministically on the
        // target chapter even at fraction 0 — not rely on the prepend's
        // scroll-anchoring (the 77px landing inconsistency, WI-8 device-verify).
        await fillNeighboursAndScroll(anchor: target, scrollFraction: fraction, force: true)
        // A mode-switch/reopen during the neighbour fill bails inside
        // `fillNeighboursAndScroll`; don't report success to the caller then
        // (Gate-4 round-3) — it would update the position from a stale task.
        guard gen == generation else { return false }
        return true
    }

    /// Materialize the ±1 neighbours of `anchor` (already in the DOM) and scroll
    /// it to `scrollFraction` (nil / ≤0 ⇒ chapter top). Shared by the initial
    /// open + `navigate` after each has committed the anchor section + window.
    /// Caller holds the mutation lane.
    /// `force` (navigate-only): scroll to the anchor even at fraction 0. The
    /// out-of-window rebuild PREPENDS the backward neighbour above the anchor,
    /// and the browser's scroll-anchoring then bumps `scrollTop` to keep the
    /// anchor visually in place — landing ~one safe-area-inset short of the
    /// anchor's `offsetTop` (the 77px in-window/out-of-window landing
    /// inconsistency found in device verify). Forcing the explicit scroll makes
    /// the out-of-window landing DETERMINISTIC (exact `offsetTop`), matching the
    /// in-window branch. `materializeInitialWindow` does NOT force: its anchor
    /// sits at the document top, so a fraction-0/nil restore must stay at
    /// `scrollTop` 0 (heading below the inset), not scroll to `offsetTop`.
    private func fillNeighboursAndScroll(anchor: Int, scrollFraction: Double?, force: Bool = false) async {
        let gen = generation
        // Fill ±1 around the anchor (each a no-op at the respective book edge).
        // Re-check the generation BETWEEN the extends (Gate-4): a mode-switch /
        // reopen that bumps the token during the forward extend's await aborts it
        // internally, but without this guard the backward extend would capture the
        // NEW generation and stitch stale-window work into a rebuilt context.
        if window.canExtendForward { await extend(forward: true) }
        guard gen == generation else { return }
        if window.canExtendBackward { await extend(forward: false) }
        guard gen == generation else { return }
        // Best-effort scroll — a failed eval just leaves the chapter top.
        if let fraction = scrollFraction, force || fraction > 0 {
            try? await evaluate(
                EPUBContinuousScrollJS.scrollToSpineFractionJS(spineIndex: anchor, fraction: fraction)
            )
        }
    }

    // MARK: - Private

    /// Bug #329 (round 3): the px margin the eviction guard keeps ON TOP of the
    /// prefetch threshold, absorbing the drift between the signal's geometry
    /// snapshot and the eviction. Drift in the travel direction only ADDS slack
    /// (the snapshot under-states the trailing side); the hazardous direction is
    /// a REVERSAL during the in-flight extend (Codex Gate-4 Medium: a stale-large
    /// snapshot could then approve an eviction the reader is heading back into).
    /// The extend's exposure window is milliseconds (provider + one eval), so 128
    /// px covers any realistic reversal velocity within it; a violent flick past
    /// that costs at most ONE evict→prepend-reload of a single section in the
    /// reader's (new) travel direction — the prepend's in-eval compensation keeps
    /// the viewport stable, so it is a wasted round-trip, not a visible jump, and
    /// it cannot oscillate (the reload direction matches travel). Accepted with
    /// this rationale in the Gate-4 audit log.
    private static let evictionGuardMarginPx = 128

    /// Bug #329 (round 3): whether evicting the next trailing candidate would
    /// strand the trailing side of the viewport below the prefetch threshold.
    ///
    /// The root cause of the evict→reload oscillation is GEOMETRIC: through a
    /// run of short sections, removing the trailing one drops `scrollTop` (its
    /// compensation) — or shrinks the below-viewport remainder — past
    /// `prefetchPx`, so the opposite boundary flag re-asserts on EVERY
    /// subsequent scroll report, not just the next one. A one-shot echo
    /// suppression can only delay each reload by one signal (the v3.59.22
    /// regression-class). The durable rule: DEFER the eviction until the reader
    /// has travelled far enough that the side being trimmed retains
    /// `prefetchPx + margin` px of content. The window then floats above
    /// `maxSpan` through short front matter (a few hundred px of extra DOM) and
    /// tightens back over normal-length chapters.
    ///
    /// `evictedSoFar` accumulates the heights this extend already trimmed (the
    /// multi-evict catch-up loop). Returns `false` (defer) when geometry is
    /// present but the candidate's height is unindexable (a mutation raced the
    /// report — the next signal carries fresh geometry). Returns `true` when the
    /// signal carries NO geometry at all (synthetic/test signals keep the legacy
    /// span-only behaviour).
    private func evictionKeepsTrailingSlack(
        forward: Bool,
        candidatePosition: Int,
        evictedSoFar: Int,
        geometry: EPUBScrollBoundarySignal?
    ) -> Bool {
        guard let geometry else { return true }
        guard let heights = geometry.sectionHeights,
              let pxSide = forward ? geometry.pxAbove : geometry.pxBelow else { return true }
        // Forward extends trim from the FRONT of the DOM (window.lo → index 0,
        // then 1, …); backward extends trim from the BACK (window.hi → last,
        // then last-1, …).
        let index = forward ? candidatePosition : heights.count - 1 - candidatePosition
        guard heights.indices.contains(index) else { return false } // raced — defer
        let remaining = pxSide - evictedSoFar - heights[index]
        return remaining > EPUBContinuousScrollJS.prefetchPx + Self.evictionGuardMarginPx
    }

    private func extend(forward: Bool, geometry: EPUBScrollBoundarySignal? = nil) async {
        // Save/restore (WI-8) rather than force-false: `navigate`'s out-of-window
        // rebuild holds `isExtending` across its remove-loop + re-materialize, and
        // the inner extends here must not clear it mid-rebuild (which would let a
        // boundary signal interleave). For a standalone boundary-driven extend
        // `wasExtending` is false, so behaviour is unchanged.
        let wasExtending = isExtending
        isExtending = true
        defer { isExtending = wasExtending }

        let gen = generation
        let targetIndex = forward ? window.hi + 1 : window.lo - 1

        let body: EPUBChapterBody
        if forward, let cached = prefetchedBody, cached.spineIndex == targetIndex {
            // Bug #347 round 2: the pre-materialized next chapter — skip the
            // provider round-trip entirely (the fling-speed starvation half).
            body = cached
            prefetchedBody = nil
        } else {
            do {
                body = try await chapterBodyProvider(targetIndex)
            } catch {
                Self.log.error("chapter \(targetIndex) materialize failed: \(String(describing: error), privacy: .public)")
                return // window unchanged
            }
        }
        // Stale: a mode-switch / reopen happened while we awaited the chapter.
        guard gen == generation else { return }
        // Defensive (Gate-4 round-1 [L2]): the provider MUST return the requested
        // chapter, or DOM section identity (`data-vreader-spine-index`) would
        // desync from `window`. Abort on mismatch rather than stitch a wrong body.
        guard body.spineIndex == targetIndex else {
            Self.log.error("chapterBodyProvider returned spineIndex \(body.spineIndex) for requested \(targetIndex) — aborting extend")
            return
        }

        let title = dividerTitle?(targetIndex)
        let insertJS = forward
            ? EPUBContinuousScrollJS.appendChapterSectionJS(body, dividerTitle: title)
            : EPUBContinuousScrollJS.prependChapterSectionJS(body, dividerTitle: title)
        do {
            try await evaluate(insertJS)
        } catch {
            // round-1 [H4]: DOM insert failed → DO NOT advance the window.
            Self.log.error("section insert eval failed for \(targetIndex): \(String(describing: error), privacy: .public)")
            return
        }
        guard gen == generation else { return }

        // Eval succeeded → the new chapter is in the DOM. Evict trailing chapters
        // one at a time, advancing `committed` ONLY as each remove succeeds, so the
        // published window always matches the DOM even under a partial (cascade)
        // remove failure (Gate-4 round-2 [M5]). `window` is assigned ONCE at the
        // end, gen-guarded, so a mode-switch DURING eviction can't publish this
        // stale task's state over a rebuilt generation (round-1 [H1]). While
        // evicting, `window` stays at its pre-extend value; `isExtending` blocks
        // any reader meanwhile.
        let extended = forward ? window.extendForward() : window.extendBackward()
        // Bug #327: eviction is DIRECTIONAL — `evictTrailing` trims only the
        // trailing edge behind the reader and NEVER the chapter just loaded ahead
        // of them. Through a run of short front-matter chapters the topmost-visible
        // anchor lags the leading edge, so a far-from-anchor trim used to remove
        // the very chapter the reader was about to reach (deadlocking the scroll on
        // the cover); trailing-only eviction keeps it. When the anchor sits within
        // `maxSpan-1` of the trailing edge the window is left larger than `maxSpan`
        // and shrinks back naturally as the anchor advances.
        let targetSpan = extended.evictTrailing(forward: forward, maxSpan: maxSpan).span
        var committed = extended
        // Bug #329 (round 3): position of the next eviction candidate within the
        // SIGNAL's section-height snapshot + the px already trimmed this extend —
        // the guard's cumulative arithmetic for the multi-evict catch-up loop.
        var candidatePosition = 0
        var evictedPx = 0
        // Bug #347 round 2 facet 2: amortize the backlog drain — at most
        // `maxEvictionsPerExtend` trims per extend, so a post-chain settle
        // can never burst a dozen compensations into one frame (the jump).
        while committed.span > targetSpan,
              candidatePosition < Self.maxEvictionsPerExtend {
            guard gen == generation else { return } // stale → emit nothing, publish nothing
            // Bug #329 (round 4): NEVER evict while a pan gesture is active —
            // a forward eviction's `scrollTop -= h` compensation is overridden
            // by the live gesture anchor, so the content leaps by the removed
            // height and the boundary re-fires (the measured chapter runaway:
            // ~19 chapters/second under a real drag; rounds 1–3's synthetic
            // ticks carried no gesture, which is why they all passed). The
            // window floats above maxSpan for the touch's duration; the
            // observer's touchend report re-enters and drains the backlog.
            if geometry?.touchActive == true {
                Self.log.debug("deferring eviction during active touch")
                break
            }
            // Bug #329 (round 3): defer the trim (and the rest of the catch-up)
            // when it would strand the trailing side below prefetch + margin —
            // the geometric source of the evict→reload oscillation. A later
            // signal carries fresher geometry and drains the backlog.
            guard evictionKeepsTrailingSlack(
                forward: forward,
                candidatePosition: candidatePosition,
                evictedSoFar: evictedPx,
                geometry: geometry
            ) else { break }
            // Trim exactly the ONE trailing chapter this step (the `lo` end on a
            // forward extend, the `hi` end on a backward extend).
            let next = committed.evictTrailing(forward: forward, maxSpan: committed.span - 1)
            guard let index = singleDroppedIndex(from: committed, to: next) else { break }
            do {
                try await evaluate(EPUBContinuousScrollJS.removeChapterSectionJS(spineIndex: index))
            } catch {
                // round-1 [M4] / round-2 [M5]: a failed remove leaves that section
                // in the DOM → stop here with `committed` reflecting ONLY the
                // sections actually removed, so the window never under- or
                // over-claims relative to the DOM.
                Self.log.warning("evict remove eval failed for \(index): \(String(describing: error), privacy: .public)")
                break
            }
            // Feature #71 WI-7 (Gate-4 round-3 MEDIUM 3): re-check the generation
            // AFTER the remove eval awaited. If the coordinator was invalidated
            // mid-eval (mode-switch / reopen / book-change), this is a stale
            // task — firing `onSectionEvicted` would clear a block bucket in the
            // NEW generation (whose DOM the bilingual orchestrator is now
            // tracking), corrupting it. Bail without signalling, exactly like the
            // window-publish guard below.
            guard gen == generation else { return }
            // Feature #71 WI-7 (Gate-4 round-2 MEDIUM 2): the remove succeeded —
            // signal the evicted spine index so the bilingual orchestrator drops
            // that section's stale block bucket. Fires AFTER the eval (a failed
            // remove `break`s above, leaving the section + its bucket alone) and
            // AFTER the gen re-check (so a stale task never signals).
            onSectionEvicted?(index)
            // Bug #329 (round 3): account the trimmed candidate's height into the
            // guard's cumulative budget for the next catch-up iteration.
            if let heights = geometry?.sectionHeights {
                let snapshotIndex = forward ? candidatePosition : heights.count - 1 - candidatePosition
                if heights.indices.contains(snapshotIndex) { evictedPx += heights[snapshotIndex] }
            }
            candidatePosition += 1
            committed = next
        }
        guard gen == generation else { return }
        // Bug #329: if this extend evicted a trailing section, the eviction's
        // `scrollTop -= removedHeight` can drop scrollTop past the prefetch
        // threshold, so the very next report falsely fires the OPPOSITE boundary.
        // Arm a one-signal suppression for it so it doesn't reload the section we
        // just evicted (the evict→reload oscillation). Forward extend evicted from
        // `lo` → suppress the next `nearTop`; backward extend evicted from `hi` →
        // suppress the next `nearBottom`.
        if committed.span < extended.span {
            if forward { ignoreNextNearTop = true } else { ignoreNextNearBottom = true }
        }
        window = committed
        // Bug #347 round 2: pre-materialize the chapter AFTER the one just
        // appended, so the next boundary append is provider-free.
        if forward, window.canExtendForward {
            schedulePrefetch(of: window.hi + 1)
        }
    }

    /// Bug #347 round 2: background single-slot pre-materialization of the
    /// next forward chapter. Gen-guarded; a stale or mismatched result is
    /// dropped. Re-scheduling for an index already cached/in-flight is a
    /// no-op so signal bursts don't refetch.
    private func schedulePrefetch(of index: Int) {
        guard index >= 0, index < window.spineCount else { return }
        if prefetchedBody?.spineIndex == index { return }
        if prefetchInFlightIndex == index { return }
        prefetchTask?.cancel()
        prefetchInFlightIndex = index
        let gen = generation
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            let body = try? await self.chapterBodyProvider(index)
            guard self.prefetchInFlightIndex == index else { return }
            self.prefetchInFlightIndex = nil
            guard let body, gen == self.generation, body.spineIndex == index else { return }
            self.prefetchedBody = body
        }
    }

    /// The spine index the in-flight prefetch targets (nil when idle).
    private var prefetchInFlightIndex: Int?

    /// Test seam: await the in-flight prefetch (if any) so unit tests can
    /// assert the cache deterministically.
    func awaitPrefetchForTesting() async {
        await prefetchTask?.value
    }

    /// Test seam: the cached pre-materialized chapter's spine index.
    var prefetchedSpineIndexForTesting: Int? { prefetchedBody?.spineIndex }

    /// Test seam: the in-flight prefetch's target index (nil when idle) —
    /// pins that `invalidate()` clears it immediately (r2 audit Medium).
    var prefetchInFlightIndexForTesting: Int? { prefetchInFlightIndex }

    /// The single spine index present in `before` but not `after` for a
    /// one-chapter trim (`after` drops exactly one end of `before`). `nil` if no
    /// single end was trimmed.
    private func singleDroppedIndex(from before: EPUBSpineWindow, to after: EPUBSpineWindow) -> Int? {
        if after.lo > before.lo { return before.lo }
        if after.hi < before.hi { return before.hi }
        return nil
    }
}
