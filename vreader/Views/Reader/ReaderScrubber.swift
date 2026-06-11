// Purpose: Feature #60 WI-6b — the bottom-chrome progress scrubber. A 3 pt
// track with an accent fill and a 14 pt draggable thumb, matching the
// design. Clamp + discrete-step snapping reuse `ReadingProgressBar`'s
// tested statics so WI-6b does not re-derive that logic. Split out of
// ReaderBottomChrome.swift for the ~300-line file budget (feature #101
// Gate-4 r2).
//
// @coordinates-with: ReaderBottomChrome.swift, ReadingProgressBar.swift,
//   ReaderThemeV2.swift

import SwiftUI

/// The bottom-chrome progress scrubber (Feature #60 WI-6b). Internal so
/// only the reader chrome composes it.
struct ReaderScrubber: View {
    let theme: ReaderThemeV2
    @Binding var progress: Double
    let onSeek: (Double) -> Void
    let discreteSteps: Int?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = ReadingProgressBar.clampedProgress(progress)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(theme.ruleColor))
                    .frame(height: 3)
                Capsule()
                    .fill(Color(theme.accentColor))
                    .frame(width: max(0, width * clamped), height: 3)
                Circle()
                    .fill(Color(theme.accentColor))
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .offset(x: width * clamped - 7)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        let fraction = max(0, min(1, value.location.x / width))
                        let resolved = ReadingProgressBar.resolveSeekValue(
                            fraction, discreteSteps: discreteSteps
                        )
                        progress = resolved
                        onSeek(resolved)
                    }
            )
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Reading progress scrubber")
        .accessibilityValue(ReadingProgressBar.formatLabel(
            progress: ReadingProgressBar.clampedProgress(progress), label: nil
        ))
        .accessibilityIdentifier("readingProgressScrubber")
    }
}
