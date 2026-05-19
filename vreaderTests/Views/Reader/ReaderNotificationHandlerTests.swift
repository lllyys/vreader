// Purpose: Tests for ReaderNotificationHandler functions extracted in WI-003.
// Validates bookmark, navigation, highlight, annotation, and AddNoteSheet flows
// against mock state and mock persistence.
//
// @coordinates-with ReaderNotificationHandlers.swift, ReaderNotificationModifier.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Test Helpers

private let testFP = DocumentFingerprint(
    contentSHA256: "handler_test_sha256_000000000000000000000000000000000000000",
    fileByteCount: 100,
    format: .txt
)

private func makeLocator(
    charOffsetUTF16: Int? = nil,
    charRangeStartUTF16: Int? = nil,
    charRangeEndUTF16: Int? = nil
) -> Locator {
    Locator(
        bookFingerprint: testFP,
        href: nil, progression: nil, totalProgression: nil, cfi: nil, page: nil,
        charOffsetUTF16: charOffsetUTF16,
        charRangeStartUTF16: charRangeStartUTF16,
        charRangeEndUTF16: charRangeEndUTF16,
        textQuote: nil, textContextBefore: nil, textContextAfter: nil
    )
}

/// Mock haptic provider that records triggerLightImpact calls.
@MainActor
private final class MockHapticFeedbackProvider: HapticFeedbackProviding {
    private(set) var triggerCount = 0
    func triggerLightImpact() { triggerCount += 1 }
}

/// Capturing `HighlightRenderer` mock — records `apply` calls so tests can
/// assert what the coordinator forwarded to rendering. Used by the bug #181
/// regression suite below; kept private here because the public
/// `HighlightCoordinatorTests` file has its own equivalent mock.
@MainActor
private final class CapturingHighlightRenderer: HighlightRenderer {
    var appliedRecords: [HighlightRecord] = []
    func apply(record: HighlightRecord) { appliedRecords.append(record) }
    func remove(id: UUID) {}
    func restore(
        records: [HighlightRecord],
        forHref href: String?,
        using evaluator: ((String) -> Void)?
    ) {}
}

private enum HandlerTestError: Error { case persistence }

/// Concrete state carrier for tests.
@MainActor
private final class TestHandlerState: ReaderNotificationHandlerStateProtocol {
    var scrollToOffset: Int?
    var highlightRange: NSRange?
    var highlightIsTemporary: Bool = true
    var highlightNonce: Int = 0
    var persistedHighlightRanges: [PaintedHighlight] = []
    var pendingAnnotationInfo: TextSelectionInfo?
    var annotationNoteText: String = ""
}

@MainActor
private func makeDeps(
    bookmarks: MockBookmarkStore = MockBookmarkStore(),
    highlights: MockHighlightStore = MockHighlightStore(),
    annotations: MockAnnotationStore = MockAnnotationStore(),
    locatorFactory: @Sendable @escaping (DocumentFingerprint, Int, Int, String?) -> Locator? = { fp, start, end, _ in
        Locator.validated(bookFingerprint: fp, charRangeStartUTF16: start, charRangeEndUTF16: end)
    },
    sourceText: @MainActor @escaping () -> String? = { "Hello World" },
    makeCurrentLocator: @MainActor @escaping () -> Locator = { makeLocator() },
    onNavigate: @MainActor @escaping (Int) -> Void = { _ in },
    hapticFeedback: (any HapticFeedbackProviding)? = nil
) -> ReaderNotificationDeps {
    ReaderNotificationDeps(
        bookFingerprintKey: "test-key",
        bookFingerprint: testFP,
        bookmarkPersistence: bookmarks,
        highlightPersistence: highlights,
        annotationPersistence: annotations,
        locatorFactory: locatorFactory,
        sourceText: sourceText,
        makeCurrentLocator: makeCurrentLocator,
        onNavigate: onNavigate,
        hapticFeedback: hapticFeedback
    )
}

// MARK: - Tests

@Suite("ReaderNotificationHandlers")
struct ReaderNotificationHandlerTests {

    // MARK: - Bookmark

    @Test @MainActor func handleBookmarkRequestCallsPersistence() async {
        let bookmarks = MockBookmarkStore()
        let deps = makeDeps(bookmarks: bookmarks)

        await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)

