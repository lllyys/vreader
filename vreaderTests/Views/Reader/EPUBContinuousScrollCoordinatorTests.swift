// Purpose: Feature #71 WI-4 — unit tests for EPUBContinuousScrollCoordinator's
// window-transition decision logic, driven by a recording stub evaluator + stub
// chapterBodyProvider (no live WKWebView). Covers: forward extend (one append
// per boundary), reverse prepend, first/last-chapter no-op, partial-eval-failure
// (window must not advance), stale-generation discard, single-in-flight
// idempotency, and far-end eviction emitting remove JS.
//
// @coordinates-with: EPUBContinuousScrollCoordinator.swift, EPUBSpineWindow.swift,
//   EPUBContinuousScrollJS.swift, EPUBChapterBodyRewriter.swift

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("EPUBContinuousScrollCoordinator (Feature #71 WI-4)")
struct EPUBContinuousScrollCoordinatorTests {

    /// Records every evaluated JS string; can be made to throw (partial-failure).
    @MainActor
    final class RecordingEvaluator {
        var evaluatedJS: [String] = []
        var shouldThrow = false
        /// Fired when a REMOVE (eviction) JS is evaluated — lets a test invalidate
        /// the coordinator mid-eviction to exercise the stale-generation guard.
        var onRemoveEval: (() -> Void)?
        /// Awaited at the START of every evaluate — lets a test hold a specific
        /// eval (e.g. the in-window scroll, which has no provider to gate on)
        /// in-flight to exercise `navigate`'s mutation-lane serialization.
        var beforeEvaluate: ((String) async -> Void)?
        func evaluate(_ js: String) async throws {
            await beforeEvaluate?(js)
            if shouldThrow { throw NSError(domain: "test.eval", code: 1) }
            evaluatedJS.append(js)
            if js.contains("el.remove()") { onRemoveEval?() }
        }
        var appends: [String] { evaluatedJS.filter { $0.contains("beforeend") } }
        var prepends: [String] { evaluatedJS.filter { $0.contains("afterbegin") } }
        var removes: [String] { evaluatedJS.filter { $0.contains("el.remove()") } }
        func removedSpineIndex(_ i: Int) -> Bool {
            removes.contains { $0.contains("data-vreader-spine-index=\"\(i)\"") }
        }
    }

    @MainActor
    final class CoordHolder { var c: EPUBContinuousScrollCoordinator? }

    private func body(_ index: Int) -> EPUBChapterBody {
        EPUBChapterBody(spineIndex: index, href: "ch\(index).xhtml",
                        bodyHTML: "<p>chapter \(index)</p>", scopedStyleHTML: "")
    }

    private func signal(visible: Int, top: Bool = false, bottom: Bool = false) -> EPUBScrollBoundarySignal {
        EPUBScrollBoundarySignal(visibleSpineIndex: visible, intraFraction: 0.5,
                                 nearTopBoundary: top, nearBottomBoundary: bottom)
    }

    private func makeCoordinator(
        anchor: Int, spineCount: Int, maxSpan: Int = 3,
        eval: RecordingEvaluator,
        provider: @escaping @MainActor (Int) async throws -> EPUBChapterBody
    ) -> EPUBContinuousScrollCoordinator {
        EPUBContinuousScrollCoordinator(
            initialWindow: EPUBSpineWindow.initial(anchor: anchor, spineCount: spineCount)!,
            maxSpan: maxSpan,
            chapterBodyProvider: provider,
            evaluate: { try await eval.evaluate($0) })
    }

    // MARK: - extend forward / backward

