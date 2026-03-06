// Purpose: Tests for HighlightListViewModel — load, add, remove, edit, overlap, edge cases.
//
// @coordinates-with: HighlightListViewModel.swift, MockHighlightStore.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Loading

@Suite("HighlightListViewModel - Loading")
@MainActor
struct HighlightListViewModelLoadingTests {

    @Test("loads highlights for a book")
    func loadHighlightsPopulatesList() async {
        let store = MockHighlightStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        let record = makeHighlightRecord(selectedText: "Hello world")
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: 1000
        )
        await vm.loadHighlights()

        #expect(vm.highlights.count == 1)
        #expect(vm.highlights.first?.selectedText == "Hello world")
    }

    @Test("empty list shows empty state")
    func emptyHighlightList() async {
        let store = MockHighlightStore()
        let vm = HighlightListViewModel(
            bookFingerprintKey: wi9TXTFingerprint.canonicalKey,
            store: store,
            totalTextLengthUTF16: 1000
        )
        await vm.loadHighlights()

        #expect(vm.highlights.isEmpty)
        #expect(vm.isEmpty)
    }

    @Test("load error sets error message")
    func loadErrorSetsMessage() async {
        let store = MockHighlightStore()
        await store.setFetchError(WI9TestError.mockFailure)

        let vm = HighlightListViewModel(
            bookFingerprintKey: wi9TXTFingerprint.canonicalKey,
            store: store,
            totalTextLengthUTF16: 1000
        )
        await vm.loadHighlights()

        #expect(vm.highlights.isEmpty)
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - Add / Remove

@Suite("HighlightListViewModel - Add/Remove")
@MainActor
struct HighlightListViewModelMutationTests {

    @Test("add highlight appends to list")
    func addHighlight() async {
        let store = MockHighlightStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        let locator = makeTXTRangeLocator(start: 0, end: 20)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: 1000
        )
        await vm.addHighlight(
            locator: locator,
            selectedText: "selected text",
            color: "yellow",
            note: nil
        )

        #expect(vm.highlights.count == 1)
        #expect(vm.highlights.first?.color == "yellow")
    }

    @Test("remove highlight removes from list")
    func removeHighlight() async {
        let store = MockHighlightStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        let record = makeHighlightRecord()
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: 1000
        )
        await vm.loadHighlights()
        #expect(vm.highlights.count == 1)

        await vm.removeHighlight(highlightId: record.highlightId)

        #expect(vm.highlights.isEmpty)
    }
}

// MARK: - Edit Note/Color

@Suite("HighlightListViewModel - Edit")
@MainActor
struct HighlightListViewModelEditTests {

    @Test("update note on highlight")
    func updateNote() async {
        let store = MockHighlightStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        let record = makeHighlightRecord()
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: 1000
        )
        await vm.loadHighlights()

        await vm.updateNote(highlightId: record.highlightId, note: "My note")

        #expect(vm.highlights.first?.note == "My note")
    }

    @Test("update color on highlight")
    func updateColor() async {
        let store = MockHighlightStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        let record = makeHighlightRecord(color: "yellow")
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: 1000
        )
        await vm.loadHighlights()

        await vm.updateColor(highlightId: record.highlightId, color: "blue")

        #expect(vm.highlights.first?.color == "blue")
    }
}

// MARK: - Out-of-bounds Detection

@Suite("HighlightListViewModel - Out of Bounds")
@MainActor
struct HighlightListViewModelOutOfBoundsTests {

    @Test("detects out-of-bounds highlight range")
    func outOfBoundsDetection() async {
        let store = MockHighlightStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        // Highlight range end (50) > totalTextLengthUTF16 (30)
        let record = makeHighlightRecord(
            locator: makeTXTRangeLocator(start: 10, end: 50)
        )
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: 30
        )
        await vm.loadHighlights()

        #expect(vm.hasOutOfBoundsHighlights)
        #expect(vm.outOfBoundsHighlightIds.contains(record.highlightId))
    }

    @Test("in-bounds highlight not flagged")
    func inBoundsNotFlagged() async {
        let store = MockHighlightStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        let record = makeHighlightRecord(
            locator: makeTXTRangeLocator(start: 0, end: 20)
        )
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: 1000
        )
        await vm.loadHighlights()

        #expect(!vm.hasOutOfBoundsHighlights)
        #expect(vm.outOfBoundsHighlightIds.isEmpty)
    }

    @Test("nil totalTextLengthUTF16 skips out-of-bounds check")
    func nilTotalSkipsCheck() async {
        let store = MockHighlightStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        let record = makeHighlightRecord(
            locator: makeTXTRangeLocator(start: 10, end: 50)
        )
        await store.seed(record, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: nil
        )
        await vm.loadHighlights()

        #expect(!vm.hasOutOfBoundsHighlights)
    }
}

// MARK: - Overlap Ordering

@Suite("HighlightListViewModel - Overlap")
@MainActor
struct HighlightListViewModelOverlapTests {

    @Test("newest-first render order for overlapping highlights")
    func newestFirstOrder() async {
        let store = MockHighlightStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        let now = Date()

        let older = makeHighlightRecord(
            locator: makeTXTRangeLocator(start: 0, end: 20),
            selectedText: "older",
            createdAt: now.addingTimeInterval(-100)
        )
        let newer = makeHighlightRecord(
            locator: makeTXTRangeLocator(start: 5, end: 25),
            selectedText: "newer",
            createdAt: now
        )

        await store.seed(older, forBookWithKey: bookKey)
        await store.seed(newer, forBookWithKey: bookKey)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: 1000
        )
        await vm.loadHighlights()

        #expect(vm.highlights.count == 2)
        #expect(vm.highlights.first?.selectedText == "newer")
    }
}

// MARK: - TXT UTF-16 Range

@Suite("HighlightListViewModel - TXT UTF-16")
@MainActor
struct HighlightListViewModelTXTTests {

    @Test("TXT highlight preserves UTF-16 range fields")
    func txtHighlightRange() async {
        let store = MockHighlightStore()
        let bookKey = wi9TXTFingerprint.canonicalKey
        let locator = makeTXTRangeLocator(start: 100, end: 200)

        let vm = HighlightListViewModel(
            bookFingerprintKey: bookKey,
            store: store,
            totalTextLengthUTF16: 1000
        )
        await vm.addHighlight(
            locator: locator,
            selectedText: "selected",
            color: "green",
            note: nil
        )

        #expect(vm.highlights.count == 1)
        let hl = vm.highlights.first!
        #expect(hl.locator.charRangeStartUTF16 == 100)
        #expect(hl.locator.charRangeEndUTF16 == 200)
    }
}
