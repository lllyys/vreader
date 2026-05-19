// Purpose: Feature #64 WI-2 — tests for `HighlightPopoverPresenter`, the pure
// `HighlightRecord` → `HighlightPopoverContent` mapping + the anchored-card-
// vs-bottom-sheet form decision for the unified highlight-action popover.
//
// Covers: `content(for:sourceRect:chapter:)` field mapping; `form` →
// `.sheet` when VoiceOver / long note (boundary at exactly 6 and 7 lines) /
// `sourceRect == .zero`; `.card` otherwise; `resolvedForm` degrades a
// `.card` to `.sheet` when no host view; a parity fence — the same inputs
// as `NotePreviewPresenter.resolvedForm` produce the matching form (a
// regression fence until #55's presenter is deleted in WI-10).

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

    // MARK: - Parity fence with NotePreviewPresenter (deleted in WI-10)

    /// Until WI-10 deletes #55's presenter, this fence proves the unified
    /// presenter's `resolvedForm` decision matches `NotePreviewPresenter`'s
    /// for every combination of inputs — so the migration is behavior-
    /// preserving on the form-selection axis.
    @Test(arguments: [
        (true,  0,  true),  (false, 0,  true),  (false, 7,  true),
        (true,  3,  false), (false, 3,  false), (false, 6,  true),
        (false, 6,  false), (false, 7,  false),
    ])
    func resolvedForm_parityWithNotePreviewPresenter(
        _ voiceOver: Bool, _ lineCount: Int, _ hasHost: Bool
    ) {
        // Use a non-zero rect so the only sheet triggers are voiceOver /
        // lineCount / hasHostView — the axes both presenters share.
        let rect = CGRect(x: 0, y: 0, width: 10, height: 10)
        let record = makeRecord()

        let unifiedContent = HighlightPopoverPresenter.content(
            for: record, sourceRect: rect, chapter: nil
        )
        let unified = HighlightPopoverPresenter.resolvedForm(
            for: unifiedContent, isVoiceOverRunning: voiceOver,
            noteLineCount: lineCount, hasHostView: hasHost
        )

        let legacyContent = NotePreviewPresenter.content(for: record, sourceRect: rect)
        let legacy = NotePreviewPresenter.resolvedForm(
            for: legacyContent, isVoiceOverRunning: voiceOver,
            noteLineCount: lineCount, hasHostView: hasHost
        )

        // `.card`/`.callout` and `.sheet`/`.sheet` are the matching pairs.
        let unifiedIsSheet = (unified == .sheet)
        let legacyIsSheet = (legacy == .sheet)
        #expect(unifiedIsSheet == legacyIsSheet)
    }

    @Test func cardMaxNoteLines_isSix() {
        #expect(HighlightPopoverPresenter.cardMaxNoteLines == 6)
    }
}
