// Purpose: Feature #61 WI-3 — one row of the Book Details sheet's
// Metadata card: a fixed-width label, a monospaced value, and an
// optional trailing mini-action (copy the fingerprint / reveal the
// file location). Pinned to `vreader-book-details.jsx`'s `MetaList`
// row.
//
// The mini-action's tap is wired in WI-4 (fingerprint copy / location
// reveal); WI-3 ships the rendered control with an inert handler.
//
// @coordinates-with: BookDetailsSheet.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-book-details.jsx`

#if canImport(UIKit)
import SwiftUI

/// One metadata row in the reader Book Details sheet.
struct BookDetailsMetadataRow: View {

    /// A metadata row's data — one element of the design's `MetaList`
    /// `rows` array. A value type so `BookDetailsSheet.metadataRows`
    /// (which composes them) is unit-testable.
    struct Model: Equatable, Identifiable {

        /// A trailing mini-action a row can carry.
        enum Accessory: Equatable {
            /// Copy the full value to the pasteboard — the Fingerprint row.
            case copy
            /// Reveal / share the file — the Location row.
            case reveal

            /// SF Symbol for the mini-button glyph.
            var systemImage: String {
                switch self {
                case .copy:   return "doc.on.doc"
                case .reveal: return "arrow.up.forward"
                }
            }

            /// VoiceOver label for the mini-button.
            var accessibilityLabel: String {
                switch self {
                case .copy:   return "Copy fingerprint"
                case .reveal: return "Reveal file location"
                }
            }
        }

        /// Stable identity — row labels are unique within the card.
        var id: String { label }
        /// Fixed-width leading label ("Format", "Size", …).
        let label: String
        /// The monospaced value text.
        let value: String
        /// Trailing mini-action, or `nil` for a plain display row.
        let accessory: Accessory?
    }

    let model: Model
    let theme: ReaderThemeV2
    /// Invoked when the trailing mini-action is tapped. Wired in WI-4;
    /// WI-3 passes an inert handler.
    let onAccessory: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(model.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 96, alignment: .leading)

            Text(model.value)
                .font(.system(size: 13.5, design: .monospaced))
                .foregroundStyle(Color(theme.inkColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let accessory = model.accessory {
                accessoryButton(accessory)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bookDetailsMetadataRow_\(model.label)")
    }

    /// The 26pt rounded mini-button — design `MetaList`'s `miniBtn`.
    private func accessoryButton(_ accessory: Model.Accessory) -> some View {
        Button(action: onAccessory) {
            Image(systemName: accessory.systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(theme.isDark
                            ? Color.white.opacity(0.06)
                            : Color.black.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessory.accessibilityLabel)
        .accessibilityIdentifier("bookDetailsMetadataAccessory_\(model.label)")
    }
}
#endif
