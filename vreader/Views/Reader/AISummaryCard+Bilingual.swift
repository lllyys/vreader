// Purpose: Feature #90 WI-3 — the bilingual render that lives INSIDE the
// accent-bordered `AISummaryCard`: the mode switch (original-only / target-only /
// interlinear) plus the dual-skeleton loading state and the translation-failure
// recovery card. Extracted from `AISummaryCard.swift` so the base card file stays
// under the ~300-line guide.
//
// Mirrors the committed design `bilingual-summarize-artboards.jsx`:
// - `SummaryCard` (`:103-141`) — single / single-target / dual body branches.
// - `SummarySkeleton` (`:142-158`) — a spinner + "Summarizing & translating…" +
//   3 skeleton bars; the `dual` variant adds a dashed divider + 2 muted bars.
// - `SummaryError` (`:159-181`) — a red-tinted alert circle + a "Couldn't
//   translate to {lang}" heading + body copy + two pill buttons.
//
// Design deviations (intentional, per the WI-3 brief + the WI-1 Gate-2 audit):
// - The error's secondary button is **"Keep original"**, NOT the artboard's
//   "Keep English" — the WI-1 Gate-2 M4 finding established the SOURCE language
//   is unknown (summarize carries no language param), so "English" is wrong. The
//   body copy is likewise de-Englished ("Show the original summary, or try the
//   translation again.").
//
// `AISummaryCardBody` is the pure body-mode selector — given
// `(SummaryDisplayMode, SummaryTranslationState)` it resolves which sub-view to
// render, so the render contract pins in `AISummaryCardModeTests` without a
// SwiftUI pass (the `AISummaryTabView.section(for:)` precedent).
//
// @coordinates-with: AISummaryCard.swift,
//   AIAssistantViewModel+BilingualSummary.swift, BilingualLanguage.swift,
//   ReaderThemeV2.swift, ReaderTypography.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/bilingual-summarize-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

/// Which sub-view the card body renders for a `(displayMode, translation)` pair.
/// Pure (no render pass) so the selection pins in a unit test.
enum AISummaryCardBody: Equatable {
    /// The produced summary `responseText`, serif, ink. The `.originalOnly`
    /// render and the fallback for an un-translated target/interlinear mode.
    case original
    /// ONLY the translated text (`.translatedOnly` + `.translated`).
    case target
    /// The single-line loading skeleton (`.translatedOnly` + `.translating`).
    case skeleton
    /// The failure-recovery card (`.translatedOnly` + `.failed`).
    case error
    /// Original ¶ + dashed divider + translated ¶ (`.interlinear` + `.translated`).
    case interlinear
    /// Original ¶ + the DUAL loading skeleton (`.interlinear` + `.translating`).
    case interlinearSkeleton
    /// Original ¶ + the failure-recovery card below it (`.interlinear` + `.failed`).
    case interlinearError

    /// Resolves the body sub-view for a display mode + translation sub-state, per
    /// the design's `SummaryCard` mode branches.
    static func resolve(
        displayMode: SummaryDisplayMode,
        translation: SummaryTranslationState
    ) -> AISummaryCardBody {
        switch displayMode {
        case .originalOnly:
            // The summary exactly as produced — the translation sub-state is
            // irrelevant (it is never kicked for this mode).
            return .original
        case .translatedOnly:
            switch translation {
            case .translated: return .target
            case .translating: return .skeleton
            case .failed:     return .error
            case .none:       return .original // not yet kicked → don't blank
            }
        case .interlinear:
            switch translation {
            case .translated: return .interlinear
            case .translating: return .interlinearSkeleton
            case .failed:     return .interlinearError
            case .none:       return .original // original only until kicked
            }
        }
    }

    /// Whether this body keeps the ORIGINAL summary paragraph visible (the whole
    /// `.interlinear` family does; the standalone target/skeleton/error do not).
    var showsOriginal: Bool {
        switch self {
        case .original, .interlinear, .interlinearSkeleton, .interlinearError:
            return true
        case .target, .skeleton, .error:
            return false
        }
    }

    /// Extracts the translated text from a `.translated` sub-state, else `nil`.
    /// Pure + pinned (Gate-4 Medium: a broken associated-value extraction would
    /// otherwise slip past the render path untested).
    static func translatedText(from translation: SummaryTranslationState) -> String? {
        if case .translated(let text) = translation { return text }
        return nil
    }

