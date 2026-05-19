// Purpose: Feature #64 WI-4 — the shared subviews of the unified
// highlight-action popover: meta row, excerpt strip, note region (reading /
// empty / editing), color row, action row, delete-confirmation.
//
// `HighlightActionCardView` (the outer shells — anchored card + bottom sheet)
// composes these. Split into their own file because `HighlightActionCardView`
// + these subviews together exceed the ~300-line guideline.
//
// Layout pinned to the committed design bundle
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-highlight-popover.jsx`
// (`HPMetaRow` / `HPExcerpt` / `HPNoteRegion` / `HPColorRow` / `HPActionRow` /
// `HPDeleteConfirm`).
//
// All subviews are purely presentational — every piece of state (`mode`,
// `noteDraft`, `pressedColor`) lives in the parent; user taps funnel through
// a single `(HighlightPopoverAction) -> Void` callback.
//
// @coordinates-with: HighlightActionCardView.swift, HighlightPopoverContent.swift,
//   HighlightPopoverMode.swift, HighlightPopoverAction.swift,
//   NamedHighlightColor.swift, ReaderThemeV2.swift, ReaderTypography.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

// MARK: - Swatch color resolution

/// Resolves a stored highlight color name to the popover's swatch `Color`.
/// The 4 named picker colors map to `NamedHighlightColor.hex`; any legacy /
/// unknown value (older hex, a future custom color) falls back to yellow —
/// mirroring `HighlightPaintColor` / `FoliateHighlightRenderer.foliateColor`.
enum HighlightPopoverSwatch {
    static func color(for storedName: String) -> Color {
        let named = NamedHighlightColor.from(storageString: storedName) ?? .yellow
        return Color(readerHexString: named.hex) ?? .yellow
    }
}

// MARK: - Meta row

/// Color swatch · "HIGHLIGHT" label · optional chapter/date · close ✕.
struct HighlightPopoverMetaRow: View {
    let content: HighlightPopoverContent
    let theme: ReaderThemeV2
    let onDismiss: () -> Void

    private var metaText: String? {
        var parts: [String] = []
        if let chapter = content.chapter, !chapter.isEmpty { parts.append(chapter) }
        parts.append(Self.dateFormatter.string(from: content.createdAt))
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(HighlightPopoverSwatch.color(for: content.colorName))
                .frame(width: 9, height: 9)
            Text("Highlight")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundColor(Color(theme.subColor))
            if let metaText {
                Text("· \(metaText)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(theme.subColor).opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(theme.subColor))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(
                            Color(theme.isDark
                                ? UIColor.white.withAlphaComponent(0.08)
                                : UIColor.black.withAlphaComponent(0.05))
                        )
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("highlightPopoverClose")
        }
        .padding(EdgeInsets(top: 11, leading: 14, bottom: 8, trailing: 12))
    }
}

// MARK: - Excerpt strip

/// The highlighted passage — italic serif, colored left bar, 2-line clamp.
struct HighlightPopoverExcerpt: View {
    let content: HighlightPopoverContent
    let theme: ReaderThemeV2

    var body: some View {
        if !content.highlightedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(HighlightPopoverSwatch.color(for: content.colorName))
                    .frame(width: 3)
                Text("\u{201C}\(content.highlightedText)\u{201D}")
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 12.5)))
                    .italic()
                    .foregroundColor(Color(theme.inkColor).opacity(0.85))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("highlightPopoverExcerpt")
            }
            .padding(EdgeInsets(top: 0, leading: 14, bottom: 10, trailing: 14))
        }
    }
}

// MARK: - Color row

/// The 4-color palette + selected ring + transient press feedback.
struct HighlightPopoverColorRow: View {
    let content: HighlightPopoverContent
    let theme: ReaderThemeV2
    let pressedColor: NamedHighlightColor?
    let onAction: (HighlightPopoverAction) -> Void

    private var currentColor: NamedHighlightColor {
        NamedHighlightColor.from(storageString: content.colorName) ?? .yellow
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(NamedHighlightColor.allCases, id: \.self) { color in
                colorButton(color)
            }
            Spacer(minLength: 0)
            Text("Color")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundColor(Color(theme.subColor))
        }
        .padding(EdgeInsets(top: 4, leading: 14, bottom: 10, trailing: 14))
    }

    private func colorButton(_ color: NamedHighlightColor) -> some View {
        let isCurrent = color == currentColor
        let isPressed = color == pressedColor
        return Button {
            onAction(.changeColor(color))
        } label: {
            Circle()
                .fill(Color(readerHexString: color.hex) ?? .yellow)
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().stroke(
                        isCurrent ? Color(theme.accentColor) : Color.white.opacity(0.45),
                        lineWidth: isCurrent ? 2.5 : 2
                    )
                )
                .overlay(
                    Group {
                        if isCurrent {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.black.opacity(0.55))
                        }
                    }
                )
                .scaleEffect(isPressed ? 0.94 : (isCurrent ? 1.06 : 1.0))
                .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(color.rawValue.capitalized) highlight")
        .accessibilityIdentifier("highlightPopoverColor-\(color.rawValue)")
    }
}

// MARK: - Action row

/// Copy · Share · Delete — destructive ink on Delete only.
struct HighlightPopoverActionRow: View {
    let theme: ReaderThemeV2
    let onAction: (HighlightPopoverAction) -> Void

    private var dangerColor: Color {
        Color(theme.isDark
            ? UIColor(red: 0.91, green: 0.56, blue: 0.56, alpha: 1)
            : UIColor(red: 0.66, green: 0.23, blue: 0.23, alpha: 1))
    }

    var body: some View {
        HStack(spacing: 4) {
            actionButton("Copy", systemImage: "doc.on.doc",
                         tint: Color(theme.inkColor), action: .copy,
                         identifier: "highlightPopoverCopy")
            actionButton("Share", systemImage: "square.and.arrow.up",
                         tint: Color(theme.inkColor), action: .share,
                         identifier: "highlightPopoverShare")
            actionButton("Delete", systemImage: "trash",
                         tint: dangerColor, action: .requestDelete,
                         identifier: "highlightPopoverDelete")
        }
        .padding(EdgeInsets(top: 6, leading: 6, bottom: 8, trailing: 6))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(theme.ruleColor))
                .frame(height: 0.5)
        }
    }

    private func actionButton(
        _ label: String, systemImage: String, tint: Color,
        action: HighlightPopoverAction, identifier: String
    ) -> some View {
        Button {
            onAction(action)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundColor(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

#endif
