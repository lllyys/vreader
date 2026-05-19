// Purpose: Feature #64 WI-1 — tests for `HighlightPopoverContent`, the value
// type the unified highlight-action popover renders.
//
// Covers `isEmpty` across nil / empty / whitespace / multiline / CJK / RTL
// note bodies, `id == highlightId`, `Equatable`, and the `chapter` / `anchor`
// fields carried beyond #55's `NotePreviewContent`.

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("HighlightPopoverContent")
struct HighlightPopoverContentTests {

    private func makeContent(
        id: UUID = UUID(),
        note: String? = nil,
        chapter: String? = nil,
        sourceRect: CGRect = .zero,
        anchor: AnnotationAnchor? = nil
    ) -> HighlightPopoverContent {
        HighlightPopoverContent(
            id: id,
            note: note,
            highlightedText: "the quick brown fox",
            colorName: "yellow",
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            chapter: chapter,
            sourceRect: sourceRect,
            anchor: anchor
        )
    }

    @Test func isEmpty_trueForNilNote() {
        #expect(makeContent(note: nil).isEmpty)
    }

    @Test func isEmpty_trueForEmptyString() {
        #expect(makeContent(note: "").isEmpty)
    }

    @Test(arguments: ["   ", "\n\n", "\t  \n", " \u{00A0} "])
    func isEmpty_trueForWhitespaceOnly(_ note: String) {
        // Note: a regular-space / newline / tab note is empty. NBSP ( )
        // is whitespace under .whitespacesAndNewlines so it also counts.
        #expect(makeContent(note: note).isEmpty)
    }

    @Test func isEmpty_falseForRealNote() {
        #expect(!makeContent(note: "a real note").isEmpty)
    }

    @Test func isEmpty_falseForMultilineNote() {
        #expect(!makeContent(note: "line one\nline two\nline three").isEmpty)
    }

    @Test func isEmpty_falseForCJKNote() {
        #expect(!makeContent(note: "这是一个笔记").isEmpty)
    }

    @Test func isEmpty_falseForRTLNote() {
        #expect(!makeContent(note: "هذه ملاحظة").isEmpty)
    }

    @Test func id_equalsHighlightId() {
        let highlightId = UUID()
        #expect(makeContent(id: highlightId).id == highlightId)
    }

    @Test func equatable_sameValuesAreEqual() {
        let id = UUID()
        let a = makeContent(id: id, note: "n", chapter: "Ch. 1")
        let b = makeContent(id: id, note: "n", chapter: "Ch. 1")
        #expect(a == b)
    }

    @Test func equatable_differentChapterDiffers() {
        let id = UUID()
        let a = makeContent(id: id, chapter: "Ch. 1")
        let b = makeContent(id: id, chapter: "Ch. 2")
        #expect(a != b)
    }

    private static let placeholderRange = EPUBSerializedRange(
        startContainerPath: "", startOffset: 0, endContainerPath: "", endOffset: 0
    )

    @Test func equatable_differentAnchorDiffers() {
        let id = UUID()
        let cfiAnchor = AnnotationAnchor.epub(
            href: "ch1.xhtml", cfi: "/6/4!/2", serializedRange: Self.placeholderRange
        )
        let a = makeContent(id: id, anchor: cfiAnchor)
        let b = makeContent(id: id, anchor: nil)
        #expect(a != b)
    }

    @Test func chapterAndAnchor_carried() {
        let cfiAnchor = AnnotationAnchor.epub(
            href: "ch2.xhtml", cfi: "/6/8!/4", serializedRange: Self.placeholderRange
        )
        let content = makeContent(chapter: "Chapter Two", anchor: cfiAnchor)
        #expect(content.chapter == "Chapter Two")
        #expect(content.anchor == cfiAnchor)
    }

    @Test func sourceRect_carried() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 24)
        #expect(makeContent(sourceRect: rect).sourceRect == rect)
    }
}
