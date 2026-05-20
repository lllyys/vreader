// Purpose: Tests for HighlightRenderer adapters (Phase R4a).
// Validates TextHighlightRenderer, EPUBHighlightRenderer, and
// PDFHighlightRenderer behavior in isolation.
//
// @coordinates-with: TextHighlightRenderer.swift, EPUBHighlightRenderer.swift,
//   PDFHighlightRenderer.swift, HighlightRenderer.swift

#if canImport(UIKit)
import Testing
import Foundation
import PDFKit
@testable import vreader

// MARK: - Helpers

private let testFP = DocumentFingerprint(
    contentSHA256: "renderer_test_sha256_000000000000000000000000000000000000",
    fileByteCount: 100,
    format: .txt
)

private func makeLocator(
    start: Int, end: Int
) -> Locator {
    Locator(
        bookFingerprint: testFP,
        href: nil, progression: nil, totalProgression: nil, cfi: nil, page: nil,
        charOffsetUTF16: nil,
        charRangeStartUTF16: start, charRangeEndUTF16: end,
        textQuote: nil, textContextBefore: nil, textContextAfter: nil
    )
}

private func makeRecord(
    id: UUID = UUID(),
    start: Int = 0,
    end: Int = 10,
    anchor: AnnotationAnchor? = nil,
    color: String = "yellow"
) -> HighlightRecord {
    HighlightRecord(
        highlightId: id,
        locator: makeLocator(start: start, end: end),
        anchor: anchor,
        profileKey: "test-key",
        selectedText: "test text",
        color: color,
        note: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
}

private func makeEPUBRange() -> EPUBSerializedRange {
    EPUBSerializedRange(
        startContainerPath: "/html/body/p[1]/text()",
        startOffset: 0,
        endContainerPath: "/html/body/p[1]/text()",
        endOffset: 5
    )
}

// MARK: - TextHighlightRenderer Tests

@Suite("TextHighlightRenderer")
struct TextHighlightRendererTests {

    @Test @MainActor func applyAddsRangeToUIState() {
        let state = TextReaderUIState()
        let renderer = TextHighlightRenderer(uiState: state)
        let record = makeRecord(start: 10, end: 20)

        renderer.apply(record: record)

        #expect(state.highlightRange == NSRange(location: 10, length: 10))
        #expect(state.highlightIsTemporary == false)
        #expect(state.persistedHighlightRanges.count == 1)
        #expect(state.persistedHighlightRanges[0].range == NSRange(location: 10, length: 10))
    }

    @Test @MainActor func applyCarriesRecordColor() {
        // Bug #208 / GH #776: apply must thread the record's stored color
        // through to the painter instead of dropping it.
        let state = TextReaderUIState()
        let renderer = TextHighlightRenderer(uiState: state)

        renderer.apply(record: makeRecord(start: 0, end: 5, color: "pink"))

        #expect(state.persistedHighlightRanges.count == 1)
        #expect(state.persistedHighlightRanges[0].colorName == "pink")
    }

    @Test @MainActor func applyIgnoresInvertedRange() {
        let state = TextReaderUIState()
        let renderer = TextHighlightRenderer(uiState: state)
        let record = makeRecord(start: 20, end: 10)

        renderer.apply(record: record)

        #expect(state.highlightRange == nil)
        #expect(state.persistedHighlightRanges.isEmpty)
    }

    @Test @MainActor func applyIgnoresZeroLengthRange() {
        let state = TextReaderUIState()
        let renderer = TextHighlightRenderer(uiState: state)
        let record = makeRecord(start: 10, end: 10)

        renderer.apply(record: record)

        #expect(state.highlightRange == nil)
        #expect(state.persistedHighlightRanges.isEmpty)
    }

    @Test @MainActor func applyIgnoresMissingRange() {
        let state = TextReaderUIState()
        let renderer = TextHighlightRenderer(uiState: state)
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: Locator(
                bookFingerprint: testFP,
                href: nil, progression: nil, totalProgression: nil, cfi: nil, page: nil,
                charOffsetUTF16: nil,
                charRangeStartUTF16: nil, charRangeEndUTF16: nil,
                textQuote: nil, textContextBefore: nil, textContextAfter: nil
            ),
            anchor: nil, profileKey: "k", selectedText: "t", color: "yellow",
            note: nil, createdAt: Date(), updatedAt: Date()
        )

        renderer.apply(record: record)

        #expect(state.highlightRange == nil)
        #expect(state.persistedHighlightRanges.isEmpty)
    }

    @Test @MainActor func applyAccumulatesMultipleRanges() {
        let state = TextReaderUIState()
        let renderer = TextHighlightRenderer(uiState: state)

        renderer.apply(record: makeRecord(start: 0, end: 5))
        renderer.apply(record: makeRecord(start: 10, end: 20))

        #expect(state.persistedHighlightRanges.count == 2)
        #expect(state.highlightRange == NSRange(location: 10, length: 10))
    }

    @Test @MainActor func applyIsIdempotentOnSameHighlightId() {
        // Bug #237 round-2 audit (Medium): `HighlightCoordinator.create` may
        // resolve the same `HighlightRecord` twice when two callers race on
        // the same locator — the persistence layer dedupes (returning the
        // existing record), but `renderer.apply(record:)` was previously
        // appending the range every call. The DebugBridge highlight-driver
        // can fire URLs back-to-back, surfacing the latent double-paint.
        // The fix: skip the append when the highlightId is already tracked.
        let state = TextReaderUIState()
        let renderer = TextHighlightRenderer(uiState: state)
        let id = UUID()
        let recordA = makeRecord(id: id, start: 10, end: 20)
        let recordB = makeRecord(id: id, start: 10, end: 20) // same id

        renderer.apply(record: recordA)
        renderer.apply(record: recordB)

        #expect(state.persistedHighlightRanges.count == 1,
                "second apply with the same highlightId must not double-append")
        #expect(state.persistedHighlightLookup.count == 1,
                "second apply with the same highlightId must not double-track in the lookup")
    }

    @Test @MainActor func applyIsIdempotentEvenWhenColorChanged() {
        // Same id, different color. The first apply wins — a follow-up
        // mutation should go through `restoreAll` / `changeColor` (which
        // rebuilds the state from scratch), not a second `apply`.
        let state = TextReaderUIState()
        let renderer = TextHighlightRenderer(uiState: state)
        let id = UUID()

        renderer.apply(record: makeRecord(id: id, start: 0, end: 5, color: "yellow"))
        renderer.apply(record: makeRecord(id: id, start: 0, end: 5, color: "pink"))

        #expect(state.persistedHighlightRanges.count == 1)
        #expect(state.persistedHighlightRanges[0].colorName == "yellow",
                "first-write-wins on the dedupe path; color updates flow through restoreAll")
    }

    @Test @MainActor func removeClearsActiveHighlight() {
        let state = TextReaderUIState()
        state.highlightRange = NSRange(location: 10, length: 10)
        state.highlightIsTemporary = false
        let renderer = TextHighlightRenderer(uiState: state)

        renderer.remove(id: UUID())

        #expect(state.highlightRange == nil)
    }

    @Test @MainActor func removeDoesNotClearPersistedRanges() {
        let state = TextReaderUIState()
        state.persistedHighlightRanges = [
            PaintedHighlight(range: NSRange(location: 0, length: 5), colorName: "yellow")
        ]
        let renderer = TextHighlightRenderer(uiState: state)

        renderer.remove(id: UUID())

        // Persisted ranges are rebuilt by restore(), not cleared by remove()
        #expect(state.persistedHighlightRanges.count == 1)
    }

    @Test @MainActor func restoreRefreshesPersistedRanges() {
        let state = TextReaderUIState()
        state.persistedHighlightRanges = [
            PaintedHighlight(range: NSRange(location: 99, length: 1), colorName: "yellow")
        ]
        let renderer = TextHighlightRenderer(uiState: state)
        let records = [
            makeRecord(start: 0, end: 10),
            makeRecord(start: 20, end: 30),
        ]

        renderer.restore(records: records)

        #expect(state.persistedHighlightRanges.count == 2)
        #expect(state.persistedHighlightRanges[0].range == NSRange(location: 0, length: 10))
        #expect(state.persistedHighlightRanges[1].range == NSRange(location: 20, length: 10))
    }

    @Test @MainActor func restoreCarriesRecordColors() {
        // Bug #208 / GH #776: restored highlights must keep their stored
        // colors so reopening a book repaints pink/green/blue, not yellow.
        let state = TextReaderUIState()
        let renderer = TextHighlightRenderer(uiState: state)
        let records = [
            makeRecord(start: 0, end: 10, color: "green"),
            makeRecord(start: 20, end: 30, color: "blue"),
        ]

        renderer.restore(records: records)

        #expect(state.persistedHighlightRanges.map(\.colorName) == ["green", "blue"])
    }

    @Test @MainActor func restoreWithEmptyRecordsClearsRanges() {
        let state = TextReaderUIState()
        state.persistedHighlightRanges = [
            PaintedHighlight(range: NSRange(location: 0, length: 5), colorName: "yellow")
        ]
        let renderer = TextHighlightRenderer(uiState: state)

        renderer.restore(records: [])

        #expect(state.persistedHighlightRanges.isEmpty)
    }
}

