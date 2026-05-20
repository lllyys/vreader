// Purpose: Feature #56 WI-14 — the "Translate entire book…" action row
// for the Book Details sheet Actions card. Status-aware:
//   - idle      → "Pre-translate every chapter to {Chinese}"
//   - running   → spinner + "Translating to {Chinese} · {done}/{total} chapters"
//   - translated→ check + "Translated to {Chinese} · {total}/{total} chapters"
//   - paused    → "Paused at {done}/{total}" (failed phase, see VM)
//
// Pinned to the committed design bundle:
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`
// (`TranslateBookActionRow` — drop-in row for Book Details > Actions).
//
// @coordinates-with: BookTranslationViewModel.swift,
//   BookTranslationProgress.swift, BookDetailsActionRow.swift (mirrors
//   layout), ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`

#if canImport(UIKit)
import SwiftUI

/// One row in the Book Details Actions card — drives the global
/// translate-entire-book flow. Visual state mirrors the design's
/// `TranslateBookActionRow` (idle / running / translated / paused).
struct TranslateBookActionRow: View {

    /// The book's translate-book state (phase + counts). The row's
    /// label, sublabel, and leading icon all derive from this.
    let progress: BookTranslationProgress
    /// The target language label shown in the sublabel ("Chinese").
    let targetLanguageLabel: String
    let theme: ReaderThemeV2
    /// Invoked on tap. The host wires this to
    /// `BookTranslationViewModel.presentConfirm(...)`.
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                iconChip
                VStack(alignment: .leading, spacing: 2) {
                    Text("Translate entire book\u{2026}")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color(theme.inkColor))
                        .lineLimit(1)
                    Text(sublabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(theme.subColor))
                        .lineLimit(1)
                        .truncationMode(.tail)
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
        .accessibilityIdentifier("translateBookActionRow")
    }

    /// The leading 28pt rounded icon chip — design `TranslateBookActionRow`'s
    /// status-aware icon (translate glyph idle, spinner running, check
    /// translated).
    private var iconChip: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(chipFill)
            .frame(width: 28, height: 28)
            .overlay { chipContent }
    }

    @ViewBuilder
    private var chipContent: some View {
        switch progress.phase {
        case .running:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .tint(Color(theme.accentColor))
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(theme.accentColor))
        default:
            Image(systemName: "character.bubble")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color(theme.accentColor))
        }
    }

    /// Chip background — matches the design's accent-tinted backdrop with
    /// a green-leaning fill in the translated state.
    private var chipFill: Color {
        if progress.phase == .completed {
            return Color(theme.accentColor).opacity(0.10)
        }
        return Color(theme.accentColor).opacity(0.10)
    }

    /// Status-aware sublabel — pinned to the design's four-way switch.
    private var sublabel: String {
        switch progress.phase {
        case .running:
            return "Translating to \(targetLanguageLabel) \u{00b7} \(progress.completed) of \(progress.total) chapters"
        case .completed:
            return "Translated to \(targetLanguageLabel) \u{00b7} \(progress.completed) of \(progress.total) chapters"
        case .failed:
            return "Paused at \(progress.completed) of \(progress.total)"
        case .cancelled:
            return "Cancelled \u{00b7} \(progress.completed) of \(progress.total) chapters cached"
        case .idle:
            return "Pre-translate every chapter to \(targetLanguageLabel)"
        }
    }
}
#endif
