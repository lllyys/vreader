// Purpose: Tests for TextReaderUIState (Phase R3 shared state).
// Validates protocol conformance, highlight refresh, pagination sync,
// and auto page turner lifecycle.
//
// @coordinates-with TextReaderUIState.swift, ReaderNotificationHandlers.swift

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import vreader

// MARK: - Helpers

private let testFP = DocumentFingerprint(
    contentSHA256: "uistate_test_sha256_00000000000000000000000000000000000000",
    fileByteCount: 200,
    format: .txt
)

private func makeLocator(
    charRangeStartUTF16: Int? = nil,
    charRangeEndUTF16: Int? = nil
) -> Locator {
    Locator(
        bookFingerprint: testFP,
        href: nil, progression: nil, totalProgression: nil, cfi: nil, page: nil,
        charOffsetUTF16: nil,
        charRangeStartUTF16: charRangeStartUTF16,
        charRangeEndUTF16: charRangeEndUTF16,
        textQuote: nil, textContextBefore: nil, textContextAfter: nil
    )
}

private func makeHighlightRecord(
    start: Int,
    end: Int,
    selectedText: String = "test",
    color: String = "yellow"
) -> HighlightRecord {
    HighlightRecord(
        highlightId: UUID(),
        locator: makeLocator(charRangeStartUTF16: start, charRangeEndUTF16: end),
        anchor: nil,
        profileKey: "test-key",
        selectedText: selectedText,
        color: color,
        note: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
}

// MARK: - Tests

@Suite("TextReaderUIState")
struct TextReaderUIStateTests {

    // MARK: - Protocol Conformance

    @Test @MainActor func conformsToReaderNotificationHandlerState() {
        let state = TextReaderUIState()

        // Verify all protocol properties are readable and writable
        state.scrollToOffset = 42
        state.highlightRange = NSRange(location: 0, length: 5)
        state.highlightIsTemporary = false
        state.persistedHighlightRanges = [
            PaintedHighlight(range: NSRange(location: 10, length: 3), colorName: "yellow")
        ]
        state.pendingAnnotationInfo = TextSelectionInfo(selectedText: "hi", startUTF16: 0, endUTF16: 2)
        state.annotationNoteText = "note"

        #expect(state.scrollToOffset == 42)
        #expect(state.highlightRange == NSRange(location: 0, length: 5))
        #expect(state.highlightIsTemporary == false)
        #expect(state.persistedHighlightRanges.count == 1)
        #expect(state.pendingAnnotationInfo?.selectedText == "hi")
        #expect(state.annotationNoteText == "note")
    }

    @Test @MainActor func canBeUsedAsProtocolWithHandlers() async {
        let state = TextReaderUIState()
        let deps = ReaderNotificationDeps(
            bookFingerprintKey: "test-key",
            bookFingerprint: testFP,
            bookmarkPersistence: NoOpBookmarkStore(),
            highlightPersistence: NoOpHighlightStore(),
            annotationPersistence: NoOpAnnotationStore(),
            locatorFactory: { fp, start, end, _ in
                Locator.validated(bookFingerprint: fp, charRangeStartUTF16: start, charRangeEndUTF16: end)
            },
            sourceText: { "Hello" },
            makeCurrentLocator: { makeLocator() },
            onNavigate: { _ in }
        )

        // Use TextReaderUIState directly where ReaderNotificationHandlerStateProtocol is expected
        let info = TextSelectionInfo(selectedText: "Hello", startUTF16: 0, endUTF16: 5)
        await ReaderNotificationHandlers.handleHighlightRequest(info: info, state: state, deps: deps)

        #expect(state.highlightIsTemporary == false)
        #expect(state.highlightRange == NSRange(location: 0, length: 5))
        #expect(state.persistedHighlightRanges.count == 1)
    }

    // MARK: - Highlight Refresh

    @Test @MainActor func refreshPersistedHighlightsMapsRecords() {
        let state = TextReaderUIState()
        let records = [
            makeHighlightRecord(start: 0, end: 10),
            makeHighlightRecord(start: 20, end: 30),
            makeHighlightRecord(start: 50, end: 80),
        ]

        state.refreshPersistedHighlights(from: records)

        #expect(state.persistedHighlightRanges.count == 3)
        #expect(state.persistedHighlightRanges[0].range == NSRange(location: 0, length: 10))
        #expect(state.persistedHighlightRanges[1].range == NSRange(location: 20, length: 10))
        #expect(state.persistedHighlightRanges[2].range == NSRange(location: 50, length: 30))
    }

    @Test @MainActor func refreshPersistedHighlightsPreservesRecordColor() {
        // Bug #208 / GH #776: each refreshed highlight must carry the
        // record's stored color through to the painter.
        let state = TextReaderUIState()
        let records = [
            makeHighlightRecord(start: 0, end: 10, color: "pink"),
            makeHighlightRecord(start: 20, end: 30, color: "green"),
        ]

        state.refreshPersistedHighlights(from: records)

        #expect(state.persistedHighlightRanges.count == 2)
        #expect(state.persistedHighlightRanges[0].colorName == "pink")
        #expect(state.persistedHighlightRanges[1].colorName == "green")
    }

    @Test @MainActor func refreshPersistedHighlightsFiltersInvalid() {
        let state = TextReaderUIState()
        let records = [
            makeHighlightRecord(start: 0, end: 10),    // valid
            makeHighlightRecord(start: 5, end: 5),     // zero-length — filtered
            makeHighlightRecord(start: 10, end: 5),    // end < start — filtered
        ]

        state.refreshPersistedHighlights(from: records)

        #expect(state.persistedHighlightRanges.count == 1)
        #expect(state.persistedHighlightRanges[0].range == NSRange(location: 0, length: 10))
    }

    @Test @MainActor func refreshPersistedHighlightsEmptyRecords() {
        let state = TextReaderUIState()
        state.persistedHighlightRanges = [
            PaintedHighlight(range: NSRange(location: 0, length: 5), colorName: "yellow")
        ]

        state.refreshPersistedHighlights(from: [])

        #expect(state.persistedHighlightRanges.isEmpty)
    }

    @Test @MainActor func refreshPersistedHighlightsFiltersNilLocatorFields() {
        let state = TextReaderUIState()
        // Record with nil range fields
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makeLocator(), // no range fields
            anchor: nil,
            profileKey: "test-key",
            selectedText: "test",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        state.refreshPersistedHighlights(from: [record])

        #expect(state.persistedHighlightRanges.isEmpty)
    }

    // MARK: - Sync Paged State

    @Test @MainActor func syncPagedStateReturnsNilWhenNoNavigator() {
        let state = TextReaderUIState()

        let offset = state.syncPagedState()

        #expect(offset == nil)
        #expect(state.pagedCurrentPage == 0)
    }

    // MARK: - Update Pagination

    @Test @MainActor func updatePaginationTearsDownWhenNotPagedMode() {
        let state = TextReaderUIState()
        // Simulate existing pagination state
        state.pageNavigator = NativeTextPageNavigator()

        state.updatePagination(
            isPagedMode: false,
            attributedText: NSAttributedString(string: "Hello"),
            initialRestoreOffset: nil,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 5.0
        )

        #expect(state.pageNavigator == nil)
    }

    @Test @MainActor func updatePaginationPreservesNavigatorWhenNilText() {
        let state = TextReaderUIState()
        state.pageNavigator = NativeTextPageNavigator()

        // Bug #82: isPagedMode=true with nil attributedText should PRESERVE navigator
        // (attr string rebuild not ready yet). Only isPagedMode=false destroys it.
        state.updatePagination(
            isPagedMode: true,
            attributedText: nil,
            initialRestoreOffset: nil,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 5.0
        )

        #expect(state.pageNavigator != nil,
                "Bug #82: navigator preserved when attrText nil but paged mode on")
    }

    // Bug #215: `updatePagination` previously hardcoded
    // `viewportSize: UIScreen.main.bounds.size` — full screen, ignoring the
    // chrome-aware inset that `pagedReaderContent` actually renders into.
    // Pages were mis-sized: each page tried to lay out a screen's worth of
    // text into a smaller `NativeTextPagedView` box, and the layout-manager
    // truncated the page text at the renderer (visible as "clipped mid-
    // line" in the original repro). The fix exposes an explicit
    // `viewportSize:` parameter; callers (MD container) pass the measured
    // `NativeTextPagedView` box via `GeometryReader`.
    //
    // These tests assert the parameter actually feeds the paginator —
    // smaller viewport → more pages, larger viewport → fewer pages.
    @Test @MainActor func updatePaginationHonorsExplicitViewportSize_smallerYieldsMorePages() {
        // A text long enough to span multiple pages at any reasonable
        // viewport, so the *delta* between two viewports is the assertion
        // (not "any" page count, which would be timing/font-fragile).
        let paragraphs = Array(repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit.", count: 40).joined(separator: "\n\n")
        let attr = NSAttributedString(
            string: paragraphs,
            attributes: [.font: UIFont.systemFont(ofSize: 18)]
        )
        let state = TextReaderUIState()

        state.updatePagination(
            isPagedMode: true,
            attributedText: attr,
            initialRestoreOffset: nil,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 5.0,
            viewportSize: CGSize(width: 400, height: 800)
        )
        let pagesLarge = state.pageNavigator?.totalPages ?? 0

        // Force a fresh navigator so the per-call paginate runs cleanly
        // (the production code reuses the navigator across re-paginate
        // events; both calls must observe the parameter, so use the same
        // state instance and a smaller viewport.)
        state.updatePagination(
            isPagedMode: true,
            attributedText: attr,
            initialRestoreOffset: nil,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 5.0,
            viewportSize: CGSize(width: 400, height: 200)
        )
        let pagesSmall = state.pageNavigator?.totalPages ?? 0

        #expect(pagesLarge >= 1)
        #expect(pagesSmall > pagesLarge,
                "smaller viewport should paginate to MORE pages, got large=\(pagesLarge) small=\(pagesSmall)")
    }

    @Test @MainActor func updatePaginationDefaultsToMainScreenWhenViewportNotSupplied() {
        // Backward compat — TXT and any caller that hasn't been
        // updated to thread a measured viewport gets the legacy default
        // (`UIScreen.main.bounds.size`). The default exists so this isn't
        // a breaking API change.
        let attr = NSAttributedString(
            string: "One paragraph.",
            attributes: [.font: UIFont.systemFont(ofSize: 18)]
        )
        let state = TextReaderUIState()

        state.updatePagination(
            isPagedMode: true,
            attributedText: attr,
            initialRestoreOffset: nil,
            autoPageTurnEnabled: false,
            autoPageTurnInterval: 5.0
        )

        // A very short text fits in 1 page at the iPhone 17 Pro default
        // viewport. The point is just that the call SUCCEEDED without an
        // explicit viewport (no compile error, no crash).
        #expect(state.pageNavigator?.totalPages == 1)
    }

    // MARK: - Auto Page Turner

    @Test @MainActor func updateAutoPageTurnerStopsWhenDisabled() {
        let state = TextReaderUIState()
        let turner = AutoPageTurner()
        state.autoPageTurner = turner

        state.updateAutoPageTurner(enabled: false, isPagedMode: true, interval: 5.0)

        #expect(turner.state == .idle)
    }

    @Test @MainActor func updateAutoPageTurnerStopsWhenNotPagedMode() {
        let state = TextReaderUIState()
        let turner = AutoPageTurner()
        state.autoPageTurner = turner

        state.updateAutoPageTurner(enabled: true, isPagedMode: false, interval: 5.0)

        #expect(turner.state == .idle)
    }

    @Test @MainActor func updateAutoPageTurnerStopsWhenNoNavigator() {
        let state = TextReaderUIState()

        state.updateAutoPageTurner(enabled: true, isPagedMode: true, interval: 5.0)

        // No crash, auto page turner remains nil
        #expect(state.autoPageTurner == nil)
    }

    // MARK: - Default Values

    @Test @MainActor func defaultValuesAreCorrect() {
        let state = TextReaderUIState()

        #expect(state.scrollToOffset == nil)
        #expect(state.highlightRange == nil)
        #expect(state.highlightIsTemporary == true)
        #expect(state.persistedHighlightRanges.isEmpty)
        #expect(state.pendingAnnotationInfo == nil)
        #expect(state.annotationNoteText == "")
        #expect(state.readingProgress == 0)
        #expect(state.pageNavigator == nil)
        #expect(state.pagedCurrentPage == 0)
        #expect(state.autoPageTurner == nil)
    }
}
