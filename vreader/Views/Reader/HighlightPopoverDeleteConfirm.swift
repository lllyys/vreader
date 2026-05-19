// Purpose: Feature #64 WI-4 — `HighlightPopoverDeleteConfirm`, the inline
// delete-confirmation sub-state of the unified highlight-action popover.
//
// Replaces the color + action rows in place when the card's `mode` is
// `.confirmingDelete`. Split into its own file from
// `HighlightActionCardSubviews.swift` to keep both files under the ~300-line
// guideline.
//
// Layout pinned to `dev-docs/designs/vreader-fidelity-v1/project/
// vreader-highlight-popover.jsx` (`HPDeleteConfirm`).
//
// @coordinates-with: HighlightActionCardView.swift, HighlightActionCardSubviews.swift,
//   HighlightPopoverAction.swift, ReaderThemeV2.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Inline delete-confirmation — replaces the color + action rows.
struct HighlightPopoverDeleteConfirm: View {
    let theme: ReaderThemeV2
    let onAction: (HighlightPopoverAction) -> Void

    private var dangerColor: Color {
        Color(theme.isDark
            ? UIColor(red: 0.91, green: 0.56, blue: 0.56, alpha: 1)
            : UIColor(red: 0.66, green: 0.23, blue: 0.23, alpha: 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Delete this highlight?")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(theme.inkColor))
                .padding(.bottom, 4)
            Text("The color, the note, and the underline come off the page. Can't be undone.")
                .font(.system(size: 11.5))
                .foregroundColor(Color(theme.subColor))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            HStack(spacing: 8) {
                Button {
                    onAction(.cancelEdit)
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(theme.inkColor))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(theme.ruleColor), lineWidth: 0.5)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("highlightPopoverCancelDelete")
                Button {
                    onAction(.confirmDelete)
                } label: {
                    Text("Delete")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(dangerColor))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("highlightPopoverConfirmDelete")
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(theme.ruleColor))
                .frame(height: 0.5)
        }
    }
}
#endif
