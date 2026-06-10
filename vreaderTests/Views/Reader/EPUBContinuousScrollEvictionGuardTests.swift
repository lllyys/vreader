// Purpose: Bug #329 (round 3) — the px-aware eviction guard. The evict→reload
// oscillation is GEOMETRIC: through short sections, trimming the trailing
// section drops the trailing side below the observer's prefetch threshold, so
// the opposite boundary flag re-asserts on EVERY subsequent scroll report (a
// one-shot echo suppression only delays each reload by one signal — the
// v3.59.22 inadequacy the 1px device sweep exposed). The guard defers eviction
// until the trailing side retains `prefetchPx + margin` px.
//
// The `StitchSimulator` suite is the unit-level twin of the on-device
// 1px DebugBridge sweep: a virtual stitched document with real section
// heights ("The Half Second" front matter), scrolled 1px per signal, applying
// the SAME scrollTop compensations the JS performs. Its control case (signals
// WITHOUT geometry → legacy eviction) reproduces the oscillation — proving
// the sim detects the bug — and the geometry case must be monotonic.
//
// @coordinates-with: EPUBContinuousScrollCoordinator.swift,
//   EPUBContinuousScrollJS.swift, EPUBContinuousScrollBridge.swift (parse)

import Testing
import Foundation
@testable import vreader

@Suite("Bug #329 round 3 — px-aware eviction guard")
struct EPUBContinuousScrollEvictionGuardTests {

    @MainActor
    final class RecordingEvaluator {
        var evaluatedJS: [String] = []
        func evaluate(_ js: String) async throws { evaluatedJS.append(js) }
        var appends: [String] { evaluatedJS.filter { $0.contains("beforeend") } }
        var prepends: [String] { evaluatedJS.filter { $0.contains("afterbegin") } }
        var removes: [String] { evaluatedJS.filter { $0.contains("el.remove()") } }
    }

    private func body(_ index: Int) -> EPUBChapterBody {
        EPUBChapterBody(spineIndex: index, href: "ch\(index).xhtml",
                        bodyHTML: "<p>chapter \(index)</p>", scopedStyleHTML: "")
    }

    @MainActor
    private func makeCoordinator(
        anchor: Int, spineCount: Int, maxSpan: Int = 3,
        eval: RecordingEvaluator
    ) -> EPUBContinuousScrollCoordinator {
        EPUBContinuousScrollCoordinator(
            initialWindow: EPUBSpineWindow.initial(anchor: anchor, spineCount: spineCount)!,
            maxSpan: maxSpan,
            chapterBodyProvider: { [body] in body($0) },
            evaluate: { try await eval.evaluate($0) })
    }

    private func signal(
        visible: Int, top: Bool = false, bottom: Bool = false,
        pxAbove: Int? = nil, pxBelow: Int? = nil, sectionHeights: [Int]? = nil,
        touchActive: Bool = false
    ) -> EPUBScrollBoundarySignal {
        EPUBScrollBoundarySignal(
            visibleSpineIndex: visible, intraFraction: 0.5,
            nearTopBoundary: top, nearBottomBoundary: bottom,
            pxAbove: pxAbove, pxBelow: pxBelow, sectionHeights: sectionHeights,
            touchActive: touchActive)
    }

    // MARK: - Guard unit behavior

    /// Drive a fresh coordinator's window up to [0, n] via geometry-free
    /// nearBottom signals (the established WI-4 test pattern — each signal
    /// extends forward once; span stays ≤ maxSpan so nothing evicts).
    @MainActor
    private func growWindowForward(
        _ coordinator: EPUBContinuousScrollCoordinator, to hi: Int
    ) async {
        var visible = 0
        while coordinator.window.hi < hi {
            await coordinator.handleBoundarySignal(signal(visible: visible, bottom: true))
            visible += 1
        }
    }

