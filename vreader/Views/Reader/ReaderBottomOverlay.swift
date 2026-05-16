// Purpose: Shared bottom overlay showing reading progress and session time.
// Used by both TXTReaderContainerView and MDReaderContainerView (WI-005).
//
// Key decisions:
// - Accepts data as parameters (progress, sessionTime) — no ViewModel coupling.
// - Theme colors derived from optional ReaderSettingsStore with fallback to defaults.
// - Format prefix for accessibility identifiers allows per-format differentiation.
//
// @coordinates-with TXTReaderContainerView.swift, MDReaderContainerView.swift

import SwiftUI

/// Bottom overlay bar displaying reading progress percentage and session time.
struct ReaderBottomOverlay: View {
    let progress: Double?
    let sessionTime: String?
    let settingsStore: ReaderSettingsStore?
    var accessibilityPrefix: String = "reader"

    var body: some View {
        HStack {
            if let progress {
                let pct = Self.formatProgress(progress)
                Text(pct)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(secondaryColor)
                    .accessibilityLabel("Reading progress \(pct.replacingOccurrences(of: "%", with: " percent"))")
                    .accessibilityIdentifier("\(accessibilityPrefix)ProgressIndicator")
            }

            Spacer()

            if let sessionTime {
                Text(sessionTime)
                    .font(.caption)
                    .foregroundColor(secondaryColor)
                    .accessibilityIdentifier("\(accessibilityPrefix)SessionTime")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .accessibilityIdentifier("\(accessibilityPrefix)BottomOverlay")
    }

    // MARK: - Theme Colors

    // Feature #60 WI-11: `theme` is `ReaderThemeV2`; `subColor` is the
    // V2 token for secondary text. Fallback uses `ReaderThemeV2.default`.
    private var secondaryColor: Color {
        Color(settingsStore?.theme.subColor ?? ReaderThemeV2.default.subColor)
    }

    private var backgroundColor: Color {
        Color(settingsStore?.theme.backgroundColor ?? ReaderThemeV2.default.backgroundColor).opacity(0.92)
    }

    // MARK: - Formatting

    /// Formats a 0.0–1.0 progress value as a percentage string like "42%".
    /// Clamps input to 0...1 to prevent invalid display values.
    static func formatProgress(_ value: Double) -> String {
        let clamped = min(max(value, 0), 1)
        return "\(Int(clamped * 100))%"
    }
}
