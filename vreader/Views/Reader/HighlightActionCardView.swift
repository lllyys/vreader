// Purpose: Feature #64 WI-4 — `HighlightActionCardView`, the SwiftUI
// realization of the unified highlight-action popover. One view, two outer
// shells: the anchored card (`.card`) and the bottom sheet (`.sheet`); the
// shared content subviews live in `HighlightActionCardSubviews.swift`.
//
// Layout pinned to `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-highlight-popover.jsx` (`HighlightActionCard` + `HighlightActionSheet`).
//
// Purely presentational — `mode`, `noteDraft`, and `pressedColor` all live in
// the parent (`HighlightPopoverModifier`), and user taps funnel through a
// single `(HighlightPopoverAction) -> Void`. The note editor is a *controlled*
// component (R1-6): the draft is `noteDraft` + `onDraftChange`, not a private
// `@State`, so a rapid second tap on a different highlight never shows the
// previous highlight's stale draft.
//
// @coordinates-with: HighlightActionCardSubviews.swift,
//   HighlightPopoverContent.swift, HighlightPopoverMode.swift,
//   HighlightPopoverAction.swift, HighlightPopoverModifier.swift,
//   ReaderThemeV2.swift, ReaderTypography.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// The unified highlight-action popover view.
struct HighlightActionCardView: View {
    let content: HighlightPopoverContent
    let theme: ReaderThemeV2
    /// The card's interaction sub-state.
    let mode: HighlightPopoverMode
    /// `.card` (anchored, with notch) or `.sheet` (bottom) outer shell.
    let form: HighlightPopoverForm
    /// Presenter-owned note-editor draft (R1-6 — a controlled component).
    let noteDraft: String
    /// Transient press feedback on a color circle.
    let pressedColor: NamedHighlightColor?
    let onAction: (HighlightPopoverAction) -> Void
    let onDraftChange: (String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        switch form {
        case .card:
            cardShell
        case .sheet:
            sheetShell
        }
    }

    // MARK: - Outer shells

    private var cardShell: some View {
        cardContent
            .frame(width: 320)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(surfaceColor)
                    .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 14)
            )
            .accessibilityIdentifier("highlightPopoverCard")
    }

    private var sheetShell: some View {
        VStack(spacing: 0) {
            // Drag handle.
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(theme.isDark
                    ? UIColor.white.withAlphaComponent(0.18)
                    : UIColor.black.withAlphaComponent(0.12)))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
            cardContent
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(surfaceColor)
        )
        .accessibilityIdentifier("highlightPopoverSheet")
    }

    // MARK: - Shared content

    @ViewBuilder
    private var cardContent: some View {
        VStack(spacing: 0) {
            HighlightPopoverMetaRow(content: content, theme: theme, onDismiss: onDismiss)
            HighlightPopoverExcerpt(content: content, theme: theme)

            if mode == .confirmingDelete {
                HighlightPopoverDeleteConfirm(theme: theme, onAction: onAction)
            } else {
                noteRegion
                if mode != .editing {
                    HighlightPopoverColorRow(
                        content: content, theme: theme,
                        pressedColor: pressedColor, onAction: onAction
                    )
                    HighlightPopoverActionRow(theme: theme, onAction: onAction)
                }
            }
        }
    }

    // MARK: - Note region (reading / empty / editing)

    @ViewBuilder
    private var noteRegion: some View {
        switch mode {
        case .editing:
            editingNote
        case .reading, .confirmingDelete:
            if content.isEmpty {
                emptyNote
            } else {
                readingNote
            }
        }
    }

    private var editingNote: some View {
        VStack(alignment: .leading, spacing: 0) {
            HighlightNoteDraftEditor(
                draft: noteDraft,
                theme: theme,
                onDraftChange: onDraftChange
            )
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                Button {
                    onAction(.cancelEdit)
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(theme.subColor))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("highlightPopoverEditCancel")
                Button {
                    onAction(.saveNote(noteDraft))
                } label: {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(theme.accentColor)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("highlightPopoverEditSave")
            }
            .padding(.top, 6)
        }
        .padding(EdgeInsets(top: 0, leading: 12, bottom: 10, trailing: 12))
    }

    private var emptyNote: some View {
        Button {
            onAction(.beginEdit)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                Text("Add a note…")
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 13)))
                    .italic()
            }
            .foregroundColor(Color(theme.subColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3]))
                    .foregroundColor(Color(theme.ruleColor))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(EdgeInsets(top: 0, leading: 12, bottom: 10, trailing: 12))
        .accessibilityIdentifier("highlightPopoverAddNote")
    }

    private var readingNote: some View {
        Button {
            onAction(.beginEdit)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(content.note ?? "")
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14)))
                    .foregroundColor(Color(theme.inkColor))
                    .lineLimit(6)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text("Tap to edit")
                        .font(.system(size: 10.5, weight: .semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundColor(Color(theme.subColor))
                    Spacer(minLength: 0)
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(Color(theme.subColor))
                }
            }
            .padding(EdgeInsets(top: 8, leading: 12, bottom: 10, trailing: 12))
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(theme.isDark
                        ? UIColor.white.withAlphaComponent(0.035)
                        : UIColor.black.withAlphaComponent(0.025)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(EdgeInsets(top: 0, leading: 12, bottom: 10, trailing: 12))
        .accessibilityIdentifier("highlightPopoverReadingNote")
    }

    // MARK: - Colors

    private var surfaceColor: Color {
        Color(theme.isDark
            ? UIColor(red: 0.165, green: 0.153, blue: 0.141, alpha: 1)   // #2a2724
            : UIColor(red: 0.988, green: 0.973, blue: 0.941, alpha: 1))  // #fcf8f0
    }
}

/// The inline note-editor textarea — a controlled `TextEditor`. The draft is
/// owned by the presenter (`HighlightPopoverModifier`) and flows in via
/// `draft` + out via `onDraftChange`, so a rapid highlight swap or a
/// successful save never shows a stale draft (R1-6).
struct HighlightNoteDraftEditor: View {
    let draft: String
    let theme: ReaderThemeV2
    let onDraftChange: (String) -> Void

    var body: some View {
        TextEditor(text: Binding(
            get: { draft },
            set: { onDraftChange($0) }
        ))
        .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14)))
        .foregroundColor(Color(theme.inkColor))
        .scrollContentBackground(.hidden)
        .frame(minHeight: 84, maxHeight: 132)
        .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10))
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(theme.isDark
                    ? UIColor.white.withAlphaComponent(0.05)
                    : UIColor.black.withAlphaComponent(0.035)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(theme.accentColor).opacity(0.27), lineWidth: 1)
        )
        .accessibilityIdentifier("highlightPopoverNoteEditor")
    }
}
#endif
