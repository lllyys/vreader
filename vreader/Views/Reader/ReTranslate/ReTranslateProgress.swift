// Purpose: Feature #56 WI-15 — the in-progress half-sheet shown after the
// user commits the re-translation. Renders the chapter context strip,
// a spinner + progress bar, and a cancel button. Embedded in
// `ReTranslatePickerSheet` (the host routes here when the VM is in
// `.running`).
//
// Surface origin: `dev-docs/designs/vreader-fidelity-v1/project/vreader-retranslate.jsx`
// — `ReTranslateProgress` JSX component.
//
// @coordinates-with: ChapterReTranslateViewModel.swift,
//   ReTranslatePickerSheet.swift, ReaderThemeV2.swift,
//   dev-docs/designs/vreader-fidelity-v1/project/vreader-retranslate.jsx,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-15)

import SwiftUI

/// The in-progress UI shown while a re-translation is running. Pure
/// SwiftUI value view; receives the progress value (0.0..1.0) from the
/// view model and a cancel callback.
struct ReTranslateProgress: View {

    let theme: ReaderThemeV2
    /// Chapter title shown in the context strip. Provided by the host so
    /// the user sees what's being re-translated even after the picker is
    /// replaced by the progress view.
    let chapterTitle: String
    /// 0.0..1.0 progress — drives the bar's width and the % readout.
    let progress: Double
    let onCancel: () -> Void

    static let accessibilityIdentifier = "reTranslateProgress"

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            contextStrip
            progressBlock
            cancelButton
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 28)
        .accessibilityIdentifier(Self.accessibilityIdentifier)
    }

    private var contextStrip: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color(theme.accentColor))
                .scaleEffect(0.9)
            VStack(alignment: .leading, spacing: 1) {
                Text(chapterTitle)
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14.5)))
                    .italic()
                    .foregroundStyle(Color(theme.inkColor))
                    .lineLimit(1)
                Text("Streaming paragraphs as they arrive…")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(theme.subColor))
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.isDark
                    ? Color.white.opacity(0.04)
                    : Color.black.opacity(0.03))
        )
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.isDark
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.06))
                    Capsule()
                        .fill(Color(theme.accentColor))
                        .frame(
                            width: max(0, geo.size.width * CGFloat(clampedProgress))
                        )
                        .animation(.easeOut(duration: 0.4), value: clampedProgress)
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(percentLabel)%")
                    .monospacedDigit()
                Spacer()
                Text(remainingLabel)
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(Color(theme.subColor))
        }
    }

    private var cancelButton: some View {
        Button(action: onCancel) {
            Text("Cancel")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(theme.inkColor))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(theme.isDark
                            ? Color.white.opacity(0.06)
                            : Color.black.opacity(0.05))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reTranslateCancelButton")
    }

    // MARK: - Derived labels

    private var clampedProgress: Double { max(0, min(1, progress)) }

    private var percentLabel: Int { Int((clampedProgress * 100).rounded()) }

    /// Best-effort ETA. The translation service is opaque so we use a
    /// dynamic heuristic: at 0% progress we report a placeholder estimate;
    /// as progress advances the estimate shrinks. Capped at 99s so the
    /// label doesn't dance into long values.
    private var remainingLabel: String {
        // The design's heuristic is `(100 - progress) * 0.18s`. Mirrored
        // here directly — keeps the label moving without making promises
        // we can't keep.
        let secondsRemaining = max(0, (1.0 - clampedProgress) * 18.0)
        let rounded = Int(secondsRemaining.rounded())
        return rounded == 0 ? "almost done" : "~\(rounded)s left"
    }
}