    /// The baseline-device scenario: window [0,2] (heights 554/270/660), reader
    /// near the bottom → the next forward extend would evict section 0, but
    /// pxAbove=725 minus 554 leaves only 171px above — under the prefetch
    /// threshold, where the spurious nearTop re-asserts on EVERY following
    /// signal. The guard must DEFER: append happens, NO remove, window floats
    /// past maxSpan.
    @MainActor
    @Test func forwardEviction_deferred_whenTrailingSideWouldStrand() async {
        let eval = RecordingEvaluator()
        let coordinator = makeCoordinator(anchor: 0, spineCount: 54, eval: eval)
        await growWindowForward(coordinator, to: 2)                  // [0,2] at maxSpan
        #expect(coordinator.window.lo == 0 && coordinator.window.hi == 2)
        await coordinator.handleBoundarySignal(signal(
            visible: 2, bottom: true,
            pxAbove: 725, pxBelow: 100, sectionHeights: [554, 270, 660]))
        #expect(eval.appends.count == 3, "the forward extend itself proceeds (2 grow + this one)")
        #expect(eval.removes.isEmpty, "eviction deferred — trimming would strand 171px above")
        #expect(coordinator.window.lo == 0 && coordinator.window.hi == 3, "window floats past maxSpan")
    }

    /// With enough travelled distance (pxAbove 1500), trimming 554 leaves 946px
    /// — above prefetch(800)+margin(64) — so the eviction proceeds as before.
    @MainActor
    @Test func forwardEviction_proceeds_whenTrailingSlackRemains() async {
        let eval = RecordingEvaluator()
        let coordinator = makeCoordinator(anchor: 0, spineCount: 54, eval: eval)
        await growWindowForward(coordinator, to: 2)
        await coordinator.handleBoundarySignal(signal(
            visible: 2, bottom: true,
            pxAbove: 1500, pxBelow: 100, sectionHeights: [554, 270, 660]))
        #expect(eval.removes.count == 1, "554 trimmed leaves 946 > 864 — evict allowed")
        #expect(coordinator.window.lo == 1 && coordinator.window.hi == 3)
    }

    /// Grow a window downward to [lo, anchor] via geometry-free nearTop signals.
    @MainActor
    private func growWindowBackward(
        _ coordinator: EPUBContinuousScrollCoordinator, to lo: Int
    ) async {
        var visible = coordinator.window.anchor
        while coordinator.window.lo > lo {
            await coordinator.handleBoundarySignal(signal(visible: visible, top: true))
            visible = max(0, visible - 1)
        }
    }

    /// Symmetric: a backward extend trims the hi end (below the viewport, which
    /// shrinks pxBelow). When that would leave < prefetch+margin below, defer.
    @MainActor
    @Test func backwardEviction_deferred_whenBelowSideWouldStrand() async {
        let eval = RecordingEvaluator()
        let coordinator = makeCoordinator(anchor: 6, spineCount: 54, eval: eval)
        await growWindowBackward(coordinator, to: 4)                 // [4,6] at maxSpan
        #expect(coordinator.window.lo == 4 && coordinator.window.hi == 6)
        await coordinator.handleBoundarySignal(signal(
            visible: 4, top: true,
            pxAbove: 100, pxBelow: 900, sectionHeights: [500, 500, 700]))
        #expect(eval.removes.isEmpty, "900 - 700 = 200 < 864 — defer the hi trim")
        #expect(coordinator.window.lo == 3 && coordinator.window.hi == 6)
    }

    @MainActor
    @Test func backwardEviction_proceeds_withBelowSlack() async {
        let eval = RecordingEvaluator()
        let coordinator = makeCoordinator(anchor: 6, spineCount: 54, eval: eval)
        await growWindowBackward(coordinator, to: 4)
        await coordinator.handleBoundarySignal(signal(
            visible: 4, top: true,
            pxAbove: 100, pxBelow: 2000, sectionHeights: [500, 500, 700]))
        #expect(eval.removes.count == 1, "2000 - 700 = 1300 > 864 — evict allowed")
        #expect(coordinator.window.lo == 3 && coordinator.window.hi == 5)
    }

