// Purpose: Feature #65 WI-1 — the re-skinned Summarize summary card.
// Replaces the bare `ScrollView { Text }` + native "New Request"
// button (the pre-v2 `AIReaderPanel.completeView`) with the design's
// accent-bordered card: a sparkle uppercase label, serif body text,
// and a Share + Regenerate chip footer.
//
// Mirrors `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`
// — `SummaryView`'s summary card + `chipBtn`.
//
// Scope reconciliation (plan §2.2):
// - The design's footer draws three chips (Save / Share / Regenerate).
//   VReader has no saved-summaries store, so the **Save chip is
//   omitted** — the card's public surface carries no `onSave`.
// - The design's sparkle label reads "Chapter 1 — Summary"; the
//   chapter index is sample data with no production source, so the
//   label ships as a fixed "Summary" (the AI-generated chapter title
//   is a separate capability).
//
// @coordinates-with: AISummaryTabView.swift, ReaderThemeV2.swift,
//   ReaderTypography.swift, ShareSheet.swift (ShareActivityView),
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

/// The accent-bordered AI summary card — design `vreader-panels.jsx`
/// `SummaryView`. Sparkle uppercase label, serif body, Share +
/// Regenerate chip footer (the design's Save chip is omitted —
/// plan §2.2).
struct AISummaryCard: View {
    /// The generated summary text rendered in the card body.
    let summaryText: String
    /// Visual-identity-v2 theme tokens for the card surface + ink.
    let theme: ReaderThemeV2
    /// Feature #90 WI-3: how the summary is presented (original-only /
    /// target-only / interlinear). Drives the bilingual body switch.
    var displayMode: SummaryDisplayMode = .originalOnly
    /// Feature #90 WI-3: the second-step translation sub-state — drives the
    /// loading skeleton / failure recovery / translated text.
    var translation: SummaryTranslationState = .none
    /// Feature #90 WI-3: the bilingual target language — its name appears in the
    /// failure heading; its script picks the CJK font for the target paragraph.
    var targetLanguage: BilingualLanguage =
        BilingualLanguage.all.first ?? BilingualLanguage(key: "Chinese", glyph: "中", script: .cjk)
    /// Runs when the Regenerate chip is tapped — re-runs summarize.
    var onRegenerate: () -> Void
    /// Runs when the Share chip is tapped — the tab view presents
    /// `ShareActivityView` with the summary text.
    var onShare: () -> Void
    /// Feature #90 WI-3: re-runs ONLY the translation half (the failure card's
    /// "Retry translation"). Defaulted so the existing single-mode call sites
    /// (and the #65 composition tests) compile unchanged.
    var onRetryTranslation: () -> Void = {}
    /// Feature #90 WI-3: drops back to original-only (the failure card's
    /// "Keep original").
    var onKeepOriginal: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                sparkleLabel
                bilingualBody
                    .padding(.top, 10)
                Color(theme.ruleColor)
                    .frame(height: 0.5)
                    .padding(.top, 14)
                chipFooter
                    .padding(.top, 12)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(cardFillColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color(theme.ruleColor), lineWidth: 0.5)
            )
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .accessibilityIdentifier("aiPanelResponse")
    }

    // MARK: - Parts

    /// The design's sparkle + uppercase tracked label.
    private var sparkleLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(theme.accentColor))
            Text("Summary")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Color(theme.subColor))
        }
        .accessibilityHidden(true)
    }

    /// The Share + Regenerate chip footer (Save omitted — plan §2.2).
    private var chipFooter: some View {
        HStack(spacing: 8) {
            chip(label: "Share", systemImage: "square.and.arrow.up", action: onShare)
                .accessibilityIdentifier("aiSummaryShareButton")
            chip(label: "Regenerate", systemImage: nil, action: onRegenerate)
                .accessibilityIdentifier("aiNewRequestButton")
            Spacer(minLength: 0)
        }
    }

    /// A single pill chip — design `chipBtn`.
    private func chip(
        label: String,
        systemImage: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Color(theme.subColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(Color(chipFillColor))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Palette

    /// The card's faint accent-tinted fill — design `SummaryView`'s
    /// `rgba(140,47,47,0.04)` (light) / `rgba(214,136,90,0.08)` (dark).
    private var cardFillColor: UIColor {
        theme.accentColor.withAlphaComponent(theme.isDark ? 0.08 : 0.04)
    }

    /// The chip's neutral wash — design `chipBtn`.
    private var chipFillColor: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.07)
            : UIColor.black.withAlphaComponent(0.05)
    }
}
#endif