    @Test func nearBottom_extendsForward_emitsOneAppend() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 0, spineCount: 5, eval: eval, provider: { self.body($0) })
        await c.handleBoundarySignal(signal(visible: 0, bottom: true))
        #expect(c.window.hi == 1)
        #expect(c.window.lo == 0)
        #expect(eval.appends.count == 1)
        #expect(eval.prepends.isEmpty)
    }

    @Test func nearTop_extendsBackward_emitsOnePrepend() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 2, spineCount: 5, eval: eval, provider: { self.body($0) })
        await c.handleBoundarySignal(signal(visible: 2, top: true))
        #expect(c.window.lo == 1)
        #expect(c.window.hi == 2)
        #expect(eval.prepends.count == 1)
        #expect(eval.appends.isEmpty)
    }

    @Test func atLastChapter_nearBottom_isNoOp_noBounceJS() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 4, spineCount: 5, eval: eval, provider: { self.body($0) })
        await c.handleBoundarySignal(signal(visible: 4, bottom: true))
        #expect(c.window == EPUBSpineWindow.initial(anchor: 4, spineCount: 5)!)
        #expect(eval.evaluatedJS.isEmpty)
    }

    @Test func atFirstChapter_nearTop_isNoOp_noBounceJS() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 0, spineCount: 5, eval: eval, provider: { self.body($0) })
        await c.handleBoundarySignal(signal(visible: 0, top: true))
        #expect(c.window == EPUBSpineWindow.initial(anchor: 0, spineCount: 5)!)
        #expect(eval.evaluatedJS.isEmpty)
    }

    // MARK: - partial failure (round-1 [H4])

    @Test func evalThrows_windowDoesNotAdvance() async {
        let eval = RecordingEvaluator()
        eval.shouldThrow = true
        let c = makeCoordinator(anchor: 0, spineCount: 5, eval: eval, provider: { self.body($0) })
        await c.handleBoundarySignal(signal(visible: 0, bottom: true))
        // Insert eval threw → window must stay at its initial range.
        #expect(c.window == EPUBSpineWindow.initial(anchor: 0, spineCount: 5)!)
        #expect(eval.appends.isEmpty)
    }

    @Test func providerThrows_windowDoesNotAdvance_noEval() async {
        let eval = RecordingEvaluator()
        struct Boom: Error {}
        let c = makeCoordinator(anchor: 0, spineCount: 5, eval: eval, provider: { _ in throw Boom() })
        await c.handleBoundarySignal(signal(visible: 0, bottom: true))
        #expect(c.window == EPUBSpineWindow.initial(anchor: 0, spineCount: 5)!)
        #expect(eval.evaluatedJS.isEmpty)
    }

    // MARK: - stale generation (round-1 [H4])

    @Test func staleGeneration_discardsMaterializedChapter() async {
        let eval = RecordingEvaluator()
        let holder = CoordHolder()
        let c = makeCoordinator(anchor: 0, spineCount: 5, eval: eval, provider: { idx in
            // Simulate a mode-switch / reopen DURING materialization: the gen
            // token bumps before the provider resolves.
            holder.c?.invalidate()
            return self.body(idx)
        })
        holder.c = c
        await c.handleBoundarySignal(signal(visible: 0, bottom: true))
        // gen != generation after the await → discard: no append, window unchanged.
        #expect(c.window == EPUBSpineWindow.initial(anchor: 0, spineCount: 5)!)
        #expect(eval.evaluatedJS.isEmpty)
    }

    // MARK: - single in-flight extension (idempotency)

    @Test func concurrentBoundarySignals_appendExactlyOnce() async {
        let eval = RecordingEvaluator()
        let gate = CheckedContinuationGate()
        let c = makeCoordinator(anchor: 0, spineCount: 5, eval: eval, provider: { idx in
            await gate.wait()   // hold the first extend in-flight
            return self.body(idx)
        })
        // Fire two bottom signals concurrently; the second must be dropped by the
        // isExtending guard while the first is materializing.
        async let a: Void = c.handleBoundarySignal(signal(visible: 0, bottom: true))
        // Let the first extend reach the provider await + the second signal run.
        while !c.isExtending { await Task.yield() }
        await c.handleBoundarySignal(signal(visible: 0, bottom: true)) // dropped (busy)
        gate.open()
        await a
        #expect(eval.appends.count == 1)
        #expect(c.window.hi == 1)
    }

    // MARK: - eviction emits remove JS

    @Test func forwardReadPastMaxSpan_evictsBehind_emitsRemoveJS() async {
        let eval = RecordingEvaluator()
        // maxSpan 3 (anchor ±1). Read forward 0→1→2; the 3rd extend grows the
        // window to [0,3] anchored at 2, which evicts the far-behind index 0.
        let c = makeCoordinator(anchor: 0, spineCount: 10, maxSpan: 3, eval: eval, provider: { self.body($0) })
        await c.handleBoundarySignal(signal(visible: 0, bottom: true)) // [0,1]
        await c.handleBoundarySignal(signal(visible: 1, bottom: true)) // [0,2]
        await c.handleBoundarySignal(signal(visible: 2, bottom: true)) // [0,3]→evict→[1,3]
        #expect(c.window.lo == 1)
        #expect(c.window.hi == 3)
        #expect(c.window.contains(2))            // the reading chapter is kept
        #expect(eval.removedSpineIndex(0))       // the far-behind chapter was removed
    }

    // MARK: - dual boundary (round-1 [M3])

    @Test func nearTopAndBottom_extendsBothSides() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 2, spineCount: 5, eval: eval, provider: { self.body($0) })
        await c.handleBoundarySignal(signal(visible: 2, top: true, bottom: true))
        #expect(c.window.lo == 1)
        #expect(c.window.hi == 3)
        #expect(eval.appends.count == 1)
        #expect(eval.prepends.count == 1)
    }

    // MARK: - defensive provider check (round-1 [L2])

    @Test func providerReturnsWrongSpineIndex_abortsExtend_noEval() async {
        let eval = RecordingEvaluator()
        // Provider returns a body for the WRONG index (42) regardless of request.
        let c = makeCoordinator(anchor: 0, spineCount: 5, eval: eval, provider: { _ in self.body(42) })
        await c.handleBoundarySignal(signal(visible: 0, bottom: true))
        #expect(c.window == EPUBSpineWindow.initial(anchor: 0, spineCount: 5)!)
        #expect(eval.evaluatedJS.isEmpty)
    }

    // MARK: - stale generation DURING eviction (round-1 [H1])

    @Test func invalidateDuringEviction_doesNotPublishEvictedWindow() async {
        let eval = RecordingEvaluator()
        let holder = CoordHolder()
        // maxSpan 3, read forward 0→1→2 so the 3rd extend evicts index 0. On that
        // remove eval, invalidate (simulate a mode-switch mid-eviction).
        let c = makeCoordinator(anchor: 0, spineCount: 10, maxSpan: 3, eval: eval, provider: { self.body($0) })
        holder.c = c
        await c.handleBoundarySignal(signal(visible: 0, bottom: true)) // [0,1]
        await c.handleBoundarySignal(signal(visible: 1, bottom: true)) // [0,2]
        eval.onRemoveEval = { holder.c?.invalidate() }                 // bump gen during the evict remove
        await c.handleBoundarySignal(signal(visible: 2, bottom: true)) // would be [0,3]→evict→[1,3]
        // The stale task must NOT publish the evicted RANGE over the new generation:
        // the materialized range stays [0,2] (the pre-extend value), not [1,3].
        // (The anchor moved to 2 via the pre-extend re-anchor, which is correct +
        // DOM-independent — only the lo/hi range tracks materialized sections.)
        #expect(c.window.lo == 0 && c.window.hi == 2)  // evicted [1,3] NOT published
        #expect(eval.removedSpineIndex(0))              // the remove WAS emitted (gen current at the loop-top check)
    }

    // MARK: - materializeInitialWindow (Feature #71 WI-6b-i)

    @Test func materializeInitialWindow_appendsAnchorThenExtendsBothSides() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 2, spineCount: 5, eval: eval, provider: { self.body($0) })
        await c.materializeInitialWindow()
        // Anchor (2) + forward (3) appended; backward (1) prepended → window [1,3].
        #expect(eval.appends.contains { $0.contains("data-vreader-spine-index=\"2\"") })
        #expect(eval.appends.contains { $0.contains("data-vreader-spine-index=\"3\"") })
        #expect(eval.prepends.contains { $0.contains("data-vreader-spine-index=\"1\"") })
        #expect(c.window.lo == 1 && c.window.hi == 3 && c.window.anchor == 2)
    }

    @Test func materializeInitialWindow_atFirstChapter_appendsAnchorAndForwardOnly() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 0, spineCount: 5, eval: eval, provider: { self.body($0) })
        await c.materializeInitialWindow()
        #expect(eval.appends.contains { $0.contains("data-vreader-spine-index=\"0\"") })
        #expect(eval.appends.contains { $0.contains("data-vreader-spine-index=\"1\"") })
        #expect(eval.prepends.isEmpty)
        #expect(c.window.lo == 0 && c.window.hi == 1)
    }

    @Test func materializeInitialWindow_singleChapter_appendsAnchorOnly() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 0, spineCount: 1, eval: eval, provider: { self.body($0) })
        await c.materializeInitialWindow()
        #expect(eval.appends.count == 1)
        #expect(eval.appends.contains { $0.contains("data-vreader-spine-index=\"0\"") })
        #expect(eval.prepends.isEmpty)
        #expect(c.window.lo == 0 && c.window.hi == 0)
    }

    @Test func materializeInitialWindow_anchorAppendFails_windowUnchanged_noExtend() async {
        let eval = RecordingEvaluator()
        eval.shouldThrow = true
        let c = makeCoordinator(anchor: 2, spineCount: 5, eval: eval, provider: { self.body($0) })
        await c.materializeInitialWindow()
        // The anchor append threw → abort: no sections, window stays [2,2].
        #expect(eval.appends.isEmpty)
        #expect(c.window == EPUBSpineWindow.initial(anchor: 2, spineCount: 5)!)
    }

    // WI-6b-iii: saved-position restore — after the initial window materializes,
    // scroll the anchor section to the restore fraction.
    @Test func materializeInitialWindow_withRestoreFraction_scrollsAnchorToFraction() async {
        let eval = RecordingEvaluator()
        let c = EPUBContinuousScrollCoordinator(
            initialWindow: EPUBSpineWindow.initial(anchor: 2, spineCount: 5)!,
            chapterBodyProvider: { self.body($0) },
            evaluate: { try await eval.evaluate($0) },
            restoreFraction: 0.5
        )
        await c.materializeInitialWindow()
        // A scrollToSpineFraction eval (recognized by its scrollTop math) was
        // emitted, targeting the anchor section, AFTER the section appends.
        let scrollEvals = eval.evaluatedJS.filter { $0.contains("root.scrollTop = el.offsetTop") }
        #expect(scrollEvals.count == 1)
        #expect(scrollEvals.first?.contains(#"data-vreader-spine-index="2""#) == true)
        #expect(scrollEvals.first?.contains("* 0.5") == true)
    }

    @Test func materializeInitialWindow_noRestoreFraction_doesNotScroll() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 2, spineCount: 5, eval: eval, provider: { self.body($0) })
        await c.materializeInitialWindow()
        #expect(eval.evaluatedJS.contains { $0.contains("root.scrollTop = el.offsetTop") } == false)
    }

    @Test func materializeInitialWindow_zeroRestoreFraction_doesNotScroll() async {
        let eval = RecordingEvaluator()
        let c = EPUBContinuousScrollCoordinator(
            initialWindow: EPUBSpineWindow.initial(anchor: 0, spineCount: 3)!,
            chapterBodyProvider: { self.body($0) },
            evaluate: { try await eval.evaluate($0) },
            restoreFraction: 0
        )
        await c.materializeInitialWindow()
        #expect(eval.evaluatedJS.contains { $0.contains("root.scrollTop = el.offsetTop") } == false)
    }

    // MARK: - WI-8: continuous-mode navigation (TOC / bookmark / search jump)

    @Test func navigate_inWindow_scrollsAndReanchors() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 2, spineCount: 6, eval: eval, provider: { self.body($0) })
        await c.materializeInitialWindow()   // window → [1,3]
        #expect(c.window.contains(3))
        eval.evaluatedJS.removeAll()
        await c.navigate(toSpineIndex: 3, fraction: 0.25)
        // In-window: a single scroll to section 3, no remove/append, re-anchored.
        let scrolls = eval.evaluatedJS.filter { $0.contains("root.scrollTop = el.offsetTop") }
        #expect(scrolls.count == 1)
        #expect(scrolls.first?.contains(#"data-vreader-spine-index="3""#) == true)
        #expect(eval.removes.isEmpty)
        #expect(eval.appends.isEmpty)
        #expect(c.window.anchor == 3)
    }

    @Test func navigate_outOfWindow_rebuildsAroundTarget() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 0, spineCount: 10, eval: eval, provider: { self.body($0) })
        await c.materializeInitialWindow()   // window → [0,1]
        #expect(c.window == EPUBSpineWindow.initial(anchor: 0, spineCount: 10)!.extendForward())
        eval.evaluatedJS.removeAll()
        let moved = await c.navigate(toSpineIndex: 7, fraction: 0.5)
        #expect(moved)
        // Out-of-window: ONE atomic eval clears (replaceChildren) AND inserts the
        // target anchor (7) together, then ±1 rebuild around 7 → [6,8].
        #expect(eval.evaluatedJS.contains {
            $0.contains("replaceChildren") && $0.contains(#"data-vreader-spine-index="7""#)
        })
        #expect(c.window.contains(7))
        #expect(c.window.anchor == 7)
        #expect(c.window.lo == 6 && c.window.hi == 8)
        // Neighbours 6 + 8 materialized; scrolled to the target fraction.
        #expect(eval.evaluatedJS.contains { $0.contains(#"data-vreader-spine-index="8""#) })
        #expect(eval.evaluatedJS.contains { $0.contains(#"data-vreader-spine-index="6""#) })
        #expect(eval.evaluatedJS.contains {
            $0.contains("root.scrollTop = el.offsetTop") && $0.contains(#"data-vreader-spine-index="7""#)
        })
    }

    @Test func navigate_whileExtending_isDropped() async {
        let eval = RecordingEvaluator()
        let gate = CheckedContinuationGate()
        let c = makeCoordinator(anchor: 0, spineCount: 8, eval: eval, provider: { idx in
            await gate.wait()   // hold the first extend in-flight
            return self.body(idx)
        })
        // Drive a boundary extend that blocks at the provider await (isExtending=true).
        async let a: Void = c.handleBoundarySignal(signal(visible: 0, bottom: true))
        while !c.isExtending { await Task.yield() }
        eval.evaluatedJS.removeAll()
        // A navigate arriving mid-extend is dropped (serialized), not interleaved.
        let moved = await c.navigate(toSpineIndex: 5, fraction: 0.5)
        #expect(moved == false)
        #expect(eval.evaluatedJS.isEmpty)   // no clear / append / scroll emitted
        #expect(!c.window.contains(5))
        gate.open()
        await a
    }

    @Test func navigate_duringInitialMaterialize_isDropped() async {
        let eval = RecordingEvaluator()
        let gate = CheckedContinuationGate()
        let c = makeCoordinator(anchor: 2, spineCount: 8, eval: eval, provider: { idx in
            await gate.wait()   // hold the initial anchor materialize in-flight
            return self.body(idx)
        })
        // Round-2 Critical: initial materialize must own the mutation lane too,
        // so a jump arriving while the anchor provider is suspended is dropped
        // (not interleaved over the initial DOM).
        async let m: Void = c.materializeInitialWindow()
        while !c.isExtending { await Task.yield() }
        let moved = await c.navigate(toSpineIndex: 5, fraction: 0.5)
        #expect(moved == false)
        #expect(!c.window.contains(5))
        gate.open()
        await m
    }

    @Test func navigate_outOfRange_isNoOp() async {
        let eval = RecordingEvaluator()
        let c = makeCoordinator(anchor: 0, spineCount: 3, eval: eval, provider: { self.body($0) })
        await c.materializeInitialWindow()
        let windowBefore = c.window
        eval.evaluatedJS.removeAll()
        await c.navigate(toSpineIndex: 99, fraction: 0.5)   // out of spine range
        #expect(eval.evaluatedJS.isEmpty)
        #expect(c.window == windowBefore)
    }

    @Test func navigate_rapidDoubleInWindow_secondIsDropped() async {
        // Gate-4 round-3 High: in-window `navigate` must hold the mutation lane
        // for its whole body (not just the out-of-window rebuild). Two rapid
        // in-window jumps must NOT both pass `guard !isExtending`; the second is
        // dropped while the first scroll is still in flight, so positions don't
        // interleave.
        let eval = RecordingEvaluator()
        let gate = CheckedContinuationGate()
        let c = makeCoordinator(anchor: 2, spineCount: 6, eval: eval, provider: { self.body($0) })
        await c.materializeInitialWindow()   // window → [1,3]; both 1 and 3 in-window
        eval.evaluatedJS.removeAll()
        // Hold the first navigate's in-window scroll eval in flight.
        eval.beforeEvaluate = { js in
            if js.contains("root.scrollTop = el.offsetTop") { await gate.wait() }
        }
        async let first = c.navigate(toSpineIndex: 3, fraction: 0.25)
        while !c.isExtending { await Task.yield() }
        eval.beforeEvaluate = nil   // don't gate any later eval
        // A second in-window jump arriving mid-scroll is serialized out.
        let second = await c.navigate(toSpineIndex: 1, fraction: 0.0)
        #expect(second == false)
        gate.open()
        let firstResult = await first
        #expect(firstResult)
        // Exactly one scroll happened (the first); the second emitted nothing,
        // and the eviction anchor reflects the first target only.
        #expect(eval.evaluatedJS.filter { $0.contains("root.scrollTop = el.offsetTop") }.count == 1)
        #expect(c.window.anchor == 3)
    }

    /// A tiny @MainActor gate so a stub provider can be held mid-materialization.
    @MainActor
    final class CheckedContinuationGate {
        private var continuation: CheckedContinuation<Void, Never>?
        private var opened = false
        func wait() async {
            if opened { return }
            await withCheckedContinuation { continuation = $0 }
        }
        func open() {
            opened = true
            continuation?.resume()
            continuation = nil
        }
    }
}
