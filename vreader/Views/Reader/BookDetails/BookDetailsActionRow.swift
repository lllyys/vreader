// Purpose: Feature #61 WI-3 — one row of the Book Details sheet's
// Actions card: a leading icon chip, a label with an optional
// secondary line, and a trailing chevron. Pinned to
// `vreader-book-details.jsx`'s `ActionList` row.
//
// The row's tap is wired in WI-4 (cover-swap via the WI-2
// CoverPickCoordinator / share / export annotations); WI-3 ships the
// rendered control with an inert handler.
//
// @coordinates-with: BookDetailsSheet.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-book-details.jsx`

#if canImport(UIKit)
import SwiftUI

/// One action row in the reader Book Details sheet.
struct BookDetailsActionRow: View {

    /// An action row's data — one element of the design's `ActionList`
    /// `actions` array. A value type so `BookDetailsSheet.actionRows`
    /// (which composes them) is unit-testable.
    struct Model: Equatable, Identifiable {

        /// Which book-scoped action the row triggers.
        enum Kind: String, Equatable {
            /// Replace (or add) the book's custom cover.
            case cover
            /// Share the book file.
            case share
            /// Export the book's annotations.
            case exportAnnotations
            /// Feature #56 WI-14 — translate every chapter through the
            /// active AI provider and cache the results to disk.
            case translateBook
        }

        /// Stable identity — one row per kind.
        var id: String { kind.rawValue }
        let kind: Kind
        /// SF Symbol for the leading icon chip.
        let systemImage: String
        /// Primary label.
        let label: String
        /// Optional secondary line under the label.
        let sublabel: String?
    }

    let model: Model
    let theme: ReaderThemeV2
    /// Invoked when the row is tapped. Wired in WI-4; WI-3 passes an
    /// inert handler.
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                iconChip
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.label)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color(theme.inkColor))
                        .lineLimit(1)
                    if let sublabel = model.sublabel {
                        Text(sublabel)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(theme.subColor))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(theme.subColor))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bookDetailsAction_\(model.kind.rawValue)")
    }

    /// The 28pt rounded icon chip — design `ActionList`'s icon chip.
    private var iconChip: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(theme.isDark
                ? Color.white.opacity(0.05)
                : Color.black.opacity(0.04))
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: model.systemImage)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color(theme.inkColor))
            )
    }
}
#endif