// MARK: - EPUBHighlightRenderer Tests

@Suite("EPUBHighlightRenderer")
struct EPUBHighlightRendererTests {

    @Test @MainActor func applyInjectsCreateJS() {
        let renderer = EPUBHighlightRenderer()
        var injectedJS: String?
        renderer.onInjectJS = { js in injectedJS = js }

        let anchor = AnnotationAnchor.epub(
            href: "ch1.xhtml", cfi: "", serializedRange: makeEPUBRange()
        )
        let record = makeRecord(anchor: anchor)

        renderer.apply(record: record)

        #expect(injectedJS != nil)
        #expect(injectedJS?.contains("__vreader_createHighlight") == true)
    }

    @Test @MainActor func applySkipsRecordWithoutEPUBAnchor() {
        let renderer = EPUBHighlightRenderer()
        var injectedJS: String?
        renderer.onInjectJS = { js in injectedJS = js }

        renderer.apply(record: makeRecord()) // no anchor

        #expect(injectedJS == nil)
    }

    @Test @MainActor func applySkipsRecordWithPDFAnchor() {
        let renderer = EPUBHighlightRenderer()
        var injectedJS: String?
        renderer.onInjectJS = { js in injectedJS = js }

        let anchor = AnnotationAnchor.pdf(page: 0, rects: [.zero])
        renderer.apply(record: makeRecord(anchor: anchor))

        #expect(injectedJS == nil)
    }