    /// Catch-up draining: a window that floated past maxSpan evicts cumulatively —
    /// each trim debits the budget; the loop stops at the first candidate that
    /// would strand the trailing side, deferring the rest to a fresher signal.
    @MainActor
    @Test func multiEvictCatchUp_cumulativeBudget_stopsMidway() async {
        let eval = RecordingEvaluator()
        let coordinator = makeCoordinator(anchor: 0, spineCount: 54, eval: eval)
        await growWindowForward(coordinator, to: 2)                  // [0,2]
        // Float the window to [0,4] (span 5) via two deferred forward extends.
        await coordinator.handleBoundarySignal(signal(
            visible: 2, bottom: true, pxAbove: 700, pxBelow: 50, sectionHeights: [300, 200, 660]))
        await coordinator.handleBoundarySignal(signal(
            visible: 3, bottom: true, pxAbove: 900, pxBelow: 50, sectionHeights: [300, 200, 660, 500]))
        #expect(coordinator.window.lo == 0 && coordinator.window.hi == 4, "two deferrals floated the span to 5")
        #expect(eval.removes.isEmpty)
        // A further forward signal with budget 1900: candidate 0 (300) leaves
        // 1600 ✓; candidate 1 (200) leaves 1400 ✓; candidate 2 (660) would leave
        // 740 < 864 ✗ — stop mid-catch-up with exactly two trims.
        await coordinator.handleBoundarySignal(signal(
            visible: 4, bottom: true,
            pxAbove: 1900, pxBelow: 50, sectionHeights: [300, 200, 660, 500, 480]))
        #expect(eval.removes.count == 2, "catch-up drained exactly two trims within budget")
        #expect(coordinator.window.lo == 2 && coordinator.window.hi == 5)
    }

    /// A raced snapshot (heights array shorter than the eviction needs) defers
    /// rather than trims blind — the next signal heals with fresh geometry.
    @MainActor
    @Test func racedHeightsSnapshot_defers() async {
        let eval = RecordingEvaluator()
        let coordinator = makeCoordinator(anchor: 0, spineCount: 54, eval: eval)
        await growWindowForward(coordinator, to: 2)
        await coordinator.handleBoundarySignal(signal(
            visible: 2, bottom: true,
            pxAbove: 5000, pxBelow: 50, sectionHeights: []))
        // Empty heights should never arrive (parse drops empty arrays), but the
        // coordinator must still defend: no candidate height → defer.
        #expect(eval.removes.isEmpty)
        #expect(coordinator.window.lo == 0 && coordinator.window.hi == 3)
    }

    /// Signals WITHOUT geometry (synthetic / DebugBridge / tests) keep the
    /// legacy span-only eviction — no behavior change for existing callers.
    @MainActor
    @Test func noGeometry_keepsLegacySpanEviction() async {
        let eval = RecordingEvaluator()
        let coordinator = makeCoordinator(anchor: 0, spineCount: 54, eval: eval)
        await growWindowForward(coordinator, to: 2)
        await coordinator.handleBoundarySignal(signal(visible: 2, bottom: true))
        #expect(eval.removes.count == 1, "nil geometry → legacy eviction at maxSpan")
        #expect(coordinator.window.lo == 1 && coordinator.window.hi == 3)
    }

    // MARK: - parse: geometry fields

    @Test func parse_carriesGeometryFields() {
        let body: [String: Any] = [
            "visibleSpineIndex": NSNumber(value: 2),
            "intraFraction": NSNumber(value: 0.5),
            "nearTopBoundary": NSNumber(value: false),
            "nearBottomBoundary": NSNumber(value: true),
            "pxAbove": NSNumber(value: 725),
            "pxBelow": NSNumber(value: 130),
            "sectionHeights": [NSNumber(value: 554), NSNumber(value: 270), NSNumber(value: 660)],
        ]
        let parsed = EPUBScrollBoundarySignal.parse(body)
        #expect(parsed?.pxAbove == 725)
        #expect(parsed?.pxBelow == 130)
        #expect(parsed?.sectionHeights == [554, 270, 660])
    }

