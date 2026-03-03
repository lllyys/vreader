import Testing
import Foundation

@testable import vreader

// MARK: - Highlight Model Tests

@Suite("Highlight Model")
struct HighlightTests {

    // MARK: - Creation

    @Test("creates highlight with required fields")
    func createWithRequiredFields() {
        let bookID = UUID()
        let highlight = Highlight(
            bookID: bookID,
            locator: BookLocator(chapter: 2, progression: 0.3),
            text: "To be or not to be",
            color: .yellow
        )

        #expect(highlight.bookID == bookID)
        #expect(highlight.text == "To be or not to be")
        #expect(highlight.color == .yellow)
        #expect(highlight.locator.chapter == 2)
    }

    @Test("assigns creation date automatically")
    func autoDateCreated() {
        let before = Date()
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            text: "Some text",
            color: .yellow
        )
        let after = Date()

        #expect(highlight.dateCreated >= before)
        #expect(highlight.dateCreated <= after)
    }

    @Test("creates highlight without note")
    func createWithoutNote() {
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.1),
            text: "Highlighted text",
            color: .green
        )

        #expect(highlight.note == nil)
    }

    @Test("creates highlight with note")
    func createWithNote() {
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.1),
            text: "Highlighted text",
            color: .blue,
            note: "This is my annotation"
        )

        #expect(highlight.note == "This is my annotation")
    }

    // MARK: - Colors

    @Test(
        "supports all highlight colors",
        arguments: [
            HighlightColor.yellow,
            HighlightColor.green,
            HighlightColor.blue,
            HighlightColor.pink,
            HighlightColor.purple,
        ]
    )
    func allColors(color: HighlightColor) {
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            text: "text",
            color: color
        )

        #expect(highlight.color == color)
    }

    // MARK: - Text Range

    @Test("stores text selection start and end offsets")
    func textRange() {
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.2),
            text: "selected text",
            color: .yellow,
            startOffset: 10,
            endOffset: 23
        )

        #expect(highlight.startOffset == 10)
        #expect(highlight.endOffset == 23)
    }

    @Test("end offset is greater than or equal to start offset")
    func rangeValidity() {
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            text: "x",
            color: .yellow,
            startOffset: 5,
            endOffset: 5
        )

        #expect(highlight.endOffset >= highlight.startOffset)
    }

    // MARK: - Note Editing

    @Test("note can be updated after creation")
    func updateNote() {
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            text: "text",
            color: .yellow
        )

        highlight.note = "Added later"
        #expect(highlight.note == "Added later")
    }

    @Test("note can be cleared")
    func clearNote() {
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            text: "text",
            color: .green,
            note: "Initial note"
        )

        highlight.note = nil
        #expect(highlight.note == nil)
    }

    // MARK: - Edge Cases: Unicode / CJK

    @Test("handles CJK highlighted text")
    func cjkText() {
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.5),
            text: "天地玄黄，宇宙洪荒",
            color: .yellow
        )

        #expect(highlight.text == "天地玄黄，宇宙洪荒")
    }

    @Test("handles mixed script text")
    func mixedScriptText() {
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            text: "Hello 世界 مرحبا 🌍",
            color: .blue
        )

        #expect(highlight.text == "Hello 世界 مرحبا 🌍")
    }

    @Test("handles CJK annotation note")
    func cjkNote() {
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            text: "text",
            color: .yellow,
            note: "これは重要なポイントです"
        )

        #expect(highlight.note == "これは重要なポイントです")
    }

    // MARK: - Edge Cases: Boundaries

    @Test("handles empty text string")
    func emptyText() {
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            text: "",
            color: .yellow
        )

        #expect(highlight.text.isEmpty)
    }

    @Test("handles very long highlighted text")
    func longText() {
        let longText = String(repeating: "word ", count: 2000)
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            text: longText,
            color: .yellow
        )

        #expect(highlight.text.count == longText.count)
    }

    @Test("handles very long note")
    func longNote() {
        let longNote = String(repeating: "annotation ", count: 1000)
        let highlight = Highlight(
            bookID: UUID(),
            locator: BookLocator(chapter: 1, progression: 0.0),
            text: "text",
            color: .yellow,
            note: longNote
        )

        #expect(highlight.note?.count == longNote.count)
    }

    // MARK: - Sorting

    @Test("highlights sort by chapter then progression")
    func sortOrder() {
        let bookID = UUID()
        let h1 = Highlight(
            bookID: bookID,
            locator: BookLocator(chapter: 2, progression: 0.1),
            text: "a",
            color: .yellow
        )
        let h2 = Highlight(
            bookID: bookID,
            locator: BookLocator(chapter: 1, progression: 0.9),
            text: "b",
            color: .green
        )
        let h3 = Highlight(
            bookID: bookID,
            locator: BookLocator(chapter: 1, progression: 0.2),
            text: "c",
            color: .blue
        )

        let sorted = [h1, h2, h3].sorted()

        #expect(sorted[0].text == "c") // ch1, 0.2
        #expect(sorted[1].text == "b") // ch1, 0.9
        #expect(sorted[2].text == "a") // ch2, 0.1
    }

    // MARK: - Book Reference

    @Test("highlight references parent book by ID")
    func bookReference() {
        let bookID = UUID()
        let highlight = Highlight(
            bookID: bookID,
            locator: BookLocator(chapter: 1, progression: 0.0),
            text: "text",
            color: .yellow
        )

        #expect(highlight.bookID == bookID)
    }
}
