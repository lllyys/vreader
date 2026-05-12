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

private enum HandlerTestError: Error { case persistence }

/// Concrete state carrier for tests.
@MainActor
private final class TestHandlerState: ReaderNotificationHandlerStateProtocol {
    var scrollToOffset: Int?
    var highlightRange: NSRange?
    var highlightIsTemporary: Bool = true
    var persistedHighlightRanges: [NSRange] = []
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
        #expect(state.persistedHighlightRanges.first == NSRange(location: 0, length: 5))
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

    // MARK: - AddNoteSheet Save

    @Test @MainActor func handleAnnotationSaveTrimsAndPersists() async {
        let annotations = MockAnnotationStore()
        let deps = makeDeps(annotations: annotations)
        let state = TestHandlerState()
        state.pendingAnnotationInfo = TextSelectionInfo(selectedText: "Hello", startUTF16: 0, endUTF16: 5)
        state.annotationNoteText = "  My note  "

        await ReaderNotificationHandlers.handleAnnotationSave(state: state, deps: deps)

        #expect(state.pendingAnnotationInfo == nil)
        let count = await annotations.addCallCount
        #expect(count == 1)
    }

    @Test @MainActor func handleAnnotationSaveEmptyTextNoPersistence() async {
        let annotations = MockAnnotationStore()
        let deps = makeDeps(annotations: annotations)
        let state = TestHandlerState()
        state.pendingAnnotationInfo = TextSelectionInfo(selectedText: "Hello", startUTF16: 0, endUTF16: 5)
        state.annotationNoteText = "   "

        await ReaderNotificationHandlers.handleAnnotationSave(state: state, deps: deps)

        #expect(state.pendingAnnotationInfo == nil)
        let count = await annotations.addCallCount
        #expect(count == 0)
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
