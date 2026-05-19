// Purpose: Feature #55 WI-4 — pins the visible-action contract and the
// swatch-color mapping for `NoteCalloutView` against the committed design
// bundle `dev-docs/designs/vreader-fidelity-v1/project/vreader-note-preview.jsx`.
//
// SwiftUI views are tested for behavior, not pixels (per .claude/rules/10-tdd.md).
// `NoteCalloutView`'s testable surface:
//   - `NoteCalloutAction` — the handoff-row action enum. The design's
//     `CalloutAction` row depicts Edit / Share / Open-in-panel; v1 ships
//     ONLY Share + Open-in-panel (Edit is the BLOCKED: needs-design slice,
//     plan §2.8; Delete is never in the design, §2.7.2). A regression that
//     adds Edit or Delete to v1, or reorders, fails here.
//   - `noteSwatchColor(for:)` — maps a stored highlight color name to the
//     meta-row swatch color. Covers the real stored palette
//     (yellow/green/blue/red/orange/purple), not just the design's 4-color
//     subset (plan §2.1.1).
//   - the empty-vs-note branch is driven by `NotePreviewContent.isEmpty`.

import Testing
import Foundation
import SwiftUI
import CoreGraphics
@testable import vreader

@Suite("Feature #55 WI-4 — NoteCalloutView contract")
struct NoteCalloutViewTests {

    static let fp = DocumentFingerprint(
        contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        fileByteCount: 1024, format: .epub
    )

    private static func content(note: String?, color: String = "yellow") -> NotePreviewContent {
        NotePreviewContent(
            id: UUID(), note: note, highlightedText: "an excerpt",
            colorName: color, createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceRect: CGRect(x: 1, y: 2, width: 30, height: 14)
        )
    }

    // MARK: - Handoff-action contract (v1 surface)

    @Test("v1 handoff row has exactly 2 actions")
    func handoffActionCount() {
        #expect(NoteCalloutAction.allCases.count == 2)
    }

    @Test("v1 handoff row is Share then Open-in-panel — Edit + Delete omitted")
    func handoffActionOrder() {
        #expect(NoteCalloutAction.allCases == [.share, .openInPanel])
    }

    @Test("no handoff action is an edit or delete affordance")
    func handoffActionsAreReadOnlyHandoffs() {
        // The v1 callout is read-only — the Edit slice is BLOCKED: needs-design,
        // Delete was never in the design. Guard against either being added.
        for action in NoteCalloutAction.allCases {
            #expect(action != .openInPanel || action == .openInPanel)  // tautology guard
        }
        // Concretely: the case set must be exactly {share, openInPanel}.
        let cases = Set(NoteCalloutAction.allCases)
        #expect(cases == [.share, .openInPanel])
    }

    @Test("each handoff action has a label and an SF symbol")
    func handoffActionLabelsAndSymbols() {
        #expect(NoteCalloutAction.share.label == "Share")
        #expect(NoteCalloutAction.openInPanel.label == "Open in panel")
        #expect(!NoteCalloutAction.share.systemImage.isEmpty)
        #expect(!NoteCalloutAction.openInPanel.systemImage.isEmpty)
    }

    @Test("each handoff action has a stable accessibility identifier")
    func handoffActionAccessibilityIdentifiers() {
        #expect(NoteCalloutAction.share.accessibilityIdentifier == "noteCalloutShare")
        #expect(NoteCalloutAction.openInPanel.accessibilityIdentifier == "noteCalloutOpenInPanel")
    }

    // MARK: - Swatch color mapping (real stored palette)

    @Test(arguments: ["yellow", "green", "blue", "red", "orange", "purple"])
    func swatchColorResolvesEveryStoredPaletteColor(_ name: String) {
        // Every color a highlight can actually be stored as must resolve to a
        // concrete swatch — not just the design's depicted 4 (plan §2.1.1).
        let color = NoteCalloutView.noteSwatchColor(for: name)
        // A resolved color is not the clear/no-op sentinel.
        #expect(color != Color.clear)
    }

    @Test("an unknown stored color falls back, not crash")
    func swatchColorUnknownColorFallsBack() {
        let color = NoteCalloutView.noteSwatchColor(for: "chartreuse-legacy-hex")
        #expect(color != Color.clear)
    }

    @Test("swatch mapping is case-insensitive on the stored name")
    func swatchColorCaseInsensitive() {
        #expect(NoteCalloutView.noteSwatchColor(for: "YELLOW")
            == NoteCalloutView.noteSwatchColor(for: "yellow"))
    }

    // MARK: - Empty-vs-note branch (driven by NotePreviewContent.isEmpty)

    @Test("a note-less content is the empty/no-note state")
    func emptyStateBranchForNilNote() {
        #expect(Self.content(note: nil).isEmpty == true)
    }

    @Test("a whitespace-only note is the empty/no-note state")
    func emptyStateBranchForWhitespaceNote() {
        #expect(Self.content(note: "   \n ").isEmpty == true)
    }

    @Test("a real note is the note state, not empty")
    func noteStateBranchForRealNote() {
        #expect(Self.content(note: "a real note").isEmpty == false)
    }

    // MARK: - Note line-count helper (callout-vs-sheet threshold input)

    @Test("note line count counts newline-separated lines")
    func noteLineCountCountsLines() {
        #expect(NoteCalloutView.noteLineCount(for: "one") == 1)
        #expect(NoteCalloutView.noteLineCount(for: "one\ntwo") == 2)
        #expect(NoteCalloutView.noteLineCount(for: "a\nb\nc\nd\ne\nf\ng") == 7)
    }

    @Test("note line count of nil / empty is zero")
    func noteLineCountNilOrEmpty() {
        #expect(NoteCalloutView.noteLineCount(for: nil) == 0)
        #expect(NoteCalloutView.noteLineCount(for: "") == 0)
    }

    @Test("a trailing newline does not add a phantom line")
    func noteLineCountTrailingNewline() {
        #expect(NoteCalloutView.noteLineCount(for: "one\ntwo\n") == 2)
    }
}
