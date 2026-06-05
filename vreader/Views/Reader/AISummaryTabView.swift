// Purpose: Feature #65 WI-1 — the re-skinned Summarize tab body.
// Extracted from `AIReaderPanel.swift` (the inline `summarizeContent`
// switch + `idleView`/`loadingView`/`completeView`/`errorView`/
// `featureDisabledView`/`consentRequiredView`), re-skinned to the v2
// theme tokens and the design's summary card.
//
// Feature #69 WI-5 adds the scope chip strip (Section / Chapter /
// Book so far) above the state body, wired to the scoped
// AIContextExtractor. The suggested-questions list remains OMITTED
// (carved out by feature #65 §2.2 — no question-generation service).
//
// Mirrors `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`
// — `SummaryView`: the chip pill row + the summary card + states.
//
// State routing is exposed through the pure static `section(for:)`
// mapper + the `SummarySection` enum (the `SearchView.contentState`
// precedent) so a re-skin regression guard can pin every state without
// a SwiftUI render pass.
//
// @coordinates-with: AIReaderPanel.swift, AISummaryCard.swift,
//   AIAssistantViewModel.swift, ReaderThemeV2.swift,
//   ReaderTypography.swift, SummaryScope.swift, ChapterBounds.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx`

#if canImport(UIKit)
import SwiftUI

/// The re-skinned Summarize tab body — design `vreader-panels.jsx`
/// `SummaryView`: the scope chip strip + the summary card + states.
struct AISummaryTabView: View {

    /// The AI assistant view model (shared with the reader).
    @Bindable var viewModel: AIAssistantViewModel

    /// The current locator for context extraction.
    let locator: Locator

    /// The FULL flattened book text — the source for scoped extraction
    /// (Section / Chapter / Book-so-far). NOT a section snippet:
    /// feeding a snippet would make Chapter / Book-so-far meaningless.
    let fullTextContent: String

    /// The chapter span containing the locator, for the Chapter scope.
    /// `nil` (empty / non-char-offset-anchored TOC) → Chapter degrades
    /// to Section in `AIContextExtractor`.
    let chapterBounds: ChapterBounds?

    /// The book format (determines context extraction strategy).
    let format: BookFormat

    /// Visual-identity-v2 theme tokens.
    let theme: ReaderThemeV2

    /// Runs when the summary card's Share chip is tapped — the parent
    /// presents `ShareActivityView` with the summary text.
    var onShare: (String) -> Void

    /// Feature #90 WI-2: whether the language popover is presented. Owned here
    /// (the `body` presents the popover); the lang-row wiring lives in the
    /// `+Bilingual` extension to keep this file under the ~300-line guide.
    @State var isLangPopoverPresented = false

    // MARK: - State sections

    /// The distinct visual sections the Summarize tab can show. One
    /// `AIAssistantState` may resolve to the same section (`.streaming`
    /// and `.complete` both show `.summary`).
    enum SummarySection: Equatable {
        case idle
        case loading
        case summary
        case error
        case featureDisabled
        case consentRequired
    }

    /// Pure mapping from a view-model state to its visual section.
    /// Exposed `static` so the re-skin regression guard pins every
    /// state without a render pass (the `SearchView.contentState`
    /// precedent).
    static func section(for state: AIAssistantState) -> SummarySection {
        switch state {
        case .idle:            return .idle
        case .loading:         return .loading
        // Streaming accumulates text into the same card as complete.
        case .streaming, .complete: return .summary
        case .error:           return .error
        case .featureDisabled: return .featureDisabled
        case .consentRequired: return .consentRequired
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The scope chip strip sits above the state body so it shows
            // in every state — matching the design `SummaryView`.
            AISummaryScopeChipStrip(
                scopes: scopeChips,
                activeScope: activeScope,
                theme: theme,
                onSelect: selectScope
            )
            // Feature #90 WI-2: the second control row — language + a
            // Single/Bilingual toggle — beneath the scope chips (design's
            // "two rows, not one crowded row").
            AISummaryLangRow(
                language: viewModel.summaryTargetLanguage,
                mode: viewModel.summaryDisplayMode,
                theme: theme,
                isPopoverOpen: isLangPopoverPresented,
                onTapLanguage: toggleLangPopover,
                onSelectMode: selectDisplayMode
            )
            .padding(.horizontal, 18)
            .padding(.top, 11)
            .padding(.bottom, 2)
            stateBody
        }
        // The language popover overlays the control block, anchored under the
        // lang row — matching the artboard's absolutely-positioned `LangPopover`
        // (an iPhone `.popover` would render as a sheet, breaking the design).
        // The overlay body lives in the `+Bilingual` extension.
        .overlay(alignment: .topLeading) { langPopoverOverlay }
    }

