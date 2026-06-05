// Purpose: Feature #90 WI-3 — the bilingual summary card's loading skeleton
// (`AISummarySkeleton`) and translation-failure recovery card
// (`AISummaryErrorCard`), drawn INSIDE `AISummaryCard` for the `.translating` /
// `.failed` translation sub-states. Split out of `AISummaryCard.swift` so the
// base card file stays under the ~300-line guide.
//
// Mirrors the committed design `bilingual-summarize-artboards.jsx`:
// - `SummarySkeleton` (`:142-158`) — a small spinner + "Summarizing &
//   translating…" caption + 3 skeleton bars (heights 9; widths 100% / 95% /
//   55%); the `dual` variant adds a dashed divider + 2 muted bars (90% / 50%).
// - `SummaryError` (`:159-181`) — a 26×26 red-tinted alert circle + a "Couldn't
//   translate to {lang}" heading + body copy + two pill buttons.
//
// Design deviation (WI-1 Gate-2 M4): the secondary button is **"Keep original"**,
// not the artboard's "Keep English", and the body copy is de-Englished — the
// SOURCE language is unknown (summarize carries no language param).
//
// @coordinates-with: AISummaryCard+Bilingual.swift, AISummaryCard.swift,
//   BilingualLanguage.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/bilingual-summarize-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

/// The loading skeleton shown while the translation is in flight — design
/// `SummarySkeleton`. `dual = true` adds the divider + 2 muted bars for the
/// interlinear case so the stacked layout does not jump when the target lands.
struct AISummarySkeleton: View {

    let theme: ReaderThemeV2
    /// Whether to draw the interlinear (dual) second block.
    var dual: Bool

    /// The card's content width, measured via a zero-cost background probe.
    /// Drives each bar's fractional width WITHOUT making a `GeometryReader` the
    /// layout parent — so the skeleton sizes to its content (the inner `VStack`
    /// determines height) instead of being clipped to a fixed `.frame(height:)`
    /// (Gate-4 High: the old 60 / 110 clamps truncated the bars, whose true
    /// height is ~78 single / ~130 dual).
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.7)
                    .tint(Color(theme.accentColor))
                Text("Summarizing & translating\u{2026}")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(theme.subColor))
            }
            .padding(.bottom, 12)
            bar(width: 1.0, muted: false)
            bar(width: 0.95, muted: false)
            bar(width: 0.55, muted: false)
            if dual {
                VStack(alignment: .leading, spacing: 0) {
                    bar(width: 0.9, muted: true)
                    bar(width: 0.5, muted: true)
                }
                .padding(.top, 8)
                .overlay(alignment: .top) {
                    Rectangle()
                        .strokeBorder(
                            Color(theme.ruleColor),
                            style: StrokeStyle(lineWidth: 0.5, dash: [3, 2])
                        )
                        .frame(height: 0.5)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: SummarySkeletonWidthKey.self, value: geo.size.width
                )
            }
        )
        .onPreferenceChange(SummarySkeletonWidthKey.self) { availableWidth = $0 }
        .accessibilityIdentifier("aiSummaryTranslationLoading")
        .accessibilityLabel("Translating summary")
    }

    /// One skeleton bar — height 9, rounded, a faint fill (design `bar`). The
    /// colored rect takes `fraction × availableWidth`; a trailing `Spacer` fills
    /// the rest, so the bar tracks the design's percentage widths without a
    /// `GeometryReader`-as-parent clipping the column.
    @ViewBuilder
    private func bar(width fraction: CGFloat, muted: Bool) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(barFill(muted: muted)))
                .frame(width: max(0, availableWidth * fraction), height: 9)
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    /// The bar wash — design dark `rgba(255,255,255,0.07/0.04)` / light
    /// `rgba(0,0,0,0.06/0.035)`.
    private func barFill(muted: Bool) -> UIColor {
        if theme.isDark {
            return UIColor.white.withAlphaComponent(muted ? 0.04 : 0.07)
        }
        return UIColor.black.withAlphaComponent(muted ? 0.035 : 0.06)
    }
}

/// The translation-failure recovery card — design `SummaryError`. The summary
/// still renders above this (the caller draws the original ¶ first); this offers
/// "Retry translation" / "Keep original".
struct AISummaryErrorCard: View {

    let theme: ReaderThemeV2
    /// The target language whose name is named in the heading.
    let targetLanguage: BilingualLanguage
    /// Re-runs ONLY the translation half (WI-1 `retrySummaryTranslation`).
    let onRetryTranslation: () -> Void
    /// Drops back to the original-only summary (WI-1 `setSummaryDisplayMode(.originalOnly)`).
    let onKeepOriginal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            alertCircle
            VStack(alignment: .leading, spacing: 0) {
                Text("Couldn\u{2019}t translate to \(targetLanguage.key)")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                    .fixedSize(horizontal: false, vertical: true)
                Text("The summary was generated, but the translation step failed. "
                    + "Show the original summary, or try the translation again.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(theme.subColor))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                buttons
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("aiSummaryTranslationError")
    }

    /// The 26×26 red-tinted circle with an alert glyph (design `#c0443a`).
    private var alertCircle: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0xc0 / 255, green: 0x44 / 255, blue: 0x3a / 255)
                    .opacity(0.12))
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(red: 0xc0 / 255, green: 0x44 / 255, blue: 0x3a / 255))
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }

    /// The two pill buttons — "Retry translation" (accent fill) + "Keep original"
    /// (0.5pt rule border). Wrap so the longer copy survives narrow widths.
    private var buttons: some View {
        HStack(spacing: 8) {
            Button(action: onRetryTranslation) {
                Text("Retry translation")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color(theme.accentColor)))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("aiSummaryRetryTranslationButton")
            Button(action: onKeepOriginal) {
                Text("Keep original")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        Capsule().strokeBorder(Color(theme.ruleColor), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("aiSummaryKeepOriginalButton")
            Spacer(minLength: 0)
        }
    }
}

/// Carries the skeleton card's measured content width up to `AISummarySkeleton`
/// so the bars can take fractional widths without a `GeometryReader` layout
/// parent (which would clip the column to a fixed height).
private struct SummarySkeletonWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
#endif
