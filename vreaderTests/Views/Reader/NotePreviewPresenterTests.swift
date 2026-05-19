// Purpose: Tests for feature #55 WI-1 foundational types — NotePreviewContent
// (the value type a note-preview surface renders) and NotePreviewPresenter
// (the pure parse/build + callout-vs-sheet decision boundary).
//
// Behavior under test, not pixels:
//   - content(for:sourceRect:) maps a HighlightRecord into NotePreviewContent.
//   - isEmpty trims whitespace — nil / "" / "   " are all the empty/no-note state.
//   - form(...) picks .callout vs .sheet per VoiceOver / note length / zero rect.

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("NotePreviewPresenter")
struct NotePreviewPresenterTests {

    static let fp = DocumentFingerprint(
        contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        fileByteCount: 1024,
        format: .epub
    )

    private static func makeRecord(
        note: String?,
        color: String = "yellow",
        selectedText: String = "the quoted passage",
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> HighlightRecord {
        let locator = Locator(
            bookFingerprint: fp,
            href: "ch1.xhtml", progression: 0.5, totalProgression: nil,
            cfi: "/6/4", page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        return HighlightRecord(
            highlightId: UUID(),
            locator: locator,
            anchor: nil,
            profileKey: "key",
            selectedText: selectedText,
            color: color,
            note: note,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }

    // MARK: - content(for:sourceRect:)

    @Test func contentMapsAllFieldsFromRecord() {
        let rect = CGRect(x: 10, y: 20, width: 100, height: 18)
        let record = Self.makeRecord(note: "my note body", color: "green",
                                     selectedText: "a passage")
        let content = NotePreviewPresenter.content(for: record, sourceRect: rect)

        #expect(content.id == record.highlightId)
        #expect(content.note == "my note body")
        #expect(content.highlightedText == "a passage")
        #expect(content.colorName == "green")
        #expect(content.createdAt == record.createdAt)
        #expect(content.sourceRect == rect)
    }

    @Test func contentPreservesNilNote() {
        let content = NotePreviewPresenter.content(
            for: Self.makeRecord(note: nil), sourceRect: .zero
        )
        #expect(content.note == nil)
        #expect(content.isEmpty)
    }

    // MARK: - isEmpty

    @Test(arguments: [
        (String?.none, true),
        (.some(""), true),
        (.some("   "), true),
        (.some("\n\t  "), true),
        (.some("real note"), false),
        (.some("  padded note  "), false),
    ])
    func isEmptyTrimsWhitespace(_ note: String?, _ expectedEmpty: Bool) {
        let content = NotePreviewPresenter.content(
            for: Self.makeRecord(note: note), sourceRect: .zero
        )
        #expect(content.isEmpty == expectedEmpty)
    }

    // MARK: - form(...) decision table

    @Test func shortNoteWithAnchorPicksCallout() {
        let content = NotePreviewPresenter.content(
            for: Self.makeRecord(note: "short"), sourceRect: CGRect(x: 5, y: 5, width: 50, height: 14)
        )
        let form = NotePreviewPresenter.form(
            for: content, isVoiceOverRunning: false, noteLineCount: 2
        )
        #expect(form == .callout)
    }

    @Test func longNotePicksSheet() {
        let content = NotePreviewPresenter.content(
            for: Self.makeRecord(note: "long"), sourceRect: CGRect(x: 5, y: 5, width: 50, height: 14)
        )
        let form = NotePreviewPresenter.form(
            for: content, isVoiceOverRunning: false, noteLineCount: 12
        )
        #expect(form == .sheet)
    }

    @Test func voiceOverAlwaysPicksSheet() {
        let content = NotePreviewPresenter.content(
            for: Self.makeRecord(note: "short"), sourceRect: CGRect(x: 5, y: 5, width: 50, height: 14)
        )
        let form = NotePreviewPresenter.form(
            for: content, isVoiceOverRunning: true, noteLineCount: 1
        )
        #expect(form == .sheet)
    }

    @Test func zeroSourceRectPicksSheet() {
        // Foliate emits sourceRect == .zero — an anchored callout would
        // point nowhere, so the sheet form is used (plan §2.9).
        let content = NotePreviewPresenter.content(
            for: Self.makeRecord(note: "short"), sourceRect: .zero
        )
        let form = NotePreviewPresenter.form(
            for: content, isVoiceOverRunning: false, noteLineCount: 1
        )
        #expect(form == .sheet)
    }

    @Test func lineCountThresholdBoundary() {
        let content = NotePreviewPresenter.content(
            for: Self.makeRecord(note: "n"), sourceRect: CGRect(x: 1, y: 1, width: 10, height: 10)
        )
        // At the threshold (6 lines) → still callout; one past → sheet.
        #expect(NotePreviewPresenter.form(
            for: content, isVoiceOverRunning: false, noteLineCount: 6) == .callout)
        #expect(NotePreviewPresenter.form(
            for: content, isVoiceOverRunning: false, noteLineCount: 7) == .sheet)
    }
}
