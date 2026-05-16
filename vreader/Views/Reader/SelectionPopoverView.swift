// Purpose: Feature #60 WI-7a — SwiftUI overlay rendering the
// new-selection popover that will replace the legacy 4-item
// UIMenu (Highlight / Add Note / Define / Translate) in the
// long-press flow. Visual layout pinned to
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx:438-495`:
//
//   ┌──────────────────────────────────────────┐
//   │ "<selection preview>"                    │  ← italic serif, sub, 2-line clamp
//   │ ⬤ ⬤ ⬤ ⬤              ✕                   │  ← 4 color circles, close
//   │ ─────────────────────────────────         │  ← rule divider
//   │ [Note] [Translate] [Ask AI] [Read]       │  ← 4 actions; Ask AI is accent
//   └──────────────────────────────────────────┘
//
// **Production wiring is deferred to WI-7b.** This file ships the
// view body only — long-press paths in TXT/MD/EPUB still drive the
// legacy `TXTBridgeShared.buildReaderEditMenu` UIMenu. WI-7b
// replaces that path with a presenter that mounts this view.
//
// @coordinates-with: SelectionPopoverActionRow.swift,
//   SelectionPopoverAction.swift, NamedHighlightColor.swift,
//   ReaderThemeV2.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// New-selection popover. The view is purely presentational — all
/// state (selection text, currently-presented flag) lives in the
/// parent, and user taps are funnelled through a single
/// `(SelectionPopoverAction) -> Void` callback.
struct SelectionPopoverView: View {
    /// The text excerpt the user has selected. Rendered as a 2-line
    /// italic-serif preview at the top of the popover so the user
    /// recognises which selection they're acting on. Pass an empty
    /// string to hide the preview row.
    let selectionText: String

    /// The reader theme that drives ink / sub / rule / accent
    /// colors. Pass the same `ReaderThemeV2` the rest of the reader
    /// chrome is using — this view does not project across the
    /// legacy `ReaderTheme.asV2` boundary itself; the caller does.
    let theme: ReaderThemeV2

    /// Single funnel for every user tap. The callback receives a
    /// `SelectionPopoverAction` (WI-3 dispatch enum) describing
    /// which row was tapped. The caller is responsible for routing
    /// the action to the highlight / note / translate / AI / TTS
    /// pipelines.
    let onAction: (SelectionPopoverAction) -> Void

    /// Fired when the user taps the close `X` button. Distinct from
    /// the action callback so the parent can dismiss without
    /// triggering any side-effect.
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Codex Gate 4 round 1 (Low): whitespace-only selections
            // should not render a quoted "empty" preview row.
            if !selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                selectionPreview
            }
            colorRow
            Divider()
                .background(Color(theme.ruleColor))
            actionRow
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(popoverBackground)
                .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 10)
        )
        .accessibilityIdentifier("selectionPopover")
    }

    // MARK: - Subviews

    private var selectionPreview: some View {
        // Source Serif 4 italic per the design bundle; routes through
        // `ReaderTypography` so when WI-1b bundles the binary the
        // popover picks it up automatically. Without the binary, the
        // registry returns Georgia → system serif fallback.
        Text("\u{201C}\(selectionText)\u{201D}")
            .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 13)))
            .italic()
            .foregroundColor(Color(theme.subColor))
            .lineLimit(2)
            .truncationMode(.tail)
            .accessibilityIdentifier("selectionPopoverPreview")
    }

    private var colorRow: some View {
        HStack(spacing: 6) {
            ForEach(NamedHighlightColor.allCases, id: \.self) { color in
                Button {
                    onAction(.highlight(color))
                } label: {
                    // Codex Gate 4 round 1 (Low): expand hit target to
                    // 36×36 minimum while keeping the visible swatch at
                    // 30×30. `contentShape` makes the surrounding clear
                    // frame tappable.
                    Circle()
                        .fill(Color(hexString: color.hex) ?? .yellow)
                        .frame(width: 30, height: 30)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.4), lineWidth: 2)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 1)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(color.rawValue.capitalized) highlight")
                .accessibilityIdentifier("selectionPopoverColor-\(color.rawValue)")
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(theme.subColor))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("selectionPopoverClose")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            ForEach(SelectionPopoverActionRow.allCases, id: \.self) { row in
                Button {
                    onAction(row.dispatchAction)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: row.systemImage)
                            .font(.system(size: 18, weight: .regular))
                        // Inter (UI chrome) via ReaderTypography so the
                        // label picks up WI-1b's bundled face when it
                        // lands; falls back to system sans otherwise.
                        Text(row.label)
                            .font(Font(ReaderTypography.body(for: .inter, size: 10.5)))
                            .fontWeight(.medium)
                    }
                    .foregroundColor(actionForeground(for: row))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background(actionBackground(for: row))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(row.accessibilityIdentifier)
            }
        }
    }

    // MARK: - Theme-aware colors

    private var popoverBackground: Color {
        // Design ships hardcoded #2a2724 (dark) and #fcf8f0 (light)
        // for the popover surface, distinct from the reader chrome
        // tint so the popover reads as a floating element. Map
        // through V2's `isDark` predicate so all 5 themes pick the
        // appropriate surface.
        if theme.isDark {
            return Color(hexString: "#2a2724") ?? Color(theme.chromeColor)
        } else {
            return Color(hexString: "#fcf8f0") ?? Color(theme.chromeColor)
        }
    }

    private func actionForeground(for row: SelectionPopoverActionRow) -> Color {
        row.isAccent ? .white : Color(theme.inkColor)
    }

    private func actionBackground(for row: SelectionPopoverActionRow) -> Color {
        row.isAccent ? Color(theme.accentColor) : Color.clear
    }
}

// MARK: - Hex → SwiftUI Color (file-scoped helper)

private extension Color {
    /// Parses a hex string `#RRGGBB` (with optional alpha as
    /// `#RRGGBBAA`) into a SwiftUI `Color`. Returns nil for any
    /// malformed input — callers decide their fallback.
    ///
    /// Kept file-private because the WI-7a deliverable doesn't need
    /// a project-wide hex utility. Lift this to a shared `Color+Hex`
    /// helper only when a second call site appears.
    init?(hexString: String) {
        var trimmed = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6 || trimmed.count == 8,
              let value = UInt32(trimmed, radix: 16) else {
            return nil
        }
        let r, g, b, a: UInt32
        if trimmed.count == 6 {
            r = (value >> 16) & 0xff
            g = (value >> 8) & 0xff
            b = value & 0xff
            a = 0xff
        } else {
            r = (value >> 24) & 0xff
            g = (value >> 16) & 0xff
            b = (value >> 8) & 0xff
            a = value & 0xff
        }
        self = Color(
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }
}
#endif