    @Test @MainActor func applyDoesNothingWithoutCallback() {
        let renderer = EPUBHighlightRenderer()
        // onInjectJS is nil — should not crash
        let anchor = AnnotationAnchor.epub(
            href: "ch1.xhtml", cfi: "", serializedRange: makeEPUBRange()
        )
        renderer.apply(record: makeRecord(anchor: anchor))
        // No assertion needed — just verifying no crash
    }

    @Test @MainActor func removeInjectsRemoveJS() {
        let renderer = EPUBHighlightRenderer()
        var injectedJS: String?
        renderer.onInjectJS = { js in injectedJS = js }
        let id = UUID()

        renderer.remove(id: id)

        #expect(injectedJS != nil)
        #expect(injectedJS?.contains("__vreader_removeHighlight") == true)
        #expect(injectedJS?.contains(id.uuidString) == true)
    }

    @Test @MainActor func restoreFiltersbyCurrentHref() {
        let renderer = EPUBHighlightRenderer()
        renderer.currentHref = "chapter1.xhtml"
        var injectedJS: String?
        renderer.onInjectJS = { js in injectedJS = js }

        let range = makeEPUBRange()
        let anchor1 = AnnotationAnchor.epub(
            href: "chapter1.xhtml", cfi: "", serializedRange: range
        )
        let anchor2 = AnnotationAnchor.epub(
            href: "chapter2.xhtml", cfi: "", serializedRange: range
        )
        let records = [
            makeRecord(anchor: anchor1),
            makeRecord(anchor: anchor2),
        ]

        renderer.restore(records: records)

        #expect(injectedJS != nil)
        #expect(injectedJS?.contains("__vreader_createHighlight") == true)
    }

    @Test @MainActor func restoreSkipsWhenNoHref() {
        let renderer = EPUBHighlightRenderer()
        renderer.currentHref = nil
        var injectedJS: String?
        renderer.onInjectJS = { js in injectedJS = js }

        let anchor = AnnotationAnchor.epub(
            href: "ch1.xhtml", cfi: "", serializedRange: makeEPUBRange()
        )
        renderer.restore(records: [makeRecord(anchor: anchor)])

        #expect(injectedJS == nil)
    }

    @Test @MainActor func restoreSkipsWhenEmptyHref() {
        let renderer = EPUBHighlightRenderer()
        renderer.currentHref = ""
        var injectedJS: String?
        renderer.onInjectJS = { js in injectedJS = js }

        let anchor = AnnotationAnchor.epub(
            href: "ch1.xhtml", cfi: "", serializedRange: makeEPUBRange()
        )
        renderer.restore(records: [makeRecord(anchor: anchor)])

        #expect(injectedJS == nil)
    }

    @Test @MainActor func restoreSkipsWhenNoMatchingHighlights() {
        let renderer = EPUBHighlightRenderer()
        renderer.currentHref = "chapter3.xhtml"
        var injectedJS: String?
        renderer.onInjectJS = { js in injectedJS = js }

        let anchor = AnnotationAnchor.epub(
            href: "chapter1.xhtml", cfi: "", serializedRange: makeEPUBRange()
        )
        renderer.restore(records: [makeRecord(anchor: anchor)])

        #expect(injectedJS == nil)
    }
}

