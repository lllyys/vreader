// Purpose: Feature #55 WI-4 — `NoteCalloutView`, the SwiftUI realization of
// the committed design bundle's `NoteCallout`
// (`dev-docs/designs/vreader-fidelity-v1/project/vreader-note-preview.jsx`).
//
// The anchored card a tap-on-annotated-text gesture reveals: a meta row
// (color swatch + "NOTE"/"HIGHLIGHT" label + date + dismiss ×), a one-line
// italic-serif excerpt of the highlighted passage with a color-tinted left
// rule, the note body as the hero (Source Serif 4, scrollable, capped at the
// design's 180pt), the empty/no-note state, and a handoff row.
//
// v1 ships read-only preview only:
//   - Handoff row = Share + Open-in-panel (`NoteCalloutAction`). The design's
//     `CalloutAction` row also depicts Edit; Edit is a `BLOCKED: needs-design`
//     slice (issue #914, plan §2.8) and is omitted. Delete was never in the
//     design (plan §2.7.2) and is not added. Rendering a depicted 3-button
//     row with 2 of its buttons is narrower than the design — rule 51 permits.
//   - No inline editing state.
//
// Key decisions:
// - The view is purely presentational — all state lives in the parent; user
//   taps funnel through `onAction` / `onDismiss`. Mirrors `SelectionPopoverView`.
// - The swatch-color mapper covers the REAL stored highlight palette
//   (yellow/green/blue/red/orange/purple — `HighlightListView.highlightColor`),
//   not just the design's depicted 4-color subset (plan §2.1.1). A
//   faithful-to-data extension: the swatch surface is designed, only the
//   color set widens to what users actually have.
// - `noteSwatchColor(for:)` and `noteLineCount(for:)` are `static` so the
//   color contract and the line-count helper (the callout-vs-sheet decision
//   input) are unit-testable with no SwiftUI render.
// - Theming flows through `ReaderThemeV2` — light/dark parity falls out.
//
// @coordinates-with: NoteCalloutAction.swift, NotePreviewContent.swift,
//   ReaderThemeV2.swift, ReaderTypography.swift, SelectionPopoverView.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Which subtree the callout renders below the meta + excerpt rows.
/// Extracted so the empty-vs-note branch decision is unit-testable without a
/// SwiftUI render — the `body` switches on `displayMode`.
enum NoteCalloutDisplayMode: Equatable {
    /// No note body — the empty/no-note state ("No note attached.").
    case empty
    /// A note body — the note-body hero + the handoff row.
    case note
}

/// Anchored note-preview card — the SwiftUI realization of the design's
/// `NoteCallout`. Purely presentational; the parent owns presentation state.
struct NoteCalloutView: View {

    /// The note-preview content to render.
    let content: NotePreviewContent

    /// The reader theme driving ink / sub / rule / accent colors. Pass the
    /// same `ReaderThemeV2` the rest of the reader chrome uses.
    let theme: ReaderThemeV2

    /// Funnel for the handoff-row actions (Share / Open-in-panel).
    let onAction: (NoteCalloutAction) -> Void

    /// Fired when the user taps the dismiss `×` (or the surrounding scrim,
    /// which the presenter owns). Distinct from `onAction` so the parent can
    /// dismiss with no side effect.
    let onDismiss: () -> Void

    /// The design's note-body `maxHeight` — past this the body scrolls.
    private static let bodyMaxHeight: CGFloat = 180

    /// Which subtree to render — the empty/no-note state or the note hero +
    /// handoff row. Driven by `content.isEmpty`. Unit-tested via
    /// `NoteCalloutView.displayMode(for:)`.
    private var displayMode: NoteCalloutDisplayMode {
        Self.displayMode(for: content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            metaRow
            excerptRow
            switch displayMode {
            case .empty:
                emptyStateRow
            case .note:
                noteBody
                Divider().background(Color(theme.ruleColor))
                handoffRow
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardBackground)
                .shadow(color: .black.opacity(0.28), radius: 20, x: 0, y: 12)
        )
        .accessibilityIdentifier("noteCallout")
    }

    // MARK: - Subviews

