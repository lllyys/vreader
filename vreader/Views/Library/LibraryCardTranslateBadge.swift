// Purpose: Feature #56 WI-14 — the per-book status badge overlay shown
// on the library card cover whenever a global translate-book job is
// running for that book, or whenever the book has a completed
// whole-book translation in cache.
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`
// (`LibraryCardTranslateBadge`).
//
// @coordinates-with: BookCardView.swift, BookTranslationProgress.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`

#if canImport(UIKit)
import SwiftUI

/// Overlay rendered inside `BookCardView`'s cover area whenever the
/// underlying book has an active or finished translation job. Two visual
/// states: a running chip at the bottom and a translated check at the
/// top-right (per the design).
struct LibraryCardTranslateBadge: View {

    /// Progress snapshot for the underlying book.
    let progress: BookTranslationProgress

    var body: some View {
        switch progress.phase {
        case .running:
            runningChip
        case .completed:
            translatedCheck
        default:
            EmptyView()
        }
    }

    /// Running state — bottom chip with spinner + "{done} / {total}".
    private var runningChip: some View {
        HStack(spacing: 6) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .tint(.white)
            Text("\(progress.completed) / \(progress.total)")
                .font(.system(size: 10, weight: .semibold).monospaced())
                .foregroundStyle(.white)
                .kerning(0.3)
                .lineLimit(1)
            progressBar
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.82))
        )
        .accessibilityIdentifier("libraryCardTranslateBadgeRunning")
    }

    /// Translated state — top-right green check.
    private var translatedCheck: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(
                Circle().fill(Color(red: 0x3a / 255, green: 0x6a / 255, blue: 0x5a / 255).opacity(0.95))
            )
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .accessibilityIdentifier("libraryCardTranslateBadgeTranslated")
    }

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.18))
            Capsule().fill(.white)
                .frame(width: 50 * CGFloat(progress.fraction))
        }
        .frame(width: 50, height: 3)
    }
}
#endif
