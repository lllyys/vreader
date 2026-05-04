// Purpose: RED tests for Bug #77 — Cannot add highlight in native EPUB.
// Proves the root cause: EPUBHighlightRenderer silently drops JS when onInjectJS
// is nil (race between .task callback setup and highlight creation), and the
// restoreHighlightsOnLoad callback swap can lose concurrent highlight JS.
//
// These tests assert CORRECT behavior that the current code does NOT implement.
// They should FAIL until the bug is fixed.
//
// @coordinates-with: EPUBHighlightRenderer.swift, HighlightCoordinator.swift,
//   EPUBReaderContainerView+Highlights.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

// MARK: - Test Helpers

private let testFP77 = DocumentFingerprint(
    contentSHA256: "bug77_test_sha256_000000000000000000000000000000000000000",
    fileByteCount: 500,
    format: .epub
)

private func makeEPUBLocator() -> Locator {
    Locator(
        bookFingerprint: testFP77,
        href: "chapter1.xhtml", progression: 0.5, totalProgression: 0.1,
        cfi: "", page: nil, charOffsetUTF16: nil,
        charRangeStartUTF16: nil, charRangeEndUTF16: nil,
        textQuote: "test text", textContextBefore: nil, textContextAfter: nil
    )
}

private func makeEPUBRecord(id: UUID = UUID()) -> HighlightRecord {
    let range = EPUBSerializedRange(
        startContainerPath: "/html/body/p[1]/text()",
        startOffset: 0,
        endContainerPath: "/html/body/p[1]/text()",
        endOffset: 10
    )
    return HighlightRecord(
        highlightId: id,
        locator: makeEPUBLocator(),
        anchor: .epub(href: "chapter1.xhtml", cfi: "", serializedRange: range),
        profileKey: "epub:sha:500",
        selectedText: "test text",
        color: "yellow",
        note: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
}

@MainActor
private final class MockPersistence77: HighlightPersisting, @unchecked Sendable {
    var stubbedHighlights: [HighlightRecord] = []

    /// Bug #103 race test gate. When armed, `fetchHighlights` stores a
    /// continuation and signals `armed → true` so the test can wait
    /// for the suspension explicitly. Without the handshake, the test
    /// would race between "did restore reach the await?" and "did
    /// create+release run too early?" — Codex round 2 finding.
    private var pendingFetchGate: CheckedContinuation<Void, Never>?
    private var fetchGateRequested: Bool = false
    private var fetchIsPausedContinuation: CheckedContinuation<Void, Never>?
    private(set) var fetchIsPaused: Bool = false

    /// Arms the gate. Call BEFORE starting the Task that will hit
    /// `fetchHighlights`.
    func pauseFetchUntilReleased() {
        fetchGateRequested = true
    }

    /// Suspends until `fetchHighlights` has installed its continuation
    /// and is genuinely paused. Use after starting the restore Task
    /// and before triggering the concurrent action under test.
    func waitForFetchToBeArmed() async {
        guard !fetchIsPaused else { return }
        await withCheckedContinuation { cont in
            self.fetchIsPausedContinuation = cont
        }
    }

    /// Releases the gate. Resumes the suspended `fetchHighlights`.
    func releaseFetchGate() {
        if let cont = pendingFetchGate {
            pendingFetchGate = nil
            cont.resume()
        }
        fetchIsPaused = false
        fetchGateRequested = false
    }

    func addHighlight(
        locator: Locator, selectedText: String, color: String,
        note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        try await addHighlight(
            locator: locator, anchor: nil, selectedText: selectedText,
            color: color, note: note, toBookWithKey: key
        )
    }

    func addHighlight(
        locator: Locator, anchor: AnnotationAnchor?, selectedText: String,
        color: String, note: String?, toBookWithKey key: String
    ) async throws -> HighlightRecord {
        makeEPUBRecord()
    }

    func removeHighlight(highlightId: UUID) async throws {}
    func updateHighlightNote(highlightId: UUID, note: String?) async throws {}
    func updateHighlightColor(highlightId: UUID, color: String) async throws {}

    func fetchHighlights(forBookWithKey key: String) async throws -> [HighlightRecord] {
        if fetchGateRequested {
            await withCheckedContinuation { cont in
                self.pendingFetchGate = cont
                self.fetchIsPaused = true
                if let waiter = self.fetchIsPausedContinuation {
                    self.fetchIsPausedContinuation = nil
                    waiter.resume()
                }
            }
        }
        return stubbedHighlights
    }
}

// MARK: - Bug #77 Tests

@Suite("Bug #77 — EPUB Highlight Renderer")
@MainActor
struct EPUBHighlightRendererBug77Tests {

    // -----------------------------------------------------------------------
    // ROOT CAUSE TEST: onInjectJS nil → JS silently lost
    // -----------------------------------------------------------------------

    @Test("apply() should not silently lose JS when onInjectJS is nil")
    func applyWithNilCallback_shouldNotLoseJS() {
        let renderer = EPUBHighlightRenderer()
        // onInjectJS is nil (simulates race: .task hasn't set it yet)

        let record = makeEPUBRecord()
        renderer.apply(record: record)

        // After onInjectJS is set (simulating .task completing), the lost JS
        // should be delivered. We capture it to verify.
        var deliveredJS: [String] = []
        renderer.onInjectJS = { js in
            deliveredJS.append(js)
        }

        // BUG: The JS from the apply() call was lost. It was never queued.
        // Correct behavior: renderer should buffer pending JS and flush
        // when onInjectJS becomes available.
        #expect(!deliveredJS.isEmpty,
                "JS from apply() while onInjectJS was nil should be delivered when callback is set")
    }

    @Test("remove() should not silently lose JS when onInjectJS is nil")
    func removeWithNilCallback_shouldNotLoseJS() {
        let renderer = EPUBHighlightRenderer()
        // onInjectJS is nil

        renderer.remove(id: UUID())

        var deliveredJS: [String] = []
        renderer.onInjectJS = { js in
            deliveredJS.append(js)
        }

        // BUG: Same as apply — remove JS is lost when callback is nil
        #expect(!deliveredJS.isEmpty,
                "JS from remove() while onInjectJS was nil should be delivered when callback is set")
    }

    // -----------------------------------------------------------------------
    // RACE CONDITION: restoreHighlightsOnLoad callback swap
    // -----------------------------------------------------------------------

    @Test("highlight created during restore should be delivered to correct callback")
    func highlightDuringRestore_shouldNotBeMisdirected() async {
        // Bug #103 fix: restore now passes its evaluator via the
        // `using:` parameter on `restore(records:forHref:using:)`
        // instead of mutating `onInjectJS`. So a `create()` running
        // concurrently with `restoreAll(forHref:using:)` keeps using
        // `onInjectJS` (the normal callback) and lands at the right
        // destination — never on the temporary restore evaluator.
        //
        // To exercise the race deterministically, the persistence
        // mock blocks inside `fetchHighlights` until we release the
        // gate. We start `restoreAll(...)`, let it suspend on the
        // fetch, then run `create()` to completion — that's exactly
        // the timing window the pre-fix swap pattern lost the JS
        // through. Then we release the gate and assert both routing
        // directions.
        let renderer = EPUBHighlightRenderer()
        let persistence = MockPersistence77()
        persistence.stubbedHighlights = [makeEPUBRecord()]
        persistence.pauseFetchUntilReleased()

        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )

        @MainActor final class JSCollector { var values: [String] = [] }
        let normalCollector = JSCollector()
        let pageEvalCollector = JSCollector()

        renderer.onInjectJS = { js in normalCollector.values.append(js) }

        let pageEvaluator: @Sendable (String) -> Void = { js in
            MainActor.assumeIsolated { pageEvalCollector.values.append(js) }
        }

        // Start restore. It will suspend inside fetchHighlights waiting
        // for the gate. Use a Task (not async let) so we can start it,
        // wait for the explicit "fetch is paused" handshake, then run
        // create() to completion before releasing the gate.
        let restoreTask = Task {
            await coordinator.restoreAll(forHref: "chapter1.xhtml", using: pageEvaluator)
        }
        // Deterministic wait: returns only after fetchHighlights has
        // installed its continuation. No yield-loop guesswork.
        await persistence.waitForFetchToBeArmed()

        // Restore is now suspended at fetchHighlights. Create a
        // highlight — its JS must go through onInjectJS (the normal
        // callback), not the temporary pageEvaluator.
        let newRecord = await coordinator.create(
            locator: makeEPUBLocator(),
            selectedText: "new highlight"
        )

        // Release the gate; restore now resumes, fetches, and emits
        // its JS into the page evaluator.
        persistence.releaseFetchGate()
        await restoreTask.value

        #expect(newRecord != nil)
        // Bug #103 invariant: create's JS lands at the normal callback...
        #expect(!normalCollector.values.isEmpty,
                "create()'s JS must land at onInjectJS (the normal callback) — not the page evaluator")
        #expect(normalCollector.values.count == 1, "exactly one create JS")
        // ...and restore's JS lands at the page evaluator, never on the normal callback.
        #expect(!pageEvalCollector.values.isEmpty,
                "restore's JS must land at the page evaluator")
        // Strict separation: the two destinations don't share strings.
        let crosstalk = Set(normalCollector.values).intersection(Set(pageEvalCollector.values))
        #expect(crosstalk.isEmpty,
                "no JS string should appear in both callback destinations — got crosstalk: \(crosstalk)")
    }

    // -----------------------------------------------------------------------
    // COORDINATOR AVAILABILITY
    // -----------------------------------------------------------------------

    @Test("coordinator create + apply should deliver JS end-to-end")
    func coordinatorCreateDeliversJS() async {
        let renderer = EPUBHighlightRenderer()
        let persistence = MockPersistence77()
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: persistence,
            bookFingerprintKey: "test-book"
        )

        var deliveredJS: [String] = []
        renderer.onInjectJS = { js in deliveredJS.append(js) }

        let record = await coordinator.create(
            locator: makeEPUBLocator(),
            anchor: .epub(
                href: "chapter1.xhtml",
                cfi: "",
                serializedRange: EPUBSerializedRange(
                    startContainerPath: "/html/body/p[1]/text()",
                    startOffset: 0,
                    endContainerPath: "/html/body/p[1]/text()",
                    endOffset: 10
                )
            ),
            selectedText: "test text"
        )

        #expect(record != nil)
        // This should pass — verifies the happy path works
        #expect(!deliveredJS.isEmpty,
                "Coordinator create → renderer apply should deliver JS to callback")
    }
}
#endif