    @Test func parse_missingGeometry_yieldsNilFields_signalStillParses() {
        let body: [String: Any] = [
            "visibleSpineIndex": NSNumber(value: 1),
            "intraFraction": NSNumber(value: 0.2),
        ]
        let parsed = EPUBScrollBoundarySignal.parse(body)
        #expect(parsed != nil)
        #expect(parsed?.pxAbove == nil)
        #expect(parsed?.sectionHeights == nil)
    }

    @Test func parse_malformedGeometry_dropsFieldNotSignal() {
        let body: [String: Any] = [
            "visibleSpineIndex": NSNumber(value: 1),
            "intraFraction": NSNumber(value: 0.2),
            "pxAbove": NSNumber(value: -5),                       // negative px = malformed
            "pxBelow": NSNumber(value: true),                     // bool = malformed
            "sectionHeights": [NSNumber(value: 100), "bogus"],    // partial array = dropped whole
        ]
        let parsed = EPUBScrollBoundarySignal.parse(body)
        #expect(parsed != nil, "geometry problems never reject the signal")
        #expect(parsed?.pxAbove == nil)
        #expect(parsed?.pxBelow == nil)
        #expect(parsed?.sectionHeights == nil)
    }

    @Test func parse_emptySectionHeights_dropped() {
        let body: [String: Any] = [
            "visibleSpineIndex": NSNumber(value: 1),
            "intraFraction": NSNumber(value: 0.2),
            "sectionHeights": [Any](),
        ]
        #expect(EPUBScrollBoundarySignal.parse(body)?.sectionHeights == nil)
    }

    // MARK: - observer JS shape

