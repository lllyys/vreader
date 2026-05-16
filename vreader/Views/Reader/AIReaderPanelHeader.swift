// Purpose: Feature #60 visual-identity v2 (WI-10) — the AI sheet's
// custom header row. Extracted from `AIReaderPanel` to keep that file
// under the ~300-line guideline.
//
// Mirrors the design `AISheet`'s header (`vreader-panels.jsx`): a
// sparkle accent-gradient avatar, the "AI Assistant" / "with this
// book's context" titles, the feature-#50 in-reader provider picker,
// and a close button.
//
// @coordinates-with: AIReaderPanel.swift, AIProviderPicker.swift,
//   ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

/// The AI sheet's design header row (feature #60 WI-10).
struct AIReaderPanelHeader: View {
    /// Visual-identity-v2 theme tokens for the header.
    let theme: ReaderThemeV2
    /// The feature-#50 in-reader provider picker's view model.
    @Bindable var providerPickerViewModel: AIProviderPickerViewModel
    /// Sheet-dismiss action.
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            sparkleAvatar
            titles
            Spacer(minLength: 0)
            // Feature #50 WI-7: in-reader provider picker — preserved
            // through the WI-10 re-skin so the user can still flip the
            // active provider without leaving the reader. Persists to
            // the shared ProviderProfileStore; every in-flight
            // AIService call picks the new provider up via
            // resolveProvider.
            AIProviderPicker(viewModel: providerPickerViewModel)
            closeButton
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    // MARK: - Parts

    /// The design's accent-gradient sparkle disc.
    private var sparkleAvatar: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [
                        Color(theme.accentColor),
                        Color(theme.accentColor).opacity(0.67),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }

    /// The "AI Assistant" + "with this book's context" title stack.
    private var titles: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI Assistant")
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 17)))
                .fontWeight(.semibold)
                .foregroundStyle(Color(theme.inkColor))
            Text("with this book's context")
                .font(.system(size: 11))
                .foregroundStyle(Color(theme.subColor))
        }
    }

    /// The circular close button — the design `AISheet`'s dismiss
    /// affordance.
    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(theme.subColor))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(
                        theme.isDark
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.06)
                    )
                )
        }
        .accessibilityLabel("Close")
        .accessibilityIdentifier("aiPanelDoneButton")
    }
}
#endif
