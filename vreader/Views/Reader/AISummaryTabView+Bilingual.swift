// Purpose: Feature #90 WI-2 — the bilingual-control wiring for
// `AISummaryTabView`, split out so the base file stays under the ~300-line
// guide (it was already 393 before WI-2).
//
// Holds the language-popover toggle + the control→view-model callbacks: a
// segment tap maps Single → `.translatedOnly` / Bilingual → `.interlinear` and a
// language tap selects the `BilingualLanguage`. Every control change routes
// through the WI-1 synchronous setters (`setSummaryDisplayMode` /
// `setSummaryTargetLanguage`) and then kicks the (re)translation via the WI-1
// `async refreshSummaryTranslationIfNeeded()` — so a non-`.originalOnly` mode
// with a completed summary (re)translates, while `.originalOnly` is a pure no-op.
//
// The methods are `internal` (not `private`): a same-type extension in a
// SEPARATE file cannot see `private` members, and the base file's `body`
// references these. This mirrors the existing `selectScope` / `runSummarize`
// pattern in `AISummaryTabView.swift`.
//
// @coordinates-with: AISummaryTabView.swift, AISummaryLangRow.swift,
//   AISummaryLangPopover.swift, AIAssistantViewModel+BilingualSummary.swift

#if canImport(UIKit)
import SwiftUI

extension AISummaryTabView {

    // MARK: - Language popover

    /// The language-popover overlay — present only while `isLangPopoverPresented`.
    /// A near-transparent scrim catches an outside tap to dismiss; the popover
    /// card sits under the control block, matching the artboard's
    /// absolutely-positioned `LangPopover`. `internal` so the base file's `body`
    /// can reference it across the extension boundary.
    @ViewBuilder
    var langPopoverOverlay: some View {
        if isLangPopoverPresented {
            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { isLangPopoverPresented = false }
                AISummaryLangPopover(
                    selectedLanguage: viewModel.summaryTargetLanguage,
                    theme: theme,
                    onSelect: selectLanguage
                )
                .padding(.leading, 18)
                .padding(.top, 92)
                .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
            }
        }
    }

    /// Toggles the language popover open/closed (the lang-row pill tap).
    func toggleLangPopover() {
        isLangPopoverPresented.toggle()
    }

    // MARK: - Control → view-model wiring

    /// Selects a Single/Bilingual segment. Sets the mapped `SummaryDisplayMode`
    /// via the WI-1 synchronous mutator, then kicks the (re)translation so a
    /// non-`.originalOnly` mode with a completed summary translates immediately.
    /// `internal` so the mapping contract is unit-testable.
    func selectDisplayMode(_ mode: SummaryDisplayMode) {
        guard mode != viewModel.summaryDisplayMode else { return }
        viewModel.setSummaryDisplayMode(mode)
        Task { await viewModel.refreshSummaryTranslationIfNeeded() }
    }

    /// Selects a target language from the popover. Sets it via the WI-1
    /// synchronous mutator (which invalidates any stale translation), closes the
    /// popover, then re-kicks the translation if the current mode needs it.
    func selectLanguage(_ language: BilingualLanguage) {
        isLangPopoverPresented = false
        guard language != viewModel.summaryTargetLanguage else { return }
        viewModel.setSummaryTargetLanguage(language)
        Task { await viewModel.refreshSummaryTranslationIfNeeded() }
    }
}
#endif