    @Test func observerJS_reportsGeometryAndUsesSharedPrefetchConstant() {
        let js = EPUBContinuousScrollJS.continuousScrollObserverJS
        #expect(js.contains("pxAbove: pxAbove"))
        #expect(js.contains("pxBelow: pxBelow"))
        #expect(js.contains("sectionHeights: sectionHeights"))
        #expect(js.contains("var PREFETCH_PX = \(EPUBContinuousScrollJS.prefetchPx);"),
                "the JS threshold and the Swift eviction guard share one constant")
    }

    @Test func observerJS_installsResizeCompensation() {
        let js = EPUBContinuousScrollJS.continuousScrollObserverJS
        #expect(js.contains("ResizeObserver"))
        #expect(js.contains("MutationObserver"), "newly stitched sections get observed")
        // First observation records a baseline only — the insert-time prepend
        // compensation already covered the initial height; compensating again
        // would double-shift.
        #expect(js.contains("if (oldH === undefined) { continue; }"))
        // Only sections ENTIRELY above the viewport (by their PRE-resize bottom —
        // Codex Gate-4 High) shift the reader's content.
        #expect(js.contains("(el.offsetTop + oldH) <= root.scrollTop"))
        // An EVICTED (disconnected) section must never compensate — its final
        // zero-size entry reads offsetTop 0 and would double-subtract on top of
        // removeChapterSectionJS's own compensation (the post-merge 1px sweep
        // caught scrollTop crashing to ~0 at multi-evict moments).
        #expect(js.contains("if (!el.isConnected) { continue; }"))
    }

    // MARK: - Bug #329 round 4: gesture-aware mutation deferral

    /// A forward extend during an ACTIVE touch must append WITHOUT evicting —
    /// the eviction's scrollTop compensation would be overridden by the live
    /// gesture anchor (the measured chapter runaway). The window floats above
    /// maxSpan for the touch's duration.
    @MainActor
    @Test func forwardExtendDuringTouch_appendsWithoutEvicting() async {
        let eval = RecordingEvaluator()
        let coordinator = makeCoordinator(anchor: 0, spineCount: 20, maxSpan: 3, eval: eval)
        await growWindowForward(coordinator, to: 2)   // [0,2] at maxSpan
        let before = coordinator.window

        await coordinator.handleBoundarySignal(signal(
            visible: 2, bottom: true,
            pxAbove: 5000, pxBelow: 100, sectionHeights: [3000, 3000, 3000],
            touchActive: true))

        #expect(coordinator.window.hi == before.hi + 1, "the append itself stays allowed")
        #expect(coordinator.window.lo == before.lo, "no eviction during an active touch")
        #expect(coordinator.window.span == before.span + 1, "the window floats above maxSpan")
        let removed = eval.evaluatedJS.filter { $0.contains(".remove()") }
        #expect(removed.isEmpty, "no section-remove JS during the touch")
    }

    /// The touchend report (touchActive false) drains the deferred eviction.
    @MainActor
    @Test func touchEndSignal_drainsDeferredEviction() async {
        let eval = RecordingEvaluator()
        let coordinator = makeCoordinator(anchor: 0, spineCount: 20, maxSpan: 3, eval: eval)
        await growWindowForward(coordinator, to: 2)
        await coordinator.handleBoundarySignal(signal(
            visible: 2, bottom: true,
            pxAbove: 5000, pxBelow: 100, sectionHeights: [3000, 3000, 3000],
            touchActive: true))
        #expect(coordinator.window.span == 4)

        // Touch ended; ample trailing slack → the backlog drains to maxSpan.
        await coordinator.handleBoundarySignal(signal(
            visible: 3, bottom: true,
            pxAbove: 9000, pxBelow: 100, sectionHeights: [3000, 3000, 3000, 3000],
            touchActive: false))
        #expect(coordinator.window.span <= 4, "post-touch signals drain the eviction backlog")
        let removed = eval.evaluatedJS.filter { $0.contains(".remove()") }
        #expect(!removed.isEmpty, "the deferred eviction ran after the touch ended")
    }

    /// A backward (prepend) extend during an active touch is deferred entirely
    /// — its scrollTop += h compensation would be overridden by the gesture.
    @MainActor
    @Test func backwardExtendDuringTouch_isDeferred() async {
        let eval = RecordingEvaluator()
        let coordinator = makeCoordinator(anchor: 5, spineCount: 20, maxSpan: 3, eval: eval)
        await growWindowForward(coordinator, to: 7)   // window [5,7]
        let before = coordinator.window
        let evalsBefore = eval.evaluatedJS.count

        await coordinator.handleBoundarySignal(signal(
            visible: 5, top: true,
            pxAbove: 100, pxBelow: 5000, sectionHeights: [3000, 3000, 3000],
            touchActive: true))
        #expect(coordinator.window == before, "no backward extend during an active touch")
        #expect(eval.evaluatedJS.count == evalsBefore, "no DOM mutation during the touch")

        // Touch ended → the same boundary now extends backward.
        await coordinator.handleBoundarySignal(signal(
            visible: 5, top: true,
            pxAbove: 100, pxBelow: 5000, sectionHeights: [3000, 3000, 3000],
            touchActive: false))
        #expect(coordinator.window.lo == before.lo - 1, "the deferred prepend ran after touchend")
    }
}

// MARK: - 1px physics simulation

/// The unit-level twin of the on-device 1px DebugBridge sweep: a virtual
/// stitched document scrolled one px per signal, applying the same scrollTop
/// compensations `EPUBContinuousScrollJS` performs (prepend +h, above-viewport
/// remove −h, browser clamping). The CONTROL case (geometry withheld → legacy
/// span eviction) must REPRODUCE the oscillation — proving this sim detects the
/// bug — and the geometry case must be jump-free and reach the target chapter.
@Suite("Bug #329 round 3 — 1px stitch simulation")
struct EPUBContinuousScroll1pxSimulationTests {

    /// "The Half Second" front-matter-like geometry (short sections — the
    /// degenerate case) followed by normal-length chapters.
    static let sectionHeights = [555, 270, 660, 300, 520, 480, 700, 1500, 2200, 1800, 2400, 2000]
    static let viewportH = 874