    private var metaRow: some View {
        HStack(spacing: 8) {
            // Color swatch — resolved from the real stored palette.
            RoundedRectangle(cornerRadius: 2)
                .fill(Self.noteSwatchColor(for: content.colorName))
                .frame(width: 8, height: 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Self.noteSwatchColor(for: content.colorName).opacity(0.2),
                                lineWidth: 2)
                )
            Text(content.isEmpty ? "HIGHLIGHT" : "NOTE")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(Color(theme.subColor))
            Text("· \(Self.dateText(content.createdAt))")
                .font(.system(size: 11))
                .foregroundColor(Color(theme.subColor).opacity(0.7))
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(theme.subColor))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Color(theme.ruleColor).opacity(0.5)))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
            .accessibilityIdentifier("noteCalloutDismiss")
        }
        .padding(.horizontal, 14)
        .padding(.top, 11)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var excerptRow: some View {
        let excerpt = content.highlightedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !excerpt.isEmpty {
            Text("\u{201C}\(excerpt)\u{201D}")
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 11.5)))
                .italic()
                .foregroundColor(Color(theme.subColor))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Self.noteSwatchColor(for: content.colorName))
                        .frame(width: 2)
                }
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.bottom, 10)
                .accessibilityIdentifier("noteCalloutExcerpt")
        }
    }

    /// The note body — the hero. Source Serif 4, scrollable, capped at 180pt.
    private var noteBody: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(content.note ?? "")
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 15)))
                .foregroundColor(Color(theme.inkColor))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: Self.bodyMaxHeight)
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .accessibilityIdentifier("noteCalloutBody")
    }

    /// The empty/no-note state — the design's "No note attached." treatment.
    /// v1 has no "Add one…" affordance (that opens the BLOCKED: needs-design
    /// editor); the state still acknowledges the tap so it does not feel broken.
    private var emptyStateRow: some View {
        Text("No note attached.")
            .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14)))
            .italic()
            .foregroundColor(Color(theme.subColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 14)
            .accessibilityIdentifier("noteCalloutEmptyState")
    }

    private var handoffRow: some View {
        HStack(spacing: 4) {
            ForEach(NoteCalloutAction.allCases, id: \.self) { action in
                Button {
                    onAction(action)
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: action.systemImage)
                            .font(.system(size: 15, weight: .regular))
                        Text(action.label)
                            .font(Font(ReaderTypography.body(for: .inter, size: 10)))
                            .fontWeight(.medium)
                            .foregroundColor(Color(theme.subColor))
                    }
                    .foregroundColor(Color(theme.inkColor))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(action.accessibilityIdentifier)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    // MARK: - Theme-aware colors

    private var cardBackground: Color {
        // Design ships hardcoded #2a2724 (dark) / #fcf8f0 (light) for the
        // callout surface — a floating element distinct from reader chrome.
        if theme.isDark {
            return Color(hexString: "#2a2724") ?? Color(theme.chromeColor)
        } else {
            return Color(hexString: "#fcf8f0") ?? Color(theme.chromeColor)
        }
    }

    // MARK: - Testable statics

    /// The subtree the callout renders for `content` — the empty/no-note
    /// state when the content has no note body, the note hero + handoff row
    /// otherwise. The `body`'s branch switches on this; exposed `static` so
    /// the branch decision is unit-tested without a SwiftUI render.
    static func displayMode(for content: NotePreviewContent) -> NoteCalloutDisplayMode {
        content.isEmpty ? .empty : .note
    }

    /// Resolves a stored highlight color name to the meta-row swatch color.
    ///
    /// Covers the REAL stored palette — `HighlightListView.highlightColor`
    /// handles yellow/green/blue/red/orange/purple — not just the design's
    /// depicted four. The four designed colors use the design's exact hex
    /// stops (`NamedHighlightColor.hex`); the broader three
    /// (red/orange/purple) map to their natural opaque hue. An unrecognized
    /// value falls back to yellow — never `.clear`, never a crash.
    static func noteSwatchColor(for storedColorName: String) -> Color {
        let normalized = storedColorName.lowercased()
        // Designed four — pinned to the committed design hex stops.
        if let named = NamedHighlightColor.from(storageString: normalized),
           let color = Color(hexString: named.hex) {
            return color
        }
        // Broader stored palette the design did not depict, mapped to a
        // faithful hue so a red/orange/purple highlight still gets its swatch.
        switch normalized {
        case "red":    return Color(hexString: "#e08585") ?? .red
        case "orange": return Color(hexString: "#e8a85a") ?? .orange
        case "purple": return Color(hexString: "#b48ce8") ?? .purple
        default:
            // Legacy hex / unknown / empty — fall back to the yellow swatch.
            return Color(hexString: NamedHighlightColor.yellow.hex) ?? .yellow
        }
    }

    /// Counts the newline-separated lines in a note body — the input the
    /// callout-vs-sheet decision (`NotePreviewPresenter.form`) reads to pick
    /// the roomier sheet for a long note. `nil`/empty → 0; a trailing newline
    /// does not add a phantom line.
    static func noteLineCount(for note: String?) -> Int {
        guard let note, !note.isEmpty else { return 0 }
        // Drop a single trailing newline so "a\nb\n" counts as 2, not 3.
        var body = note
        if body.hasSuffix("\n") { body.removeLast() }
        if body.isEmpty { return 0 }
        return body.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    // MARK: - Private helpers

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

// MARK: - Hex → SwiftUI Color (file-scoped helper)

private extension Color {
    /// Parses `#RRGGBB` / `#RRGGBBAA` into a `Color`. Returns nil for
    /// malformed input. File-private — lift to a shared helper only when a
    /// third call site appears (`SelectionPopoverView` has its own copy).
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