        let count = await bookmarks.addCallCount
        #expect(count == 1)
    }

    @Test @MainActor func handleBookmarkRequest_firesHaptic_onSuccess() async {
        let haptic = MockHapticFeedbackProvider()
        let deps = makeDeps(hapticFeedback: haptic)
        await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)
        #expect(haptic.triggerCount == 1, "haptic must fire once on successful bookmark add")
    }

    @Test @MainActor func handleBookmarkRequest_suppressesHaptic_onPersistenceFailure() async {
        let haptic = MockHapticFeedbackProvider()
        let bookmarks = MockBookmarkStore()
        await bookmarks.setAddError(HandlerTestError.persistence)
        let deps = makeDeps(bookmarks: bookmarks, hapticFeedback: haptic)
        await ReaderNotificationHandlers.handleBookmarkRequest(deps: deps)
        #expect(haptic.triggerCount == 0, "haptic must not fire when bookmark persistence throws")
    }

    // MARK: - Navigate

    @Test @MainActor func handleNavigateToLocatorSetsScrollOffset() {
        let state = TestHandlerState()
        var navigatedOffset: Int?
        let deps = makeDeps(onNavigate: { navigatedOffset = $0 })

        let locator = makeLocator(charOffsetUTF16: 500, charRangeStartUTF16: 500, charRangeEndUTF16: 510)
        ReaderNotificationHandlers.handleNavigateToLocator(locator: locator, state: state, deps: deps)

        #expect(state.scrollToOffset == 500)
        #expect(state.highlightIsTemporary == true)
        #expect(state.highlightRange == NSRange(location: 500, length: 10))
        #expect(navigatedOffset == 500)
    }

    @Test @MainActor func handleNavigateToLocatorFallsBackToCharRangeStart() {
        let state = TestHandlerState()
        let deps = makeDeps()

        let locator = makeLocator(charRangeStartUTF16: 200, charRangeEndUTF16: 210)
        ReaderNotificationHandlers.handleNavigateToLocator(locator: locator, state: state, deps: deps)

        #expect(state.scrollToOffset == 200)
    }

    @Test @MainActor func handleNavigateToLocatorNilOffsetsIsNoOp() {
        let state = TestHandlerState()
        let deps = makeDeps()

        let locator = makeLocator()
        ReaderNotificationHandlers.handleNavigateToLocator(locator: locator, state: state, deps: deps)

        #expect(state.scrollToOffset == nil)
    }

    // MARK: - Navigate Nonce (Bug #154 / GH #443)

    /// A single navigate event bumps `highlightNonce` exactly once.
    @Test @MainActor func handleNavigateToLocatorBumpsNonce() {
        let state = TestHandlerState()
        let deps = makeDeps()
        #expect(state.highlightNonce == 0)

        let locator = makeLocator(charOffsetUTF16: 500, charRangeStartUTF16: 500, charRangeEndUTF16: 510)
        ReaderNotificationHandlers.handleNavigateToLocator(locator: locator, state: state, deps: deps)

        #expect(state.highlightNonce == 1)
    }

    /// THE BUG #154 REGRESSION GUARD. Two consecutive navigate events to the
    /// SAME locator — the search-tap-while-already-there case. `scrollToOffset`
    /// and `highlightRange` are re-set to values they already hold (an
    /// `@Observable` no-op write that never re-evaluates the SwiftUI body), so
    /// the temporary highlight was never re-painted. The nonce MUST change on
    /// the repeat-nav so the body re-evaluates and the bridge re-paints.
    @Test @MainActor func handleNavigateToLocatorBumpsNonceOnRepeatNavToSameTarget() {
        let state = TestHandlerState()
        let deps = makeDeps()
        let locator = makeLocator(charOffsetUTF16: 8847, charRangeStartUTF16: 8847, charRangeEndUTF16: 8859)

        // First navigate — establishes scrollToOffset / highlightRange.
        ReaderNotificationHandlers.handleNavigateToLocator(locator: locator, state: state, deps: deps)
        let firstNonce = state.highlightNonce
        let firstRange = state.highlightRange

        // Second navigate to the EXACT same locator. scrollToOffset and
        // highlightRange are unchanged — but the nonce must still advance.
        ReaderNotificationHandlers.handleNavigateToLocator(locator: locator, state: state, deps: deps)

        #expect(state.highlightRange == firstRange,
                "range is unchanged on a repeat-nav to the same target — that is exactly the no-op-write the bug exploited")
        #expect(state.highlightNonce > firstNonce,
                "highlightNonce MUST advance on every navigate event so a repeat-nav to an already-current target still re-paints the temporary highlight (bug #154 / GH #443)")
    }

    /// Even a navigate event with nil offsets — an early-return no-op for
    /// scroll/highlight state — leaves the nonce untouched. The nonce only
    /// advances when an actual navigation is performed, so it never fires a
    /// spurious bridge re-paint for an ignored event.
    @Test @MainActor func handleNavigateToLocatorNilOffsetsDoesNotBumpNonce() {
        let state = TestHandlerState()
        let deps = makeDeps()

        ReaderNotificationHandlers.handleNavigateToLocator(locator: makeLocator(), state: state, deps: deps)

        #expect(state.highlightNonce == 0)
    }

    // MARK: - Highlight

    @Test @MainActor func handleHighlightRequestAppliesRangeAndPersists() async {
        let highlights = MockHighlightStore()
        let deps = makeDeps(highlights: highlights)
        let state = TestHandlerState()

        let info = TextSelectionInfo(selectedText: "Hello", startUTF16: 0, endUTF16: 5)
        await ReaderNotificationHandlers.handleHighlightRequest(info: info, state: state, deps: deps)

        #expect(state.highlightIsTemporary == false)
        #expect(state.highlightRange == NSRange(location: 0, length: 5))
        #expect(state.persistedHighlightRanges.count == 1)
        #expect(state.persistedHighlightRanges.first?.range == NSRange(location: 0, length: 5))
        let count = await highlights.addCallCount
        #expect(count == 1)
    }

    @Test @MainActor func handleHighlightRequestEmptySelectionIsNoOp() async {
        let highlights = MockHighlightStore()
        let deps = makeDeps(highlights: highlights, locatorFactory: { _, _, _, _ in nil })
        let state = TestHandlerState()

        let info = TextSelectionInfo(selectedText: "", startUTF16: 0, endUTF16: 0)
        await ReaderNotificationHandlers.handleHighlightRequest(info: info, state: state, deps: deps)

        #expect(state.persistedHighlightRanges.isEmpty)
        let count = await highlights.addCallCount
        #expect(count == 0)
    }

    // MARK: - Annotation Request

    @Test @MainActor func handleAnnotationRequestSetsPendingInfo() {
        let state = TestHandlerState()
        let info = TextSelectionInfo(selectedText: "World", startUTF16: 6, endUTF16: 11)

        ReaderNotificationHandlers.handleAnnotationRequest(info: info, state: state)

        #expect(state.pendingAnnotationInfo?.selectedText == "World")
        #expect(state.annotationNoteText == "")
    }

    // MARK: - AddNoteSheet Save (Bug #188 fix: explicit-arg handler)

    /// Helper: build a real `HighlightCoordinator` backed by a fresh
    /// `MockHighlightStore` + capturing renderer. Returns both so the
    /// test can assert against them.
    @MainActor
    private func makeCoordinatorWithCaptures(
        bookFingerprintKey: String = "test-key"
    ) -> (HighlightCoordinator, CapturingHighlightRenderer, MockHighlightStore) {
        let renderer = CapturingHighlightRenderer()
        let store = MockHighlightStore()
        let coordinator = HighlightCoordinator(
            renderer: renderer,
            persistence: store,
            bookFingerprintKey: bookFingerprintKey
        )
        return (coordinator, renderer, store)
    }

    /// Helper: a valid locator for the in-range "Hello" selection in
    /// the test source text "Hello World".
    private func makeHelloLocator() -> Locator {
        Locator.validated(bookFingerprint: testFP, charRangeStartUTF16: 0, charRangeEndUTF16: 5)!
    }

    // MARK: - prepareAnnotationSave (Bug #188 fix: capture-before-dismiss contract)

    /// `prepareAnnotationSave` is the synchronous half of the fix. It
    /// validates state, captures `info` / `trimmed` / `locator` into a
    /// returnable `AnnotationSaveRequest`, AND clears
    /// `pendingAnnotationInfo` — all in one sync pass — so the
    /// AddNoteSheet's `dismiss()` can't race the captured values.
    @Test @MainActor func prepareAnnotationSave_validInput_returnsRequestAndClearsPending() {
        let deps = makeDeps()
        let state = TestHandlerState()
        state.pendingAnnotationInfo = TextSelectionInfo(selectedText: "Hello", startUTF16: 0, endUTF16: 5)
        state.annotationNoteText = "  remember  "

        let request = ReaderNotificationHandlers.prepareAnnotationSave(state: state, deps: deps)

        #expect(request != nil)
        #expect(request?.info.selectedText == "Hello")
        #expect(request?.trimmed == "remember", "trimmed must strip surrounding whitespace")
        #expect(request?.locator.charRangeStartUTF16 == 0)
        #expect(request?.locator.charRangeEndUTF16 == 5)
        // Crucial Bug #188 contract: the sync clear happens INSIDE
        // prepare so a follow-up dismiss() can't re-clear-as-no-op a
        // value that's already gone.
        #expect(state.pendingAnnotationInfo == nil)
    }

    @Test @MainActor func prepareAnnotationSave_nilPendingInfo_returnsNil() {
        let deps = makeDeps()
        let state = TestHandlerState()
        // pendingAnnotationInfo intentionally nil
        state.annotationNoteText = "some note"

        let request = ReaderNotificationHandlers.prepareAnnotationSave(state: state, deps: deps)

        #expect(request == nil)
        #expect(state.pendingAnnotationInfo == nil)
    }

    @Test @MainActor func prepareAnnotationSave_emptyTrimmed_returnsNilAndClears() {
        let deps = makeDeps()
        let state = TestHandlerState()
        state.pendingAnnotationInfo = TextSelectionInfo(selectedText: "Hello", startUTF16: 0, endUTF16: 5)
        state.annotationNoteText = "   \n\t  "

        let request = ReaderNotificationHandlers.prepareAnnotationSave(state: state, deps: deps)

        #expect(request == nil, "whitespace-only note text must short-circuit prepare")
        #expect(state.pendingAnnotationInfo == nil, "pending info must be cleared so the sheet dismisses")
    }

    @Test @MainActor func prepareAnnotationSave_locatorFactoryFailure_returnsNilAndClears() {
        let deps = makeDeps(locatorFactory: { _, _, _, _ in nil })
        let state = TestHandlerState()
        state.pendingAnnotationInfo = TextSelectionInfo(selectedText: "Hello", startUTF16: 0, endUTF16: 5)
        state.annotationNoteText = "note"

        let request = ReaderNotificationHandlers.prepareAnnotationSave(state: state, deps: deps)

        #expect(request == nil)
        #expect(state.pendingAnnotationInfo == nil)
    }

    /// Bug #188 production-sequence regression test: simulates the
    /// modifier-side flow that broke at v3.21.53. After
    /// `prepareAnnotationSave` returns the captured `request`, the test
    /// THEN clears `pendingAnnotationInfo` again (mirroring a hypothetical
    /// future regression that moves state reads back into the Task) AND
    /// also runs the handler — confirming the handler still persists
    /// both records using only the captured request.
    @Test @MainActor func prepareAndHandleAnnotationSave_isImmuneToPostPrepareStateMutation_bug188() async {
        let annotations = MockAnnotationStore()
        let deps = makeDeps(annotations: annotations)
        let state = TestHandlerState()
        state.pendingAnnotationInfo = TextSelectionInfo(selectedText: "Hello", startUTF16: 0, endUTF16: 5)
        state.annotationNoteText = "captured note"
        let (coordinator, renderer, store) = makeCoordinatorWithCaptures()

        // Modifier-side sync portion.
        guard let request = ReaderNotificationHandlers.prepareAnnotationSave(state: state, deps: deps) else {
            Issue.record("prepare returned nil unexpectedly")
            return
        }

        // Simulate AddNoteSheet's dismiss() running between sync portion
        // and Task body — for the bug #188 contract this MUST be a no-op
        // on the production-path captured values.
        state.pendingAnnotationInfo = nil
        state.annotationNoteText = ""

        // Task-spawn-equivalent: handler reads only the request, not state.
        await ReaderNotificationHandlers.handleAnnotationSave(
            info: request.info,
            trimmed: request.trimmed,
            locator: request.locator,
            deps: deps,
            highlightCoordinator: coordinator
        )

        let annoCount = await annotations.addCallCount
        #expect(annoCount == 1, "AnnotationRecord must persist even after a post-prepare state wipe (bug #188 contract)")
        let storeAddCount = await store.addCallCount
        #expect(storeAddCount == 1, "HighlightRecord must persist even after a post-prepare state wipe")
        #expect(renderer.appliedRecords.count == 1)
        #expect(renderer.appliedRecords.first?.selectedText == "Hello")
        #expect(renderer.appliedRecords.first?.note == "captured note")
    }

    @Test @MainActor func handleAnnotationSave_persistsBoth_withCapturedArgs() async {
        let annotations = MockAnnotationStore()
        let deps = makeDeps(annotations: annotations)
        let (coordinator, renderer, store) = makeCoordinatorWithCaptures()
        let info = TextSelectionInfo(selectedText: "Hello", startUTF16: 0, endUTF16: 5)

        await ReaderNotificationHandlers.handleAnnotationSave(
            info: info,
            trimmed: "My note",
            locator: makeHelloLocator(),
            deps: deps,
            highlightCoordinator: coordinator
        )

        let annoCount = await annotations.addCallCount
        #expect(annoCount == 1)
        let storeAddCount = await store.addCallCount
        #expect(storeAddCount == 1)
        #expect(renderer.appliedRecords.count == 1)
        let applied = renderer.appliedRecords.first
        #expect(applied?.selectedText == "Hello")
        #expect(applied?.color == "yellow")
        #expect(applied?.note == "My note")
    }

    /// Bug #188 regression test: the production path captures values
    /// by VALUE before spawning the Task. By the time the handler runs
    /// the surrounding `pendingAnnotationInfo` may have been cleared by
    /// AddNoteSheet's `dismiss()` — the handler must not depend on it.
    /// This test pins the contract by mutating the state class AFTER
    /// the captured args were taken and confirming the handler still
    /// persists both records using only the args.
    @Test @MainActor func handleAnnotationSave_immuneToPostCaptureStateMutation_bug188() async {
        let annotations = MockAnnotationStore()
        let deps = makeDeps(annotations: annotations)
        let (coordinator, renderer, store) = makeCoordinatorWithCaptures()
        // Mirror the production sequence: caller captures info / trimmed
        // / locator into the Task closure, then SwiftUI's dismiss() clears
        // the underlying state class (or in this test, we never wire one).
        let info = TextSelectionInfo(selectedText: "Hello", startUTF16: 0, endUTF16: 5)
        let trimmed = "remember this"
        let locator = makeHelloLocator()
        // Simulate "dismiss already ran" — state class is intentionally
        // not threaded through the handler at all in the bug #188 fix.

        await ReaderNotificationHandlers.handleAnnotationSave(
            info: info,
            trimmed: trimmed,
            locator: locator,
            deps: deps,
            highlightCoordinator: coordinator
        )

        // Both writes must succeed even though the surrounding state
        // class (TextReaderUIState in production) is irrelevant to the
        // handler. Pre-bug-188 the handler would have read from `state`
        // and bailed on nil pendingAnnotationInfo — neither write ran.
        let annoCount = await annotations.addCallCount
        #expect(annoCount == 1, "AnnotationRecord must persist regardless of view state — handler must use captured args only")
        let storeAddCount = await store.addCallCount
        #expect(storeAddCount == 1, "HighlightRecord must persist regardless of view state")
        #expect(renderer.appliedRecords.count == 1)
    }

    /// Atomicity check (Bug #181's Codex round-1 High, preserved across
    /// the Bug #188 refactor): if `addAnnotation` throws, the highlight
    /// MUST NOT be created. Both writes succeed or neither — the Notes
    /// and Highlights tabs never diverge.
    @Test @MainActor func handleAnnotationSave_annotationPersistenceFails_skipsHighlight() async {
        let annotations = MockAnnotationStore()
        await annotations.setAddError(HandlerTestError.persistence)
        let deps = makeDeps(annotations: annotations)
        let (coordinator, renderer, store) = makeCoordinatorWithCaptures()

        await ReaderNotificationHandlers.handleAnnotationSave(
            info: TextSelectionInfo(selectedText: "Hello", startUTF16: 0, endUTF16: 5),
            trimmed: "note",
            locator: makeHelloLocator(),
            deps: deps,
            highlightCoordinator: coordinator
        )

        let storeAddCount = await store.addCallCount
        #expect(storeAddCount == 0, "highlight create must be skipped when annotation persistence fails")
        #expect(renderer.appliedRecords.isEmpty)
    }

    // MARK: - AddNoteSheet Cancel

    @Test @MainActor func handleAnnotationCancelClearsState() {
        let state = TestHandlerState()
        state.pendingAnnotationInfo = TextSelectionInfo(selectedText: "X", startUTF16: 0, endUTF16: 1)
        state.annotationNoteText = "draft"

        ReaderNotificationHandlers.handleAnnotationCancel(state: state)

        #expect(state.pendingAnnotationInfo == nil)
    }
}
