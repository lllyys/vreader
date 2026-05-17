// Purpose: Tests for TextReaderUIState (Phase R3 shared state).
// Validates protocol conformance, highlight refresh, pagination sync,
// and auto page turner lifecycle.
//
// @coordinates-with TextReaderUIState.swift, ReaderNotificationHandlers.swift

import Testing
import Foundation
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
