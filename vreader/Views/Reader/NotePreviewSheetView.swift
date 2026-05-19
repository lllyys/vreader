// Purpose: Feature #55 WI-5 — `NotePreviewSheetView`, the SwiftUI realization
// of the committed design bundle's `NotePreviewSheet`
// (`dev-docs/designs/vreader-fidelity-v1/project/vreader-note-preview.jsx`).
//
// The bottom-anchored fallback form of the note preview — used for:
//   - very long notes (more lines than the callout's threshold),
//   - the VoiceOver path,
//   - Foliate/AZW3 (no `sourceRect` to anchor a callout to — plan §2.9).
//
// Same `NotePreviewContent` input as `NoteCalloutView`, rendered with more
// room: a 2-line italic-serif excerpt with the color-tinted left rule and the
// note body at the larger sheet type size (17pt).
//
// v1 ships read-only preview only. The design's sheet footer depicts a Done +
// "Edit note" pair; v1 renders **Done only** — Edit is the `BLOCKED:
// needs-design` slice (issue #914, plan §2.6 / §2.8). A handoff row of Share
// + Open-in-panel (the same `NoteCalloutAction` the callout uses) sits above
// the footer so the sheet has parity with the callout's reachable actions.
//
// Key decisions:
// - Reuses `NoteCalloutView.noteSwatchColor(for:)` for the swatch — the same
//   real-stored-palette mapping; no third copy of the color logic.
// - `NotePreviewSheetDisplayMode` + `NotePreviewSheetView.displayMode(for:)`
//   make the empty-vs-note branch unit-testable without a SwiftUI render,
//   mirroring `NoteCalloutView`.
// - Presented by `NotePreviewModifier` via SwiftUI `.sheet` — the sheet form
//   needs no rect anchor, so it does not go through the UIKit presenter.
//
// @coordinates-with: NoteCalloutView.swift, NoteCalloutAction.swift,
//   NotePreviewContent.swift, NotePreviewPresenter.swift, ReaderThemeV2.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Which subtree the sheet renders — extracted so the empty-vs-note branch is
/// unit-testable without a SwiftUI render.
enum NotePreviewSheetDisplayMode: Equatable {
    case empty
    case note
}

/// Bottom-sheet note preview — the fallback form of the design's note
/// preview. Purely presentational; the parent owns presentation state.
struct NotePreviewSheetView: View {

    /// The note-preview content to render.
    let content: NotePreviewContent

    /// The reader theme driving ink / sub / rule / accent colors.
    let theme: ReaderThemeV2

    /// Funnel for the handoff-row actions (Share / Open-in-panel).
    let onAction: (NoteCalloutAction) -> Void

    /// Fired when the user taps Done (or dismisses the sheet by drag).
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            title
            excerptRow
            switch Self.displayMode(for: content) {
            case .empty:
                emptyStateRow
            case .note:
                noteBody
            }
            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sheetBackground)
        .accessibilityIdentifier("notePreviewSheet")
    }

    // MARK: - Subviews

    private var title: some View {
        Text(content.isEmpty ? "Highlight" : "Note")
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.6)
            .foregroundColor(Color(theme.subColor))
            .textCase(.uppercase)
            .padding(.bottom, 14)
    }

    @ViewBuilder private var excerptRow: some View {
        let excerpt = content.highlightedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !excerpt.isEmpty {
            Text("\u{201C}\(excerpt)\u{201D}")
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 13)))
                .italic()
                .foregroundColor(Color(theme.subColor))
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(NoteCalloutView.noteSwatchColor(for: content.colorName))
                        .frame(width: 2)
                }
                .padding(.bottom, 18)
                .accessibilityIdentifier("notePreviewSheetExcerpt")
        }
    }

    /// The note body at the roomier sheet type size (design: 17pt).
    private var noteBody: some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(content.note ?? "")
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 17)))
                .foregroundColor(Color(theme.inkColor))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier("notePreviewSheetBody")
    }

    /// The empty/no-note state — acknowledges the tap without an "Add one…"
    /// affordance (that opens the BLOCKED: needs-design editor).
    private var emptyStateRow: some View {
        Text("No note attached.")
            .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 16)))
            .italic()
            .foregroundColor(Color(theme.subColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("notePreviewSheetEmptyState")
    }

    /// Handoff actions + the Done footer. v1: Done only (Edit is the
    /// BLOCKED: needs-design slice); Share + Open-in-panel above it for
    /// parity with the callout.
    private var footer: some View {
        VStack(spacing: 0) {
            if !content.isEmpty {
                HStack(spacing: 8) {
                    ForEach(NoteCalloutAction.allCases, id: \.self) { action in
                        Button { onAction(action) } label: {
                            Label(action.label, systemImage: action.systemImage)
                                .font(Font(ReaderTypography.body(for: .inter, size: 13)))
                                .foregroundColor(Color(theme.inkColor))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier(action.accessibilityIdentifier)
                        if action != NoteCalloutAction.allCases.last {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 18)
            }
            Divider()
                .background(Color(theme.ruleColor))
                .padding(.top, 14)
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Text("Done")
                        .font(Font(ReaderTypography.body(for: .inter, size: 13)))
                        .fontWeight(.medium)
                        .foregroundColor(Color(theme.subColor))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("notePreviewSheetDone")
            }
            .padding(.top, 14)
        }
    }

    // MARK: - Theme-aware colors

    private var sheetBackground: Color {
        if theme.isDark {
            return Color(readerHexString: "#2a2724") ?? Color(theme.chromeColor)
        } else {
            return Color(readerHexString: "#fcf8f0") ?? Color(theme.chromeColor)
        }
    }

    // MARK: - Testable statics

    /// The subtree the sheet renders for `content`. Exposed `static` so the
    /// empty-vs-note branch is unit-tested without a SwiftUI render.
    static func displayMode(for content: NotePreviewContent) -> NotePreviewSheetDisplayMode {
        content.isEmpty ? .empty : .note
    }
}
#endif
