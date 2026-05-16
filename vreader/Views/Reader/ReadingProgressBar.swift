// Purpose: Shared reading progress bar with scrubber for all reader formats.
// Provides clamping, optional discrete step snapping, and seek callbacks.
//
// Key decisions:
// - Pure data logic (clamping, snapping, formatting) is static for testability.
// - Accepts @Binding progress + onSeek callback — no ViewModel coupling.
// - Discrete steps snap to nearest (e.g., PDF pages, EPUB chapters).
// - Continuous mode for TXT/MD passes raw slider value.
// - Fade in/out animation when isVisible changes.
// - Theme colors derived from optional ReaderSettingsStore with fallback defaults.
//
// @coordinates-with: ReaderBottomOverlay.swift, TXTReaderContainerView.swift,
//   MDReaderContainerView.swift, PDFReaderContainerView.swift, EPUBReaderContainerView.swift

import SwiftUI

/// A scrubber bar for reading progress. Supports continuous and discrete step modes.
struct ReadingProgressBar: View {
    @Binding var progress: Double  // 0.0 to 1.0
    var onSeek: (Double) -> Void
    var discreteSteps: Int? = nil  // nil = continuous, e.g. 10 = snap to 10 positions
    var isVisible: Bool = true
    var label: String? = nil       // e.g. "Page 3 of 10"
    var settingsStore: ReaderSettingsStore? = nil

    var body: some View {
        if isVisible {
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { Self.clampedProgress(progress) },
                        set: { newValue in
                            let resolved = Self.resolveSeekValue(newValue, discreteSteps: discreteSteps)
                            progress = resolved
                            onSeek(resolved)
                        }
                    ),
                    in: 0...1
                )
                .tint(accentColor)
                .accessibilityLabel("Reading progress scrubber")
                .accessibilityValue(Self.formatLabel(progress: Self.clampedProgress(progress), label: label))
                .accessibilityIdentifier("readingProgressScrubber")

                Text(Self.formatLabel(progress: Self.clampedProgress(progress), label: label))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundColor(secondaryColor)
                    .accessibilityIdentifier("readingProgressLabel")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.2), value: isVisible)
            .accessibilityIdentifier("readingProgressBar")
        }
    }

    // MARK: - Theme Colors

    private var accentColor: Color {
        Color.accentColor
    }

    private var secondaryColor: Color {
        if let store = settingsStore {
            // Feature #60 WI-11: `theme` is `ReaderThemeV2`; `subColor`
            // is the V2 token equivalent of the legacy `secondaryTextColor`.
            return Color(store.theme.subColor)
        }
        return .secondary
    }

    private var backgroundColor: Color {
        if let store = settingsStore {
            return Color(store.theme.backgroundColor).opacity(0.92)
        }
        return Color(.systemBackground).opacity(0.92)
    }

    // MARK: - Static Logic (Testable)

    /// Clamps a progress value to 0.0...1.0. Returns 0.0 for NaN.
    static func clampedProgress(_ value: Double) -> Double {
        guard !value.isNaN else { return 0.0 }
        return min(max(value, 0.0), 1.0)
    }

    /// Snaps a value to the nearest discrete step. Returns raw value if steps is nil or <= 0.
    /// Uses integer-based rounding to avoid floating-point accumulation errors.
    static func snappedValue(_ value: Double, discreteSteps: Int?) -> Double {
        guard let steps = discreteSteps, steps > 0 else {
            return value
        }
        let nearestStep = (value * Double(steps)).rounded()
        return nearestStep / Double(steps)
    }

    /// Combines clamping and snapping into a single resolved seek value.
    static func resolveSeekValue(_ rawValue: Double, discreteSteps: Int?) -> Double {
        let clamped = clampedProgress(rawValue)
        return snappedValue(clamped, discreteSteps: discreteSteps)
    }

    /// Formats the display label. Uses custom label if provided, otherwise percentage.
    static func formatLabel(progress: Double, label: String?) -> String {
        if let label {
            return label
        }
        let clamped = clampedProgress(progress)
        return "\(Int(clamped * 100))%"
    }
}