    /// The state-routed body, below the chip strip.
    @ViewBuilder
    private var stateBody: some View {
        switch Self.section(for: viewModel.state) {
        case .idle:            idleSection
        case .loading:         loadingSection
        case .summary:         summarySection
        case .error:           errorSection
        case .featureDisabled: featureDisabledSection
        case .consentRequired: consentRequiredSection
        }
    }

    // MARK: - Scope chip strip wiring (feature #69 WI-5)

    /// The three scope chips the AI Summarize tab can scope its summary
    /// to — `[.section, .chapter, .bookSoFar]`, in design order.
    /// `internal` so the chip-strip contract is unit-testable.
    var scopeChips: [SummaryScope] { SummaryScope.allCases }

    /// The currently-selected scope (drives which chip renders filled).
    /// Mirrors `viewModel.selectedScope`.
    var activeScope: SummaryScope { viewModel.selectedScope }

    /// Whether `scope`'s chip should render in the active (filled) style.
    func isScopeActive(_ scope: SummaryScope) -> Bool {
        viewModel.selectedScope == scope
    }

    /// Selects a scope chip. Updates the view model's selection only —
    /// it does NOT auto-run the summary (the user taps Summarize /
    /// Regenerate). `internal` so the selection contract is testable.
    func selectScope(_ scope: SummaryScope) {
        viewModel.setScope(scope)
    }

    /// The accessibility identifier for a scope chip — re-exported from
    /// `AISummaryScopeChipStrip` so tests and the XCUITest acceptance
    /// pass have one stable reference point.
    static func scopeChipIdentifier(_ scope: SummaryScope) -> String {
        AISummaryScopeChipStrip.chipIdentifier(scope)
    }

    // MARK: - Sections

    // The non-summary state sections (idle / loading / error /
    // feature-disabled / consent-required + the shared `infoState`) live in
    // `AISummaryTabView+Sections.swift` to keep this file under the ~300-line
    // guide (Gate-4 Low). `stateBody` above routes to them.

    /// The completed / streaming state — the design's accent summary
    /// card with the Share + Regenerate chip footer.
    @ViewBuilder
    private var summarySection: some View {
        AISummaryCard(
            summaryText: viewModel.responseText,
            theme: theme,
            displayMode: viewModel.summaryDisplayMode,
            translation: viewModel.summaryTranslation,
            targetLanguage: viewModel.summaryTargetLanguage,
            onRegenerate: runSummarize,
            onShare: { onShare(shareText) },
            onRetryTranslation: { Task { await viewModel.retrySummaryTranslation() } },
            onKeepOriginal: { viewModel.setSummaryDisplayMode(.originalOnly) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    /// The text the summary card's Share chip forwards to the parent —
    /// the verbatim generated summary off the view model. `internal` so
    /// the share-payload contract is unit-testable without a render pass.
    var shareText: String {
        viewModel.responseText
    }

    /// Re-runs the summarize action — wired to the idle / error /
    /// Regenerate triggers.
    ///
    /// In-flight guard: a rapid second tap (e.g. on the Regenerate chip)
    /// while a request is already `.loading` / `.streaming` is a no-op.
    /// `AIAssistantViewModel.summarize` does not coalesce concurrent
    /// callers, so without this guard two overlapping requests could
    /// race and an older response could overwrite a newer one.
    /// `internal` (not `private`) so the guard is unit-testable.
    func runSummarize() {
        switch viewModel.state {
        case .loading, .streaming:
            // A request is already in flight — ignore the re-trigger.
            return
        case .idle, .complete, .error, .featureDisabled, .consentRequired:
            break
        }
        Task {
            // Feature #69 WI-5: summarize at the currently-selected scope
            // chip, over the FULL flattened book text. `chapterBounds`
            // bounds the Chapter scope; a nil bounds degrades Chapter to
            // Section inside the extractor.
            await viewModel.summarize(
                locator: locator,
                fullText: fullTextContent,
                format: format,
                scope: viewModel.selectedScope,
                chapterBounds: chapterBounds
            )
            // Feature #90 WI-3 (Gate-4 High): `summarize` goes through
            // `performAction`, which resets the translation to `.none` — and the
            // card selector maps `(translatedOnly | interlinear, .none)` back to
            // `.original`. So a fresh / regenerated summary with Single or
            // Bilingual already selected would render original-only until the
            // user re-toggled the control. Kick the (re)translation here so the
            // chosen mode applies immediately. `refreshSummaryTranslationIfNeeded`
            // is a no-op for `.originalOnly`, and its own op-token guard drops the
            // result if the summary was superseded meanwhile.
            await viewModel.refreshSummaryTranslationIfNeeded()
        }
    }
}
#endif
