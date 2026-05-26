// Purpose: Tests for EPUBContinuousScrollCoordinator — the @MainActor
// window-transition decision logic for the EPUB continuous-scroll document
// (feature #71, WI-4). No live WKWebView: a recording stub evaluator + a stub
// chapter-body provider stand in for the bridge, so the whole
// materialize / evict / generation policy is exercised here.
//
// Focus (the WI-4 test catalogue):
//   - nearBottom at hi<spineCount-1 ⇒ extend forward + emit ONE append;
//   - a duplicate signal while a materialization is IN FLIGHT does NOT
//     double-append (idempotency, gated provider);
//   - nearTop at lo>0 ⇒ prepend;
//   - at the last / first chapter ⇒ no-op (no JS);
//   - partial failure: provider throws OR evaluator throws ⇒ window does NOT
//     advance;
//   - stale generation: a provider task resolving after bumpGeneration() is
//     discarded (no eval, no mutate);
//   - eviction emits a remove JS for the trimmed spine index;
//   - sequential forward signals advance the window consistently.
//
// @coordinates-with: EPUBContinuousScrollCoordinator.swift,
//   EPUBSpineWindow.swift, EPUBContinuousScrollJS.swift,
//   EPUBChapterBodyRewriter.swift (EPUBChapterBody)

import XCTest
@testable import vreader

@MainActor
final class EPUBContinuousScrollCoordinatorTests: XCTestCase {

    // MARK: - Test doubles

    /// Records the JS emitted to the (stub) WKWebView and can be told to fail.
    @MainActor
    private final class RecordingEvaluator {
        private(set) var scripts: [String] = []
        var shouldThrow = false
        /// Throw only on a remove-section (eviction) eval — lets a test assert
        /// the window is left un-trimmed when eviction fails after a successful
        /// append.
        var throwOnRemove = false
        enum EvalError: Error { case failed }

        func eval(_ js: String) async throws {
            if shouldThrow { throw EvalError.failed }
            if throwOnRemove, js.contains(".remove()") { throw EvalError.failed }
            scripts.append(js)
        }

        var appendCount: Int { scripts.filter { $0.contains("beforeend") }.count }
        var prependCount: Int { scripts.filter { $0.contains("afterbegin") }.count }
        func appendTargets(_ index: Int) -> Bool {
            scripts.contains { $0.contains("beforeend") && $0.contains("data-vreader-spine-index=\"\(index)\"") }
        }
        func removed(_ index: Int) -> Bool {
            scripts.contains { $0.contains(".remove()") && $0.contains("data-vreader-spine-index=\"\(index)\"") }
        }
    }

    /// A provider whose `provide(_:)` suspends until `release(with:)` is called
    /// — lets a test pause a materialization mid-flight to drive the
    /// idempotency + stale-generation cases deterministically.
    @MainActor
    private final class GatedBodyProvider {
        private var continuation: CheckedContinuation<EPUBChapterBody, Error>?
        let called: XCTestExpectation
        private(set) var lastRequestedIndex: Int?

        init(called: XCTestExpectation) { self.called = called }

        func provide(_ index: Int) async throws -> EPUBChapterBody {
            lastRequestedIndex = index
            called.fulfill()
            return try await withCheckedThrowingContinuation { self.continuation = $0 }
        }

        func release(with body: EPUBChapterBody) {
            continuation?.resume(returning: body)
            continuation = nil
        }
    }

    private func body(_ index: Int) -> EPUBChapterBody {
        EPUBChapterBody(
            spineIndex: index,
            href: "OEBPS/text/c\(index).xhtml",
            bodyHTML: "<p>chapter \(index)</p>",
            scopedStyleHTML: ""
        )
    }

    private func signal(
        visible: Int,
        top: Bool = false,
        bottom: Bool = false
    ) -> EPUBScrollBoundarySignal {
        EPUBScrollBoundarySignal(
            visibleSpineIndex: visible,
            intraFraction: 0,
            nearTopBoundary: top,
            nearBottomBoundary: bottom
        )
    }

    /// Builds a coordinator with an instant (non-suspending) body provider.
    private func makeCoordinator(
        window: EPUBSpineWindow,
        maxSpan: Int,
        evaluator: RecordingEvaluator,
        providerThrows: Bool = false
    ) -> EPUBContinuousScrollCoordinator {
        EPUBContinuousScrollCoordinator(
            window: window,
            maxSpan: maxSpan,
            chapterBodyProvider: { [unowned self] index in
                if providerThrows { throw RecordingEvaluator.EvalError.failed }
                return self.body(index)
            },
            evaluate: { try await evaluator.eval($0) }
        )
    }

    // MARK: - Extend forward

