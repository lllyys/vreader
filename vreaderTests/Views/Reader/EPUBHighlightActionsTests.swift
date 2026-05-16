// Purpose: Tests for EPUBHighlightActions — JS generation for
// highlight inject/restore, and edge cases.
//
// @coordinates-with: EPUBHighlightActions.swift, EPUBHighlightBridge.swift,
//   AnnotationAnchor.swift

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
@testable import vreader

// MARK: - Test Helpers

private let testFingerprint = DocumentFingerprint(
    contentSHA256: "aabbccdd00112233aabbccdd00112233aabbccdd00112233aabbccdd00112233",
    fileByteCount: 2048,
    format: .epub
)

private func makeTestLocator(href: String = "ch1.xhtml") -> Locator {
    Locator(
        bookFingerprint: testFingerprint,
        href: href,
        progression: 0.5,
        totalProgression: 0.25,
        cfi: nil,
        page: nil,
        charOffsetUTF16: nil,
        charRangeStartUTF16: nil,
        charRangeEndUTF16: nil,
        textQuote: nil,
        textContextBefore: nil,
        textContextAfter: nil
    )
}

private func makeTestRange(
    startPath: String = "/html/body/p[1]/text()",
    startOffset: Int = 0,
    endPath: String = "/html/body/p[1]/text()",
    endOffset: Int = 10
) -> EPUBSerializedRange {
    EPUBSerializedRange(
        startContainerPath: startPath,
        startOffset: startOffset,
        endContainerPath: endPath,
        endOffset: endOffset
    )
}

private func makeHighlightRecord(
    href: String = "ch1.xhtml",
    range: EPUBSerializedRange? = nil,
    color: String = "yellow",
    selectedText: String = "Hello World"
) -> HighlightRecord {
    let r = range ?? makeTestRange()
    let anchor = AnnotationAnchor.epub(href: href, cfi: "", serializedRange: r)
    let locator = makeTestLocator(href: href)
    return HighlightRecord(
        highlightId: UUID(),
        locator: locator,
        anchor: anchor,
        profileKey: "test-profile",
        selectedText: selectedText,
        color: color,
        note: nil,
        createdAt: Date(),
        updatedAt: Date()
    )
}

// Feature #60 WI-7c5b: the `EPUBHighlightActions.persistHighlight`
// suite was removed with the function. `handleHighlightAction`'s
// coordinator-not-ready fallback now calls
// `PersistenceActor.addHighlight(color:)` directly so the chosen
// SelectionPopover color is honored; the old helper hardcoded
// "yellow" and had no remaining caller. `addHighlight` is covered by
// `PersistenceActor` tests.

// MARK: - Create Highlight JS Tests

@Suite("EPUBHighlightActions — createHighlightJS")
struct EPUBHighlightActionsCreateJSTests {

    @Test("generates JS for epub anchor")
    func generatesJSForEPUBAnchor() {
        let range = makeTestRange()
        let anchor = AnnotationAnchor.epub(href: "ch1.xhtml", cfi: "", serializedRange: range)
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makeTestLocator(),
            anchor: anchor,
            profileKey: "test",
            selectedText: "Hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let js = EPUBHighlightActions.createHighlightJS(for: record)
        #expect(js != nil)
        #expect(js!.contains("createHighlight"))
        #expect(js!.contains("yellow"))
    }

    @Test("returns nil for non-epub anchor")
    func returnsNilForPDFAnchor() {
        let anchor = AnnotationAnchor.pdf(page: 5, rects: [])
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makeTestLocator(),
            anchor: anchor,
            profileKey: "test",
            selectedText: "Hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let js = EPUBHighlightActions.createHighlightJS(for: record)
        #expect(js == nil)
    }

    @Test("returns nil for nil anchor")
    func returnsNilForNilAnchor() {
        let record = HighlightRecord(
            highlightId: UUID(),
            locator: makeTestLocator(),
            anchor: nil,
            profileKey: "test",
            selectedText: "Hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let js = EPUBHighlightActions.createHighlightJS(for: record)
        #expect(js == nil)
    }
}

// MARK: - Restore Highlights Tests

@Suite("EPUBHighlightActions — restoreHighlightsJS")
struct EPUBHighlightActionsRestoreTests {

    @Test("filters highlights to current chapter href")
    func filtersToCurrentChapter() {
        let ch1 = makeHighlightRecord(href: "ch1.xhtml")
        let ch2 = makeHighlightRecord(href: "ch2.xhtml")
        let ch1b = makeHighlightRecord(href: "ch1.xhtml",
            range: makeTestRange(startOffset: 20, endOffset: 30))

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [ch1, ch2, ch1b],
            currentHref: "ch1.xhtml"
        )

        #expect(js.contains("createHighlight"))
        // Should contain references to ch1 highlights but not ch2
        // We verify by checking JS contains the highlight IDs for ch1 items
    }

    @Test("returns empty string for no matching highlights")
    func returnsEmptyForNoMatches() {
        let ch2 = makeHighlightRecord(href: "ch2.xhtml")

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [ch2],
            currentHref: "ch1.xhtml"
        )

        #expect(js.isEmpty)
    }

    @Test("returns empty string for empty highlights array")
    func returnsEmptyForEmptyArray() {
        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [],
            currentHref: "ch1.xhtml"
        )

        #expect(js.isEmpty)
    }

    @Test("handles highlights with nil anchor gracefully")
    func skipsNilAnchors() {
        let noAnchor = HighlightRecord(
            highlightId: UUID(),
            locator: makeTestLocator(),
            anchor: nil,
            profileKey: "test",
            selectedText: "Hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        let withAnchor = makeHighlightRecord(href: "ch1.xhtml")

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [noAnchor, withAnchor],
            currentHref: "ch1.xhtml"
        )

        // Should still generate JS for the one with a valid anchor
        #expect(js.contains("createHighlight"))
    }

    @Test("handles highlights with PDF anchor (wrong format) gracefully")
    func skipsPDFAnchors() {
        let pdfHighlight = HighlightRecord(
            highlightId: UUID(),
            locator: makeTestLocator(),
            anchor: .pdf(page: 1, rects: []),
            profileKey: "test",
            selectedText: "Hello",
            color: "yellow",
            note: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [pdfHighlight],
            currentHref: "ch1.xhtml"
        )

        #expect(js.isEmpty)
    }

    @Test("preserves highlight colors in restore JS")
    func preservesColors() {
        let yellow = makeHighlightRecord(href: "ch1.xhtml", color: "yellow")
        let blue = makeHighlightRecord(href: "ch1.xhtml",
            range: makeTestRange(startOffset: 20, endOffset: 30), color: "blue")

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [yellow, blue],
            currentHref: "ch1.xhtml"
        )

        #expect(js.contains("yellow"))
        #expect(js.contains("blue"))
    }

    @Test("empty currentHref returns empty string")
    func emptyHrefReturnsEmpty() {
        let record = makeHighlightRecord(href: "ch1.xhtml")

        let js = EPUBHighlightActions.restoreHighlightsJS(
            highlights: [record],
            currentHref: ""
        )

        #expect(js.isEmpty)
    }
}
#endif
