// Purpose: Feature #62 WI-4 — the two annotation card views for
// `HighlightsSheet`'s unified card stream.
//
// The committed #860 design (`vreader-notes-unified.jsx`) renders two
// card kinds: `HighlightCardV3` (the passage card — a quoted highlight
// with an optional note block, visually identical to the v2 design) and
// `StandaloneNoteCard` (NEW — the note body is the hero; no quoted
// passage; a `Standalone` pill + a dashed accent rule distinguish it).
// `HighlightsSheet` switches on `AnnotationStreamItem` to pick the card.
//
// Both take a `ReaderThemeV2` and an `onJump` closure (the card `onJump`
// only navigates to the locator — editing a highlight's note is
// `HighlightActionPopover`'s job, feature #64).
//
// @coordinates-with: HighlightsSheet.swift, AnnotationStreamItem.swift,
//   ReaderThemeV2.swift, HighlightRecord.swift, AnnotationRecord.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-notes-unified.jsx`

import SwiftUI

/// The highlight-colour → swatch-colour map for `HighlightsSheet`'s
/// cards.
///
/// The committed #860 design (`vreader-notes-unified.jsx` `colorMap`)
/// depicts four swatch colours (yellow/green/blue/pink) with exact hex
/// stops. But the REAL stored highlight palette is broader —
/// red/orange/purple are also valid stored colour names. Mapping every
/// non-designed name to yellow would render a red/orange/purple
/// highlight with the wrong swatch + rule colour, a visible
/// data-fidelity regression. So this resolves the designed four to the
/// committed `NamedHighlightColor` hex stops, and the broader three to
/// their natural opaque hue — the same faithful-to-data strategy
/// `NoteCalloutView.noteSwatchColor` already established (rule 51
/// permits extending a designed swatch's data mapping). Unknown / empty
/// / legacy-hex values fall back to yellow — never `.clear`, never a
/// crash.
enum HighlightSwatch {
    static func color(for name: String) -> Color {
        let normalized = name.lowercased()
        // Designed four — pinned to the committed design hex stops.
        if let named = NamedHighlightColor.from(storageString: normalized),
           let color = Color(readerHexString: named.hex) {
            return color
        }
        // Broader stored palette the design did not depict.
        switch normalized {
        case "red":    return Color(readerHexString: "#e08585") ?? .red
        case "orange": return Color(readerHexString: "#e8a85a") ?? .orange
        case "purple": return Color(readerHexString: "#b48ce8") ?? .purple
        default:
            return Color(readerHexString: NamedHighlightColor.yellow.hex) ?? .yellow
        }
    }
}

// MARK: - HighlightCardV3

/// The passage card — a colour-swatch meta row, a serif-italic quoted
/// passage with a 2pt solid colour left-rule, and (when the highlight
/// carries a non-empty note) a note block beneath. JSX `HighlightCardV3`.
struct HighlightCardV3: View {
    let theme: ReaderThemeV2
    let highlight: HighlightRecord
    /// Meta sub-line — `chapter · p. N` — pre-composed by `HighlightsSheet`.
    let metaLabel: String
    let onJump: (Locator) -> Void

    init(
        theme: ReaderThemeV2,
        highlight: HighlightRecord,
        metaLabel: String = "",
        onJump: @escaping (Locator) -> Void
    ) {
        self.theme = theme
        self.highlight = highlight
        self.metaLabel = metaLabel
        self.onJump = onJump
    }

    /// True when the note block is part of the composition — the
    /// highlight carries a non-empty note (the design's `h.note` guard).
    var showsNoteBlock: Bool {
        highlight.note?.isEmpty == false
    }

    /// Test-only hook — invokes `onJump` with the highlight's locator.
    func invokeJumpForTesting() { onJump(highlight.locator) }

    private var swatch: Color { HighlightSwatch.color(for: highlight.color) }

    var body: some View {
        Button {
            onJump(highlight.locator)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                metaRow
                passage
                if showsNoteBlock, let note = highlight.note {
                    noteBlock(note)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(theme.ruleColor)).frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(swatch)
                .frame(width: 10, height: 10)
            Text(metaLabel)
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
            Spacer(minLength: 0)
            Text(Self.dateFormatter.string(from: highlight.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
        }
    }

    @ViewBuilder
    private var passage: some View {
        Text("\u{201C}\(highlight.selectedText)\u{201D}")
            .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14.5)))
            .italic()
            .foregroundStyle(Color(theme.inkColor))
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                Rectangle().fill(swatch).frame(width: 2)
            }
    }

    @ViewBuilder
    private func noteBlock(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "note.text")
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
                .padding(.top, 2)
            Text(note)
                .font(.system(size: 13))
                .foregroundStyle(Color(theme.subColor))
                .lineSpacing(2)
        }
        .padding(.leading, 14)
    }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()
}

// MARK: - StandaloneNoteCard

/// The standalone-note card — a note-glyph pictogram meta row with a
/// `Standalone` pill, and the note body as the hero behind a 2pt DASHED
/// accent left-rule (no colour swatch — no highlight backs it). JSX
/// `StandaloneNoteCard`.
struct StandaloneNoteCard: View {
    let theme: ReaderThemeV2
    let note: AnnotationRecord
    /// Meta sub-line — `chapter · p. N` — pre-composed by `HighlightsSheet`.
    let metaLabel: String
    let onJump: (Locator) -> Void

    init(
        theme: ReaderThemeV2,
        note: AnnotationRecord,
        metaLabel: String = "",
        onJump: @escaping (Locator) -> Void
    ) {
        self.theme = theme
        self.note = note
        self.metaLabel = metaLabel
        self.onJump = onJump
    }

    /// Test-only hook — invokes `onJump` with the annotation's locator.
    func invokeJumpForTesting() { onJump(note.locator) }

    var body: some View {
        Button {
            onJump(note.locator)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                metaRow
                body_
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Color(theme.ruleColor)).frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var metaRow: some View {
        HStack(spacing: 8) {
            // Standalone pictogram — a small filled note glyph in an
            // accent-tinted rounded square (no colour swatch).
            Image(systemName: "note.text")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color(theme.accentColor))
                .frame(width: 12, height: 12)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(theme.accentColor).opacity(0.13))
                )
            Text(metaLabel)
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
            Text("Standalone")
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color(theme.subColor))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    Capsule().fill(Color.primary.opacity(theme.isDark ? 0.06 : 0.05))
                )
            Spacer(minLength: 0)
            Text(HighlightCardV3.dateFormatter.string(from: note.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
        }
    }

    @ViewBuilder
    private var body_: some View {
        Text(note.content)
            .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14.5)))
            .foregroundStyle(Color(theme.inkColor))
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 12)
            .overlay(alignment: .leading) {
                // Dashed accent rule — distinguishes a standalone note
                // from a highlight's solid colour rule. A top-to-bottom
                // dashed line, 2pt wide.
                DashedVerticalRule(color: Color(theme.accentColor).opacity(0.53))
                    .frame(width: 2)
            }
    }
}

// MARK: - Dashed vertical rule

/// A 2pt top-to-bottom dashed line — the standalone-note card's accent
/// left-rule (the design's `borderLeft: 2px dashed`).
private struct DashedVerticalRule: View {
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 1, y: 0))
                p.addLine(to: CGPoint(x: 1, y: geo.size.height))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        }
    }
}