    func test_nearBottom_extendsForward_emitsOneAppend() async throws {
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 0, spineCount: 5))
        let evaluator = RecordingEvaluator()
        let coord = makeCoordinator(window: window, maxSpan: 5, evaluator: evaluator)

        await coord.handle(signal(visible: 0, bottom: true))

        XCTAssertTrue(coord.window.contains(1), "window should have grown to include spine 1")
        XCTAssertEqual(evaluator.appendCount, 1, "exactly one append should be emitted")
        XCTAssertTrue(evaluator.appendTargets(1), "the append should materialize spine 1")
        XCTAssertEqual(evaluator.prependCount, 0)
    }

    // MARK: - Extend backward

    func test_nearTop_extendsBackward_emitsPrepend() async throws {
        // Mid-book singleton window 3...3, anchor 3.
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 3, spineCount: 10))
        let evaluator = RecordingEvaluator()
        let coord = makeCoordinator(window: window, maxSpan: 5, evaluator: evaluator)

        await coord.handle(signal(visible: 3, top: true))

        XCTAssertTrue(coord.window.contains(2), "window should have grown to include spine 2")
        XCTAssertEqual(evaluator.prependCount, 1)
        XCTAssertEqual(evaluator.appendCount, 0)
    }

    // MARK: - Book-edge no-ops

    func test_atLastChapter_nearBottom_isNoOp() async throws {
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 4, spineCount: 5)) // hi == last
        let evaluator = RecordingEvaluator()
        let coord = makeCoordinator(window: window, maxSpan: 5, evaluator: evaluator)

        await coord.handle(signal(visible: 4, bottom: true))

        XCTAssertEqual(coord.window, window, "window must not change at the last chapter")
        XCTAssertTrue(evaluator.scripts.isEmpty, "no JS should be emitted")
    }

    func test_atFirstChapter_nearTop_isNoOp() async throws {
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 0, spineCount: 5)) // lo == 0
        let evaluator = RecordingEvaluator()
        let coord = makeCoordinator(window: window, maxSpan: 5, evaluator: evaluator)

        await coord.handle(signal(visible: 0, top: true))

        XCTAssertEqual(coord.window, window)
        XCTAssertTrue(evaluator.scripts.isEmpty)
    }

    // MARK: - Partial failure — window must not advance

    func test_evaluatorThrows_windowDoesNotAdvance() async throws {
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 0, spineCount: 5))
        let evaluator = RecordingEvaluator()
        evaluator.shouldThrow = true
        let coord = makeCoordinator(window: window, maxSpan: 5, evaluator: evaluator)

        await coord.handle(signal(visible: 0, bottom: true))

        XCTAssertEqual(coord.window, window, "a failed eval must not advance the window")
        XCTAssertTrue(evaluator.scripts.isEmpty)
    }

    func test_providerThrows_windowDoesNotAdvance() async throws {
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 0, spineCount: 5))
        let evaluator = RecordingEvaluator()
        let coord = makeCoordinator(window: window, maxSpan: 5, evaluator: evaluator, providerThrows: true)

        await coord.handle(signal(visible: 0, bottom: true))

        XCTAssertEqual(coord.window, window, "a failed chapter fetch must not advance the window")
        XCTAssertTrue(evaluator.scripts.isEmpty)
    }

    // MARK: - Idempotency — duplicate signal in flight

    func test_duplicateSignalWhileInFlight_doesNotDoubleAppend() async throws {
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 0, spineCount: 5))
        let evaluator = RecordingEvaluator()
        let providerCalled = expectation(description: "first provider call")
        let gated = GatedBodyProvider(called: providerCalled)
        let coord = EPUBContinuousScrollCoordinator(
            window: window, maxSpan: 5,
            chapterBodyProvider: { try await gated.provide($0) },
            evaluate: { try await evaluator.eval($0) }
        )

        // First signal starts a materialization that suspends at the provider.
        let first = Task { await coord.handle(self.signal(visible: 0, bottom: true)) }
        await fulfillment(of: [providerCalled], timeout: 2)

        // A duplicate signal arrives WHILE the first is in flight → ignored.
        await coord.handle(signal(visible: 0, bottom: true))

        // Release the first; it appends exactly once.
        gated.release(with: body(1))
        await first.value

        XCTAssertEqual(evaluator.appendCount, 1, "an in-flight duplicate must not double-append")
        XCTAssertTrue(coord.window.contains(1))
    }

    // MARK: - Stale generation

    func test_staleGeneration_inFlightTaskDiscarded() async throws {
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 0, spineCount: 5))
        let evaluator = RecordingEvaluator()
        let providerCalled = expectation(description: "provider call")
        let gated = GatedBodyProvider(called: providerCalled)
        let coord = EPUBContinuousScrollCoordinator(
            window: window, maxSpan: 5,
            chapterBodyProvider: { try await gated.provide($0) },
            evaluate: { try await evaluator.eval($0) }
        )

        let task = Task { await coord.handle(self.signal(visible: 0, bottom: true)) }
        await fulfillment(of: [providerCalled], timeout: 2)

        // A mode-switch / reopen bumps the generation while the fetch is in
        // flight — the resolving task must discard itself.
        coord.bumpGeneration()
        gated.release(with: body(1))
        await task.value

        XCTAssertEqual(coord.window, window, "a stale generation must not mutate the window")
        XCTAssertTrue(evaluator.scripts.isEmpty, "a stale generation must not emit JS")
    }

    // MARK: - Eviction

    func test_eviction_emitsRemoveForTrimmedSpine() async throws {
        // Window 0...2, anchor 2 (reader at chapter 2). maxSpan 3.
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 2, spineCount: 10))
            .extendBackward().extendBackward() // 0...2, anchor 2
        let evaluator = RecordingEvaluator()
        let coord = makeCoordinator(window: window, maxSpan: 3, evaluator: evaluator)

        // Reader at chapter 2 hits the bottom → append 3 → span 4 > 3 →
        // evict the far-from-anchor (behind) chapter 0.
        await coord.handle(signal(visible: 2, bottom: true))

        XCTAssertTrue(evaluator.appendTargets(3), "spine 3 should be appended")
        XCTAssertTrue(evaluator.removed(0), "the far-behind spine 0 should be removed")
        XCTAssertTrue(coord.window.contains(3))
        XCTAssertFalse(coord.window.contains(0), "evicted spine 0 should leave the window")
    }

    // MARK: - Sequential advancement

    func test_sequentialForwardSignals_advanceConsistently() async throws {
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 0, spineCount: 10))
        let evaluator = RecordingEvaluator()
        let coord = makeCoordinator(window: window, maxSpan: 10, evaluator: evaluator) // no eviction

        await coord.handle(signal(visible: 0, bottom: true)) // → +1
        await coord.handle(signal(visible: 1, bottom: true)) // → +2
        await coord.handle(signal(visible: 2, bottom: true)) // → +3

        XCTAssertEqual(evaluator.appendCount, 3)
        XCTAssertTrue(coord.window.contains(3))
        XCTAssertFalse(coord.window.contains(4))
    }

    // MARK: - Gate-4 round-1: failure must not mutate the anchor

    func test_evaluatorThrows_anchorAlsoUnchanged() async throws {
        // Window 0...2, anchor 0. A signal whose visibleSpineIndex (2) differs
        // from the current anchor must NOT move the anchor when the eval fails:
        // the whole window (incl. anchor) is full-state equal to the original.
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 0, spineCount: 6))
            .extendForward().extendForward() // 0...2, anchor 0
        let evaluator = RecordingEvaluator()
        evaluator.shouldThrow = true
        let coord = makeCoordinator(window: window, maxSpan: 5, evaluator: evaluator)

        await coord.handle(signal(visible: 2, bottom: true))

        XCTAssertEqual(coord.window, window, "a failed eval must not move the eviction anchor")
        XCTAssertTrue(evaluator.scripts.isEmpty)
    }

    func test_duplicateInFlight_differentVisible_cannotChangeEvictedSide() async throws {
        // Window 0...2, anchor 2 (reader at chapter 2), maxSpan 3. The first
        // signal (visible 2, bottom) will append 3 then evict the far-behind
        // chapter 0. A duplicate arriving in flight carries visible 0 — if the
        // guard leaked, it would re-anchor to 0 and evict the just-appended 3
        // instead. The in-flight guard must make the duplicate a full no-op.
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 2, spineCount: 10))
            .extendBackward().extendBackward() // 0...2, anchor 2
        let evaluator = RecordingEvaluator()
        let providerCalled = expectation(description: "provider call")
        let gated = GatedBodyProvider(called: providerCalled)
        let coord = EPUBContinuousScrollCoordinator(
            window: window, maxSpan: 3,
            chapterBodyProvider: { try await gated.provide($0) },
            evaluate: { try await evaluator.eval($0) }
        )

        let first = Task { await coord.handle(self.signal(visible: 2, bottom: true)) }
        await fulfillment(of: [providerCalled], timeout: 2)

        // Duplicate in flight, DIFFERENT visible index — must be ignored.
        await coord.handle(signal(visible: 0, bottom: true))

        gated.release(with: body(3))
        await first.value

        XCTAssertTrue(evaluator.removed(0), "should evict the far-behind chapter 0 (anchor 2)")
        XCTAssertFalse(evaluator.removed(3), "must NOT evict the freshly-appended chapter 3")
        XCTAssertTrue(coord.window.contains(3))
        XCTAssertFalse(coord.window.contains(0))
    }

    func test_evictEvalFails_leavesWindowUntrimmed() async throws {
        // Append succeeds, the subsequent remove (eviction) eval throws → the
        // window is left un-trimmed (degraded, still-correct: extra memory, not
        // a wrong render). The just-appended chapter is retained.
        let window = try XCTUnwrap(EPUBSpineWindow.initial(anchor: 2, spineCount: 10))
            .extendBackward().extendBackward() // 0...2, anchor 2
        let evaluator = RecordingEvaluator()
        evaluator.throwOnRemove = true
        let coord = makeCoordinator(window: window, maxSpan: 3, evaluator: evaluator)

        await coord.handle(signal(visible: 2, bottom: true))

        XCTAssertTrue(evaluator.appendTargets(3), "the append should have succeeded")
        XCTAssertTrue(coord.window.contains(3), "appended chapter retained")
        XCTAssertTrue(coord.window.contains(0), "failed eviction leaves chapter 0 in the window")
        XCTAssertEqual(coord.window, window.reanchored(to: 2).extendForward(),
                       "window committed the append but not the failed trim")
    }
}
