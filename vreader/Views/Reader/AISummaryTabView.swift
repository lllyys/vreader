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

    /// The idle prompt — design's sparkle glyph + serif headline + a
    /// pill primary action, re-skinned to v2 tokens.
    @ViewBuilder
    private var idleSection: some View {
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
    private var loadingSection: some View {
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

    /// The completed / streaming state — the design's accent summary
    /// card with the Share + Regenerate chip footer.
    @ViewBuilder
    private var summarySection: some View {
        AISummaryCard(
            summaryText: viewModel.responseText,
            theme: theme,
            onRegenerate: runSummarize,
            onShare: { onShare(shareText) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The error state — a warning glyph + the message + a retry chip.
    @ViewBuilder
    private var errorSection: some View {
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
    private var featureDisabledSection: some View {
        infoState(
            systemImage: "sparkles.slash",
            title: "AI features are currently disabled.",
            detail: "Enable AI in Settings to use this feature.",
            identifier: "aiPanelDisabled"
        )
    }

    /// The consent-required state — a raised-hand glyph + a grant chip.
    @ViewBuilder
    private var consentRequiredSection: some View {
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
    private func infoState(
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

    // MARK: - Helpers

    /// The text the summary card's Share chip forwards to the parent —
    /// the verbatim generated summary off the view model. `internal` so
    /// the share-payload contract is unit-testable without a render pass.
    var shareText: String {
        viewModel.responseText
    }

    /// The current error message, if the state is `.error`.
    private var errorMessage: String {
        if case .error(let message) = viewModel.state { return message }
        return ""
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
        }
    }

    /// The neutral chip wash — design `chipBtn`.
    private var chipFillColor: UIColor {
        theme.isDark
            ? UIColor.white.withAlphaComponent(0.07)
            : UIColor.black.withAlphaComponent(0.05)
    }
}
#endif