    @MainActor
    final class StitchSimulator {
        let heights: [Int]
        let viewportH: Int
        private(set) var materialized: [Int]   // spine indexes in DOM order
        private(set) var scrollTop = 0

        init(heights: [Int], viewportH: Int, initialMaterialized: [Int]) {
            self.heights = heights
            self.viewportH = viewportH
            self.materialized = initialMaterialized
        }

        var scrollHeight: Int { materialized.reduce(0) { $0 + heights[$1] } }
        var maxScrollTop: Int { max(0, scrollHeight - viewportH) }

        func offsetTop(ofPosition position: Int) -> Int {
            materialized.prefix(position).reduce(0) { $0 + heights[$1] }
        }

        /// Set when the coordinator stitches a section that is already in the
        /// DOM — a window↔DOM desync that would corrupt every measurement after
        /// it. The sweep asserts this never happens.
        private(set) var desyncDetected = false

        /// Mirror of the real JS effects, parsed from the evaluated snippets.
        func apply(js: String) {
            func spineIndex(_ js: String) -> Int? {
                guard let range = js.range(of: #"data-vreader-spine-index=\\?"(\d+)\\?""#,
                                           options: .regularExpression) else { return nil }
                let digits = js[range].filter(\.isNumber)
                return Int(digits)
            }
            if js.contains("beforeend") {
                if let idx = spineIndex(js) {
                    if materialized.contains(idx) { desyncDetected = true }
                    materialized.append(idx)
                }
            } else if js.contains("afterbegin") {
                if let idx = spineIndex(js) {
                    if materialized.contains(idx) { desyncDetected = true }
                    materialized.insert(idx, at: 0)
                    scrollTop += heights[idx]   // the prepend's in-eval compensation
                }
            } else if js.contains("el.remove()") {
                if let idx = spineIndex(js), let pos = materialized.firstIndex(of: idx) {
                    let wasAbove = offsetTop(ofPosition: pos) < scrollTop
                    materialized.remove(at: pos)
                    if wasAbove { scrollTop -= heights[idx] }   // removeChapterSectionJS
                }
            }
            scrollTop = min(max(0, scrollTop), maxScrollTop)    // browser clamp
        }

        /// The observer's report for the current virtual DOM.
        func currentSignal(withGeometry: Bool) -> EPUBScrollBoundarySignal {
            var visiblePos = 0
            for position in materialized.indices where offsetTop(ofPosition: position) <= scrollTop {
                visiblePos = position
            }
            let visible = materialized[visiblePos]
            let h = max(1, heights[visible])
            let intra = Double(scrollTop - offsetTop(ofPosition: visiblePos)) / Double(h)
            let pxAbove = scrollTop
            let pxBelow = max(0, scrollHeight - scrollTop - viewportH)
            return EPUBScrollBoundarySignal(
                visibleSpineIndex: visible,
                intraFraction: min(max(intra, 0), 1),
                nearTopBoundary: pxAbove <= EPUBContinuousScrollJS.prefetchPx,
                nearBottomBoundary: pxBelow <= EPUBContinuousScrollJS.prefetchPx,
                pxAbove: withGeometry ? pxAbove : nil,
                pxBelow: withGeometry ? pxBelow : nil,
                sectionHeights: withGeometry ? materialized.map { heights[$0] } : nil)
        }

        /// The eviction-invariant content position: (visible spine, px into it).
        var contentPosition: (spine: Int, off: Int) {
            var visiblePos = 0
            for position in materialized.indices where offsetTop(ofPosition: position) <= scrollTop {
                visiblePos = position
            }
            return (materialized[visiblePos], scrollTop - offsetTop(ofPosition: visiblePos))
        }

        /// One 1px forward step (the browser clamps at the document end).
        func stepOnePx() {
            scrollTop = min(scrollTop + 1, maxScrollTop)
        }
    }