    /// Whether the target paragraph uses the serif CJK font stack — the design's
    /// `useCjk` branch, true for `.cjk` only (`.rtl`/`.latin`/`.cyrillic` use the
    /// body serif). Pure + pinned (Gate-4 Medium: a wrong `Songti SC` branch
    /// would otherwise be invisible to the selector tests).
    static func usesCJKFont(for script: BilingualLanguage.Script) -> Bool {
        script == .cjk
    }
}

extension AISummaryCard {

    /// The bilingual body — the mode switch over `(displayMode, translation)`.
    /// Drawn between the sparkle label and the chip footer inside the card.
    @ViewBuilder
    var bilingualBody: some View {
        let resolved = AISummaryCardBody.resolve(
            displayMode: displayMode,
            translation: translation
        )
        VStack(alignment: .leading, spacing: 0) {
            if resolved.showsOriginal {
                originalParagraph
            }
            switch resolved {
            case .original:
                EmptyView()
            case .target:
                targetParagraph(spacingAbove: 0)
            case .skeleton:
                AISummarySkeleton(theme: theme, dual: false)
            case .error:
                AISummaryErrorCard(
                    theme: theme,
                    targetLanguage: targetLanguage,
                    onRetryTranslation: onRetryTranslation,
                    onKeepOriginal: onKeepOriginal
                )
            case .interlinear:
                dashedDivider
                targetParagraph(spacingAbove: 8)
            case .interlinearSkeleton:
                dashedDivider
                AISummarySkeleton(theme: theme, dual: true)
                    .padding(.top, 8)
            case .interlinearError:
                dashedDivider
                AISummaryErrorCard(
                    theme: theme,
                    targetLanguage: targetLanguage,
                    onRetryTranslation: onRetryTranslation,
                    onKeepOriginal: onKeepOriginal
                )
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Paragraphs

    /// The original summary paragraph — serif 15, ink (design `single` body).
    private var originalParagraph: some View {
        // Bug #335: summaries are LLM markdown (bullets / **bold**); render it as
        // formatting, not literal markup (same fix as the chat row).
        Text(ChatMarkdownRenderer.attributedString(from: summaryText))
            .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 15)))
            .lineSpacing(4)
            .foregroundStyle(Color(theme.inkColor))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The translated paragraph. Standalone (`.translatedOnly`) renders at the
    /// design's single-target size (15.5, ink); below the interlinear divider it
    /// renders smaller + muted (14, subColor). CJK targets use the serif CJK
    /// stack with wider line spacing (design `useCjk` branch).
    @ViewBuilder
    private func targetParagraph(spacingAbove: CGFloat) -> some View {
        let text = translatedText ?? ""
        let interlinear = spacingAbove > 0
        // Bug #335: the translated summary mirrors the source markdown.
        Text(ChatMarkdownRenderer.attributedString(from: text))
            .font(targetFont(interlinear: interlinear))
            .lineSpacing(interlinear ? 5 : 7)
            .foregroundStyle(Color(interlinear ? theme.subColor : theme.inkColor))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, spacingAbove)
    }

    /// The 0.5pt dashed divider between the original and target paragraphs
    /// (design `borderTop: 0.5px dashed`).
    private var dashedDivider: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
            .overlay(
                Rectangle()
                    .strokeBorder(
                        Color(theme.ruleColor),
                        style: StrokeStyle(lineWidth: 0.5, dash: [3, 2])
                    )
            )
            .padding(.top, 7)
    }

    // MARK: - Helpers

    /// The translated text if the sub-state carries one, else `nil`. Delegates
    /// to the pinned pure `AISummaryCardBody.translatedText(from:)`.
    var translatedText: String? {
        AISummaryCardBody.translatedText(from: translation)
    }

    /// The font for the target paragraph: the serif CJK stack for `.cjk` targets
    /// (design `useCjk ? cjkFont : SERIF`), the body serif otherwise. The script
    /// decision is the pinned pure `AISummaryCardBody.usesCJKFont(for:)`.
    private func targetFont(interlinear: Bool) -> Font {
        let size: CGFloat = interlinear ? 14 : 15.5
        if AISummaryCardBody.usesCJKFont(for: targetLanguage.script) {
            return Font.custom("Songti SC", size: size)
        }
        return Font(ReaderTypography.body(for: .sourceSerif4, size: size))
    }
}
#endif
