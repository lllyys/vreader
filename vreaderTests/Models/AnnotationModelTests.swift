// Purpose: Tests for Bookmark, Highlight, and AnnotationNote models —
// initialization, profileKey, and edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("Annotation Models")
struct AnnotationModelTests {

    static let sampleFP = DocumentFingerprint(
        contentSHA256: "annot123", fileByteCount: 1024, format: .epub
    )

    static let sampleLocator = Locator(
        bookFingerprint: sampleFP,
        href: "ch1.xhtml", progression: 0.5, totalProgression: 0.25,
        cfi: "/6/4", page: nil,
        charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
        textQuote: "sample text", textContextBefore: nil, textContextAfter: nil
    )

    // MARK: - Bookmark

    @Test func bookmarkInitSetsProfileKey() {
        let bookmark = Bookmark(locator: Self.sampleLocator, title: "My Bookmark")
        let expectedPrefix = Self.sampleFP.canonicalKey
        #expect(bookmark.profileKey.hasPrefix(expectedPrefix))
        #expect(bookmark.profileKey.contains(Self.sampleLocator.canonicalHash))
    }

    @Test func bookmarkDefaultsAreCorrect() {
        let bookmark = Bookmark(locator: Self.sampleLocator)
        #expect(bookmark.title == nil)
        #expect(bookmark.book == nil)
        #expect(bookmark.createdAt == bookmark.updatedAt)
    }

    @Test func bookmarkIdIsUnique() {
        let b1 = Bookmark(locator: Self.sampleLocator)
        let b2 = Bookmark(locator: Self.sampleLocator)
        #expect(b1.bookmarkId != b2.bookmarkId)
    }

    // MARK: - Highlight

    @Test func highlightInitSetsAllFields() {
        let highlight = Highlight(
            locator: Self.sampleLocator,
            selectedText: "important passage",
            color: "blue",
            note: "This is key"
        )
        #expect(highlight.selectedText == "important passage")
        #expect(highlight.color == "blue")
        #expect(highlight.note == "This is key")
    }

    @Test func highlightDefaultColor() {
        let highlight = Highlight(locator: Self.sampleLocator, selectedText: "text")
        #expect(highlight.color == "yellow")
    }

    @Test func highlightProfileKeyConsistency() {
        let h1 = Highlight(locator: Self.sampleLocator, selectedText: "a")
        let h2 = Highlight(locator: Self.sampleLocator, selectedText: "b")
        // Same locator → same profileKey
        #expect(h1.profileKey == h2.profileKey)
    }

    @Test func highlightIdIsUnique() {
        let h1 = Highlight(locator: Self.sampleLocator, selectedText: "a")
        let h2 = Highlight(locator: Self.sampleLocator, selectedText: "b")
        #expect(h1.highlightId != h2.highlightId)
    }

    // MARK: - AnnotationNote

    @Test func annotationNoteInitSetsFields() {
        let note = AnnotationNote(locator: Self.sampleLocator, content: "My thought")
        #expect(note.content == "My thought")
        #expect(note.createdAt == note.updatedAt)
    }

    @Test func annotationNoteProfileKey() {
        let note = AnnotationNote(locator: Self.sampleLocator, content: "test")
        let expectedPrefix = Self.sampleFP.canonicalKey
        #expect(note.profileKey.hasPrefix(expectedPrefix))
    }

    @Test func annotationNoteIdIsUnique() {
        let n1 = AnnotationNote(locator: Self.sampleLocator, content: "a")
        let n2 = AnnotationNote(locator: Self.sampleLocator, content: "b")
        #expect(n1.annotationId != n2.annotationId)
    }

    // MARK: - Edge Cases

    @Test func bookmarkWithEmptyTitle() {
        let bookmark = Bookmark(locator: Self.sampleLocator, title: "")
        #expect(bookmark.title == "")
    }

    @Test func highlightWithEmptyText() {
        let highlight = Highlight(locator: Self.sampleLocator, selectedText: "")
        #expect(highlight.selectedText == "")
    }

    @Test func annotationWithUnicodeContent() {
        let note = AnnotationNote(locator: Self.sampleLocator, content: "笔记: 重要内容 📝")
        #expect(note.content == "笔记: 重要内容 📝")
    }

    @Test func highlightWithLongText() {
        let longText = String(repeating: "a", count: 10_000)
        let highlight = Highlight(locator: Self.sampleLocator, selectedText: longText)
        #expect(highlight.selectedText.count == 10_000)
    }
}
