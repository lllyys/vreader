// Purpose: Feature #62 WI-4 — pins the two annotation card views'
// composition.
//
// `HighlightCardV3` is the passage card (a quoted highlight, optional
// note block) and `StandaloneNoteCard` is the NEW standalone-note card
// (the note body is the hero; no quoted passage) — both from the
// committed #860 design `vreader-notes-unified.jsx`. They are the two
// card kinds `HighlightsSheet`'s unified stream interleaves.
//
// The contracts these tests guard: both build for every theme;
// `HighlightCardV3` renders the note block iff the highlight carries a
// non-empty note; `StandaloneNoteCard` builds with CJK content; both
// cards' `onJump` closure is invoked with the record locator on tap.
//
// @coordinates-with: HighlightAnnotationCard.swift, ReaderThemeV2.swift,
//   HighlightRecord.swift, AnnotationRecord.swift

import Testing
import SwiftUI
@testable import vreader

@Suite("Feature #62 — HighlightAnnotationCard")
@MainActor
struct HighlightAnnotationCardTests {

    // MARK: - HighlightCardV3

    @Test("HighlightCardV3 builds for every theme")
    func highlightCardBuildsForEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            let card = HighlightCardV3(
                theme: theme,
                highlight: makeHighlightRecord(selectedText: "a passage"),
                onJump: { _ in }
            )
            _ = card.body
        }
    }

    @Test("HighlightCardV3 shows the note block when the note is non-empty")
    func highlightCardShowsNoteWhenPresent() {
        let withNote = HighlightCardV3(
            theme: .paper,
            highlight: makeHighlightRecord(note: "a real note"),
            onJump: { _ in }
        )
        #expect(withNote.showsNoteBlock)
    }

    @Test("HighlightCardV3 hides the note block when the note is nil or empty")
    func highlightCardHidesNoteWhenAbsent() {
        let nilNote = HighlightCardV3(
            theme: .paper, highlight: makeHighlightRecord(note: nil), onJump: { _ in }
        )
        let emptyNote = HighlightCardV3(
            theme: .paper, highlight: makeHighlightRecord(note: ""), onJump: { _ in }
        )
        #expect(nilNote.showsNoteBlock == false)
        #expect(emptyNote.showsNoteBlock == false)
    }

    @Test("HighlightCardV3 onJump fires with the highlight's locator on tap")
    func highlightCardJumpFiresWithLocator() {
        let record = makeHighlightRecord(selectedText: "jump target")
        var jumped: Locator?
        let card = HighlightCardV3(
            theme: .paper, highlight: record,
            onJump: { jumped = $0 }
        )
        card.invokeJumpForTesting()
        #expect(jumped == record.locator)
    }

    @Test("HighlightCardV3 builds with a CJK passage and note")
    func highlightCardBuildsWithCJK() {
        let card = HighlightCardV3(
            theme: .dark,
            highlight: makeHighlightRecord(
                selectedText: "这是一段被高亮的文字", note: "我的笔记内容"
            ),
            onJump: { _ in }
        )
        _ = card.body
    }

    // MARK: - StandaloneNoteCard

    @Test("StandaloneNoteCard builds for every theme")
    func standaloneCardBuildsForEveryTheme() {
        for theme in ReaderThemeV2.allCases {
            let card = StandaloneNoteCard(
                theme: theme,
                note: makeAnnotationRecord(content: "a standalone note"),
                onJump: { _ in }
            )
            _ = card.body
        }
    }

    @Test("StandaloneNoteCard builds with CJK content")
    func standaloneCardBuildsWithCJK() {
        let card = StandaloneNoteCard(
            theme: .sepia,
            note: makeAnnotationRecord(content: "独立笔记，不依附于任何段落。"),
            onJump: { _ in }
        )
        _ = card.body
    }

    @Test("StandaloneNoteCard onJump fires with the annotation's locator on tap")
    func standaloneCardJumpFiresWithLocator() {
        let record = makeAnnotationRecord(content: "jump target")
        var jumped: Locator?
        let card = StandaloneNoteCard(
            theme: .paper, note: record,
            onJump: { jumped = $0 }
        )
        card.invokeJumpForTesting()
        #expect(jumped == record.locator)
    }
}
