// Purpose: Feature #64 WI-2 — tests for `HighlightPopoverPresenter`, the pure
// `HighlightRecord` → `HighlightPopoverContent` mapping + the anchored-card-
// vs-bottom-sheet form decision for the unified highlight-action popover.
//
// Covers: `content(for:sourceRect:chapter:)` field mapping; `form` →
// `.sheet` when VoiceOver / long note (boundary at exactly 6 and 7 lines) /
// `sourceRect == .zero`; `.card` otherwise; `resolvedForm` degrades a
// `.card` to `.sheet` when no host view. (A parity fence against feature
// #55's `NotePreviewPresenter` lived here through the WI-6..9 migration; it
// was removed in WI-10 when that presenter was deleted.)

import Testing
import Foundation
import CoreGraphics
@testable import vreader

@Suite("HighlightPopoverPresenter")
struct HighlightPopoverPresenterTests {

    private let fingerprint = DocumentFingerprint(
        contentSHA256: String(repeating: "a", count: 64),
        fileByteCount: 100, format: .epub
    )

    private func makeRecord(
        id: UUID = UUID(),
        note: String? = "a note",
        color: String = "yellow",
        selectedText: String = "the highlighted passage"
    ) -> HighlightRecord {
        let locator = Locator.validated(
            bookFingerprint: fingerprint, href: "ch1.xhtml", progression: 0.5
        )!
        return HighlightRecord(
            highlightId: id, locator: locator, anchor: nil, profileKey: "p",
            selectedText: selectedText, color: color, note: note,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    // MARK: - content(for:sourceRect:chapter:)

    @Test func content_mapsAllFields() {
        let cfiAnchor = AnnotationAnchor.epub(
            href: "ch1.xhtml", cfi: "/6/4!/2",
            serializedRange: EPUBSerializedRange(
                startContainerPath: "", startOffset: 0, endContainerPath: "", endOffset: 0
            )
        )
        let id = UUID()
        let locator = Locator.validated(bookFingerprint: fingerprint)!
        let record = HighlightRecord(
            highlightId: id, locator: locator, anchor: cfiAnchor, profileKey: "p",
            selectedText: "passage text", color: "pink", note: "note body",
            createdAt: Date(timeIntervalSince1970: 42),
            updatedAt: Date(timeIntervalSince1970: 99)
        )
        let rect = CGRect(x: 1, y: 2, width: 3, height: 4)
        let content = HighlightPopoverPresenter.content(
            for: record, sourceRect: rect, chapter: "Chapter 1"
        )
        #expect(content.id == id)
        #expect(content.note == "note body")
        #expect(content.highlightedText == "passage text")
        #expect(content.colorName == "pink")
        #expect(content.createdAt == Date(timeIntervalSince1970: 42))
        #expect(content.chapter == "Chapter 1")
        #expect(content.sourceRect == rect)
        #expect(content.anchor == cfiAnchor)
    }

    @Test func content_nilChapterCarried() {
        let content = HighlightPopoverPresenter.content(
            for: makeRecord(), sourceRect: .zero, chapter: nil
        )
        #expect(content.chapter == nil)
    }

    // MARK: - form

    @Test func form_voiceOverRunning_forcesSheet() {
        let content = HighlightPopoverPresenter.content(
            for: makeRecord(), sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            chapter: nil
        )
        let form = HighlightPopoverPresenter.form(
            for: content, isVoiceOverRunning: true, noteLineCount: 1
        )
        #expect(form == .sheet)
    }

    @Test func form_zeroSourceRect_forcesSheet() {
        let content = HighlightPopoverPresenter.content(
            for: makeRecord(), sourceRect: .zero, chapter: nil
        )
        let form = HighlightPopoverPresenter.form(
            for: content, isVoiceOverRunning: false, noteLineCount: 1
        )
        #expect(form == .sheet)
    }

    @Test func form_shortNoteWithAnchor_isCard() {
        let content = HighlightPopoverPresenter.content(
            for: makeRecord(), sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            chapter: nil
        )
        let form = HighlightPopoverPresenter.form(
            for: content, isVoiceOverRunning: false, noteLineCount: 3
        )
        #expect(form == .card)
    }

    /// Boundary: a note at exactly `cardMaxNoteLines` (6) still uses the card.
    @Test func form_noteAtExactlySixLines_isCard() {
        let content = HighlightPopoverPresenter.content(
            for: makeRecord(), sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            chapter: nil
        )
        let form = HighlightPopoverPresenter.form(
            for: content, isVoiceOverRunning: false,
            noteLineCount: HighlightPopoverPresenter.cardMaxNoteLines
        )
        #expect(form == .card)
    }

    /// Boundary: a note one line past the cap (7) falls back to the sheet.
    @Test func form_noteAtSevenLines_isSheet() {
        let content = HighlightPopoverPresenter.content(
            for: makeRecord(), sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            chapter: nil
        )
        let form = HighlightPopoverPresenter.form(
            for: content, isVoiceOverRunning: false,
            noteLineCount: HighlightPopoverPresenter.cardMaxNoteLines + 1
        )
        #expect(form == .sheet)
    }

    // MARK: - resolvedForm

    @Test func resolvedForm_cardWithNoHostView_degradesToSheet() {
        let content = HighlightPopoverPresenter.content(
            for: makeRecord(), sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            chapter: nil
        )
        let form = HighlightPopoverPresenter.resolvedForm(
            for: content, isVoiceOverRunning: false, noteLineCount: 1, hasHostView: false
        )
        #expect(form == .sheet)
    }

    @Test func resolvedForm_cardWithHostView_staysCard() {
        let content = HighlightPopoverPresenter.content(
            for: makeRecord(), sourceRect: CGRect(x: 0, y: 0, width: 10, height: 10),
            chapter: nil
        )
        let form = HighlightPopoverPresenter.resolvedForm(
            for: content, isVoiceOverRunning: false, noteLineCount: 1, hasHostView: true
        )
        #expect(form == .card)
    }

    /// A sheet stays a sheet regardless of host-view availability.
    @Test func resolvedForm_sheetStaysSheetWithoutHostView() {
        let content = HighlightPopoverPresenter.content(
            for: makeRecord(), sourceRect: .zero, chapter: nil
        )
        let form = HighlightPopoverPresenter.resolvedForm(
            for: content, isVoiceOverRunning: false, noteLineCount: 1, hasHostView: false
        )
        #expect(form == .sheet)
    }

    // NOTE: the `resolvedForm` parity fence against feature #55's
    // `NotePreviewPresenter` was removed here in feature #64 WI-10 — that
    // presenter is deleted, so the cross-check can no longer run. The unified
    // presenter's own `resolvedForm` axes (voiceOver / note-line-count /
    // host-view) stay covered by the `resolvedForm_*` tests above.

    @Test func cardMaxNoteLines_isSix() {
        #expect(HighlightPopoverPresenter.cardMaxNoteLines == 6)
    }
}