// MARK: - PDFHighlightRenderer Tests

@Suite("PDFHighlightRenderer")
struct PDFHighlightRendererTests {

    @Test @MainActor func applyTracksAnnotationInMap() {
        let renderer = PDFHighlightRenderer()
        let doc = PDFDocument()
        let page = PDFPage()
        doc.insert(page, at: 0)
        renderer.setDocument(doc)

        let anchor = AnnotationAnchor.pdf(
            page: 0, rects: [CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)]
        )
        let id = UUID()
        let record = makeRecord(id: id, anchor: anchor)

        renderer.apply(record: record)

        #expect(renderer.annotationMap[id] != nil)
        #expect(renderer.annotationMap[id]?.isEmpty == false)
    }

    @Test @MainActor func removeDeletesFromMapAndPage() {
        let renderer = PDFHighlightRenderer()
        let doc = PDFDocument()
        let page = PDFPage()
        doc.insert(page, at: 0)
        renderer.setDocument(doc)

        let anchor = AnnotationAnchor.pdf(
            page: 0, rects: [CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)]
        )
        let id = UUID()
        renderer.apply(record: makeRecord(id: id, anchor: anchor))
        let annotationCountBefore = page.annotations.count

        renderer.remove(id: id)

        #expect(renderer.annotationMap[id] == nil)
        #expect(page.annotations.count < annotationCountBefore)
    }

    @Test @MainActor func removeUnknownIdIsNoOp() {
        let renderer = PDFHighlightRenderer()
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        renderer.setDocument(doc)

        // Should not crash
        renderer.remove(id: UUID())
        #expect(renderer.annotationMap.isEmpty)
    }

    @Test @MainActor func restorePopulatesAnnotationMap() {
        let renderer = PDFHighlightRenderer()
        let doc = PDFDocument()
        let page = PDFPage()
        doc.insert(page, at: 0)
        renderer.setDocument(doc)

        let id1 = UUID()
        let id2 = UUID()
        let anchor1 = AnnotationAnchor.pdf(
            page: 0, rects: [CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)]
        )
        let anchor2 = AnnotationAnchor.pdf(
            page: 0, rects: [CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.05)]
        )
        let records = [
            makeRecord(id: id1, anchor: anchor1),
            makeRecord(id: id2, anchor: anchor2),
        ]

        renderer.restore(records: records)

        #expect(renderer.annotationMap.count == 2)
        #expect(renderer.annotationMap[id1] != nil)
        #expect(renderer.annotationMap[id2] != nil)
    }

    @Test @MainActor func setDocumentOnlyResetsOnNewDocument() {
        let renderer = PDFHighlightRenderer()
        let doc = PDFDocument()
        let page = PDFPage()
        doc.insert(page, at: 0)
        renderer.setDocument(doc)

        let anchor = AnnotationAnchor.pdf(
            page: 0, rects: [CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)]
        )
        renderer.apply(record: makeRecord(id: UUID(), anchor: anchor))
        #expect(!renderer.annotationMap.isEmpty)

        // Re-set same document — should NOT clear map
        renderer.setDocument(doc)
        #expect(!renderer.annotationMap.isEmpty)

        // Set different document — should clear map
        let newDoc = PDFDocument()
        renderer.setDocument(newDoc)
        #expect(renderer.annotationMap.isEmpty)
    }

    @Test @MainActor func applyWithoutDocumentIsNoOp() {
        let renderer = PDFHighlightRenderer()
        // No document set
        let anchor = AnnotationAnchor.pdf(
            page: 0, rects: [CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)]
        )
        renderer.apply(record: makeRecord(anchor: anchor))

        #expect(renderer.annotationMap.isEmpty)
    }

    @Test @MainActor func applyWithoutAnchorIsNoOp() {
        let renderer = PDFHighlightRenderer()
        let doc = PDFDocument()
        doc.insert(PDFPage(), at: 0)
        renderer.setDocument(doc)

        renderer.apply(record: makeRecord()) // no anchor

        #expect(renderer.annotationMap.isEmpty)
    }

    @Test @MainActor func createThenDeleteRoundTrip() {
        let renderer = PDFHighlightRenderer()
        let doc = PDFDocument()
        let page = PDFPage()
        doc.insert(page, at: 0)
        renderer.setDocument(doc)

        let id = UUID()
        let anchor = AnnotationAnchor.pdf(
            page: 0, rects: [CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)]
        )
        renderer.apply(record: makeRecord(id: id, anchor: anchor))
        #expect(!renderer.annotationMap.isEmpty)

        renderer.remove(id: id)
        #expect(renderer.annotationMap.isEmpty)
    }
}
#endif