    /// Run the 1px sweep against a live coordinator; returns (backwardJumps,
    /// maxSpineReached, sawWindowRegression).
    @MainActor
    private func runSweep(
        withGeometry: Bool, steps: Int, targetSpine: Int
    ) async -> (jumps: Int, maxSpine: Int, loRegressions: Int, desync: Bool) {
        let heights = Self.sectionHeights
        let sim = StitchSimulator(
            heights: heights, viewportH: Self.viewportH, initialMaterialized: [0])
        let coordinator = EPUBContinuousScrollCoordinator(
            initialWindow: EPUBSpineWindow.initial(anchor: 0, spineCount: heights.count)!,
            maxSpan: 3,
            chapterBodyProvider: { idx in
                EPUBChapterBody(spineIndex: idx, href: "ch\(idx).xhtml",
                                bodyHTML: "<p>c\(idx)</p>", scopedStyleHTML: "")
            },
            evaluate: { js in sim.apply(js: js) })
        // Align the coordinator window with the sim's bootstrap [0,1]:
        await coordinator.handleBoundarySignal(sim.currentSignal(withGeometry: withGeometry))

        var jumps = 0
        var loRegressions = 0
        var maxSpine = 0
        var lastPosition = sim.contentPosition
        var lastLo = coordinator.window.lo
        var violations: [String] = []
        for step in 0..<steps {
            sim.stepOnePx()
            let preWindow = (coordinator.window.lo, coordinator.window.hi)
            let preTop = sim.scrollTop
            await coordinator.handleBoundarySignal(sim.currentSignal(withGeometry: withGeometry))
            let position = sim.contentPosition
            if (position.spine, position.off) < (lastPosition.spine, lastPosition.off) {
                jumps += 1
                violations.append(
                    "step \(step): pos (\(lastPosition.spine),\(lastPosition.off))→(\(position.spine),\(position.off)) "
                    + "win \(preWindow)→(\(coordinator.window.lo),\(coordinator.window.hi)) "
                    + "scrollTop \(preTop)→\(sim.scrollTop) materialized \(sim.materialized)")
            }
            if coordinator.window.lo < lastLo {
                loRegressions += 1
                violations.append(
                    "step \(step): LO REGRESSION \(lastLo)→\(coordinator.window.lo) "
                    + "win→(\(coordinator.window.lo),\(coordinator.window.hi)) scrollTop \(preTop)→\(sim.scrollTop)")
            }
            lastPosition = position
            lastLo = coordinator.window.lo
            maxSpine = max(maxSpine, position.spine)
            if position.spine >= targetSpine { break }
        }
        if !violations.isEmpty {
            print("[b329-sim] violations:\n" + violations.joined(separator: "\n"))
        }
        return (jumps, maxSpine, loRegressions, sim.desyncDetected)
    }

    /// CONTROL: geometry withheld → legacy span-only eviction. The sim must
    /// REPRODUCE the device oscillation (backward jumps + window regressions +
    /// trapped progress) — proving the simulation detects the bug class.
    @MainActor
    @Test func control_legacyEviction_oscillates() async {
        let result = await runSweep(withGeometry: false, steps: 6000, targetSpine: 6)
        #expect(result.jumps > 0, "the control must reproduce the backward jumps")
        #expect(result.loRegressions > 0, "the control must reproduce the window collapse")
        #expect(result.maxSpine < 6, "the control stays trapped in the front matter")
    }

    /// THE FIX: with geometry, 1px scrolling across the same short front matter
    /// is perfectly monotonic — zero backward jumps, zero window regressions —
    /// and reaches chapter 6.
    @MainActor
    @Test func guarded_1pxSweep_isMonotonic_andReachesChapter6() async {
        let result = await runSweep(withGeometry: true, steps: 12000, targetSpine: 6)
        #expect(result.jumps == 0, "content position must never move backward at 1px steps")
        #expect(result.loRegressions == 0, "the window must never reload an evicted leading edge")
        #expect(result.maxSpine >= 6, "the sweep must actually cross ≥5 chapter boundaries")
        #expect(!result.desync, "the coordinator window and the DOM must never desync")
    }
}
