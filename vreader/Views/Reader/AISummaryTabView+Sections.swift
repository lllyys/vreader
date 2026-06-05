// Purpose: Feature #90 WI-3 (Gate-4 Low) — the Summarize tab's non-summary
// STATE sections (idle / loading / error / feature-disabled / consent-required +
// the shared info-state layout) split out of `AISummaryTabView.swift` so the
// base file stays under the ~300-line guide. The base keeps the body, the
// `stateBody` router, the scope wiring, the bilingual `summarySection`, and
// `runSummarize`; this extension holds the surrounding states.
//
// The members are `internal` (not `private`): a same-type extension in a
// SEPARATE file cannot see `private` members, and the base file's `stateBody`
// references these. This mirrors the `AISummaryTabView+Bilingual.swift` pattern.
//
// @coordinates-with: AISummaryTabView.swift, AISummaryCard.swift,
//   ReaderThemeV2.swift, ReaderTypography.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

extension AISummaryTabView {

    /// The idle prompt — design's sparkle glyph + serif headline + a
    /// pill primary action, re-skinned to v2 tokens.
    @ViewBuilder
    var idleSection: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(Color(theme.accentColor))
                .accessibilityHidden(true)
            Text("Summarize the current section")
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 16)))
                .foregroundStyle(Color(theme.inkColor))
            Button(action: runSummarize) {
                Text("Summarize")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 220)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(theme.accentColor))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("aiSummarizeButton")
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The loading state — while a summary is in flight the generate
    /// control IS the Stop affordance (feature #87 WI-3, design note
    /// "the generate/language control doubles as the stop affordance").
    /// Per Rule 51 there is NO separate standalone stop button: the
    /// in-flight indicator itself morphs into a tappable Stop disc (white
    /// `square.fill` + sweeping ring, matching the Chat/Translate stop
    /// visual); tapping it aborts via `cancelStreaming()`.
    @ViewBuilder
    var loadingSection: some View {
        VStack(spacing: 14) {
            Spacer()
            Button(action: { viewModel.cancelStreaming() }) {
                ZStack {
                    Circle()
                        .fill(Color(theme.accentColor))
                    Image(systemName: "square.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                    // The sweeping ring signals the in-flight request.
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(0.85)
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("aiSummaryStopButton")
            .accessibilityLabel("Stop")
            Text("Generating summary\u{2026} Tap to stop")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(theme.subColor))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("aiPanelLoading")
    }

    /// The error state — a warning glyph + the message + a retry chip.
    @ViewBuilder
    var errorSection: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundStyle(Color(theme.accentColor))
                .accessibilityHidden(true)
            Text(errorMessage)
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14)))
                .foregroundStyle(Color(theme.inkColor))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(action: runSummarize) {
                Text("Try Again")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(theme.accentColor))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().fill(Color(chipFillColor))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("aiRetryButton")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("aiPanelError")
    }

    /// The feature-disabled state — a slashed-sparkle glyph + copy.
    @ViewBuilder
    var featureDisabledSection: some View {
        infoState(
            systemImage: "sparkles.slash",
            title: "AI features are currently disabled.",
            detail: "Enable AI in Settings to use this feature.",
            identifier: "aiPanelDisabled"
        )
    }

    /// The consent-required state — a raised-hand glyph + a grant chip.
    @ViewBuilder
    var consentRequiredSection: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "hand.raised")
                .font(.system(size: 34))
                .foregroundStyle(Color(theme.subColor))
                .accessibilityHidden(true)
            Text("AI features require your consent.")
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14)))
                .foregroundStyle(Color(theme.inkColor))
                .multilineTextAlignment(.center)
            Text("Grant consent in Settings to use AI features.")
                .font(.system(size: 12))
                .foregroundStyle(Color(theme.subColor))
            Button { viewModel.grantConsent() } label: {
                Text("Grant Consent")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(theme.accentColor))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("aiGrantConsentButton")
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("aiPanelConsent")
    }

    /// Shared layout for the glyph + title + detail info states.
    @ViewBuilder
    func infoState(
        systemImage: String,
        title: String,
        detail: String,
        identifier: String
    ) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 34))
                .foregroundStyle(Color(theme.subColor))
                .accessibilityHidden(true)
            Text(title)
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14)))
                .foregroundStyle(Color(theme.inkColor))
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Color(theme.subColor))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(identifier)
    }

    /// The current error message, if the state is `.error`.
    var errorMessage: String {
        if case .error(let message) = viewModel.state { return message }
        return ""
    }

    /// The neutral chip wash — design `chipBtn`.
    var chipFillColor: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.07)
            : UIColor.black.withAlphaComponent(0.05)
    }
}
#endif
