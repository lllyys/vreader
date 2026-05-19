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
import UIKit
import CoreGraphics
@testable import vreader

/// Test-local hex → Color parser, mirroring the production file-private one
/// in `NoteCalloutView.swift` — lets the swatch tests assert exact-hex
/// equality. Kept here (not lifted to a shared helper) because only the
/// tests need to construct an expected color from a hex literal.
private extension Color {
    init(testHexString hex: String) {
        var trimmed = hex
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        let value = UInt32(trimmed, radix: 16) ?? 0
        self = Color(
            red: Double((value >> 16) & 0xff) / 255.0,
            green: Double((value >> 8) & 0xff) / 255.0,
            blue: Double(value & 0xff) / 255.0
        )
    }
}

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
        // Delete was never in the design. The case set must be EXACTLY
        // {share, openInPanel}: no edit/delete affordance, ever.
        let cases = Set(NoteCalloutAction.allCases)
        #expect(cases == [.share, .openInPanel])
        // No raw value collides with an edit/delete intent.
        for action in NoteCalloutAction.allCases {
            #expect(action.rawValue != "edit")
            #expect(action.rawValue != "delete")
        }
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

    /// The four designed colors must resolve to the EXACT committed design
    /// hex stops (`NamedHighlightColor.hex`) — a drift here breaks the
    /// visual contract against the design bundle.
    @Test(arguments: [
        ("yellow", "#f0d25a"),
        ("pink",   "#e88ca0"),
        ("green",  "#8cc88c"),
        ("blue",   "#8cb4e8"),
    ])
    func swatchColorMatchesDesignHexForDesignedColors(_ name: String, _ hex: String) {
        #expect(NoteCalloutView.noteSwatchColor(for: name) == Color(testHexString: hex))
    }

    /// The broader stored palette (not depicted in the design) must each map
    /// to their intended faithful hue — and crucially must NOT all collapse
    /// to the yellow fallback (plan §2.1.1).
    @Test(arguments: [
        ("red",    "#e08585"),
        ("orange", "#e8a85a"),
        ("purple", "#b48ce8"),
    ])
    func swatchColorMatchesIntendedHueForBroaderPalette(_ name: String, _ hex: String) {
        let resolved = NoteCalloutView.noteSwatchColor(for: name)
        #expect(resolved == Color(testHexString: hex))
        // Must be distinct from the yellow fallback — i.e. genuinely mapped.
        #expect(resolved != NoteCalloutView.noteSwatchColor(for: "yellow"))
    }

    @Test("an unknown stored color falls back exactly to the yellow swatch")
    func swatchColorUnknownColorFallsBackToYellow() {
        #expect(NoteCalloutView.noteSwatchColor(for: "chartreuse-legacy-hex")
            == NoteCalloutView.noteSwatchColor(for: "yellow"))
        #expect(NoteCalloutView.noteSwatchColor(for: "")
            == NoteCalloutView.noteSwatchColor(for: "yellow"))
    }

    @Test("swatch mapping is case-insensitive on the stored name")
    func swatchColorCaseInsensitive() {
        #expect(NoteCalloutView.noteSwatchColor(for: "YELLOW")
            == NoteCalloutView.noteSwatchColor(for: "yellow"))
        #expect(NoteCalloutView.noteSwatchColor(for: "Red")
            == NoteCalloutView.noteSwatchColor(for: "red"))
    }

    // MARK: - Display-mode branch (the view's empty-vs-note subtree decision)

    @Test("note-less content drives the empty display mode")
    func displayModeEmptyForNilNote() {
        #expect(NoteCalloutView.displayMode(for: Self.content(note: nil)) == .empty)
    }

    @Test("whitespace-only note drives the empty display mode")
    func displayModeEmptyForWhitespaceNote() {
        #expect(NoteCalloutView.displayMode(for: Self.content(note: "   \n ")) == .empty)
    }

    @Test("a real note drives the note display mode")
    func displayModeNoteForRealNote() {
        #expect(NoteCalloutView.displayMode(for: Self.content(note: "a real note")) == .note)
    }

    @Test("display mode tracks NotePreviewContent.isEmpty exactly")
    func displayModeTracksIsEmpty() {
        for note: String? in [nil, "", "  ", "real", "  padded  "] {
            let c = Self.content(note: note)
            let expected: NoteCalloutDisplayMode = c.isEmpty ? .empty : .note
            #expect(NoteCalloutView.displayMode(for: c) == expected)
        }
    }

    // MARK: - Render smoke (the view constructs for both states)

    @MainActor
    @Test("the callout view constructs for the empty state without crashing")
    func renderSmokeEmptyState() {
        let view = NoteCalloutView(
            content: Self.content(note: nil), theme: .paper,
            onAction: { _ in }, onDismiss: {}
        )
        // Hosting the view forces SwiftUI to evaluate `body` — a crash in the
        // empty-branch subtree surfaces here.
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        #expect(host.view != nil)
    }

    @MainActor
    @Test("the callout view constructs for the note state without crashing")
    func renderSmokeNoteState() {
        let view = NoteCalloutView(
            content: Self.content(note: "a note body"), theme: .paper,
            onAction: { _ in }, onDismiss: {}
        )
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        #expect(host.view != nil)
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

    /// Whitespace/newline-only bodies — these are the inputs most likely to
    /// diverge from `content.isEmpty` (which trims to empty) once the helper
    /// feeds the callout-vs-sheet decision. A spaces-only body is one
    /// non-empty visual line; a lone newline trims to zero lines.
    @Test("note line count for whitespace-only / newline-only bodies")
    func noteLineCountWhitespaceOnly() {
        #expect(NoteCalloutView.noteLineCount(for: "   ") == 1)   // one spaces line
        #expect(NoteCalloutView.noteLineCount(for: "\n") == 0)    // lone newline → 0
        #expect(NoteCalloutView.noteLineCount(for: " \n \n ") == 3)
    }
}
