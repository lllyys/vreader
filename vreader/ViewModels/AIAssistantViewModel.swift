// Purpose: ViewModel for the AI assistant panel.
// Manages request lifecycle states and bridges between View and AIService.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - State machine: idle → loading → streaming/complete/error.
// - Consent prompt shown when consentRequired error occurs.
// - Each action method resets state before starting.
// - Streaming accumulates text chunks into responseText.
// - Errors are mapped to user-friendly messages via AIError.localizedDescription.
// - Summary scope (feature #69): `selectedScope` tracks the AI Summarize
//   tab's scope chip; `summarize` takes the FULL flattened book text +
//   scope + chapterBounds and forwards them to the extractor. The
//   non-summarize actions (explain/translate/vocabulary/askQuestion) are
//   selection-driven and always extract with `.section`.
// - The context extractor is injected as `any AIContextExtracting` (a
//   boundary protocol) so tests can record what scope/bounds/fullText
//   the view model forwards.
//
// @coordinates-with: AIService.swift, AIContextExtracting.swift,
//   SummaryScope.swift, ChapterBounds.swift, AISummaryTabView.swift

import Foundation

/// UI states for the AI assistant panel.
enum AIAssistantState: Sendable, Equatable {
    case idle
    case loading
    case streaming
    case complete
    case error(String)
    case consentRequired
    case featureDisabled
}

/// ViewModel for the AI assistant UI.
@Observable
@MainActor
final class AIAssistantViewModel {

    // MARK: - Published State

    /// Current state of the AI assistant.
    /// `internal(set)` (not `private(set)`) so the streaming/cancel
    /// concern in `AIAssistantViewModel+Streaming.swift` can drive it.
    internal(set) var state: AIAssistantState = .idle

    /// Accumulated response text (from streaming or complete response).
    internal(set) var responseText: String = ""

    /// The action type of the current/last request.
    internal(set) var currentAction: AIActionType?

    /// The AI Summarize tab's selected scope chip. Defaults to `.section`
    /// (the pre-feature-#69 behavior). Mutated only via `setScope`.
    private(set) var selectedScope: SummaryScope = .section

    // MARK: - Bilingual summary (feature #90 WI-1)
    // The display mode + target language + translation sub-state are OBSERVED
    // (drive the Summarize card); the mutation logic lives in
    // `AIAssistantViewModel+BilingualSummary.swift`. Stored properties cannot
    // live in an extension, so they stay here, with `private(set)` setters
    // routed through the synchronous mutators in that file.

    /// How the completed summary is presented: as the model produced it
    /// (`.originalOnly`, the default — no translation), translated to
    /// `summaryTargetLanguage` only (`.translatedOnly`), or both stacked
    /// (`.interlinear`). `internal(set)` (not `private(set)`) so the
    /// `+BilingualSummary.swift` extension can drive it via its synchronous
    /// `setSummaryDisplayMode` mutator (same reason `state`/`responseText` are
    /// `internal(set)` — a `private(set)` setter is invisible to a same-type
    /// extension in a separate file).
    internal(set) var summaryDisplayMode: SummaryDisplayMode = .originalOnly

    /// The bilingual target language for the translated/interlinear modes.
    /// Defaults to the first `BilingualLanguage.all` entry; the reader host
    /// seeds the per-book `bilingualTargetLanguage` once on first appear
    /// (WI-2). Mutated only via `setSummaryTargetLanguage`.
    internal(set) var summaryTargetLanguage: BilingualLanguage =
        BilingualLanguage.all.first ?? BilingualLanguage(key: "Chinese", glyph: "中", script: .cjk)

    /// The second-step translation sub-state, independent of `state`/`responseText`
    /// so the summary can ship while its translation loads / fails / completes.
    internal(set) var summaryTranslation: SummaryTranslationState = .none

    // MARK: - Dependencies
    // `internal` (not `private`) so the streaming/cancel extension file
    // can reach them.

    let aiService: AIService
    let contextExtractor: any AIContextExtracting

    // MARK: - Private
    // These lifecycle vars are `@ObservationIgnored` (not UI-observed) and
    // `internal` so `AIAssistantViewModel+Streaming.swift` can mutate them.
    // Stored properties cannot live in an extension, so they stay here.

    /// The currently-running request task, retained so a user Stop
    /// (`cancelStreaming`) or a superseding request can cancel it. Now
    /// actually assigned (feature #87 WI-3): the VM owns its one-shot
    /// `sendRequest` rather than awaiting it inline.
    @ObservationIgnored var streamTask: Task<Void, Never>?

    /// Monotonic operation id. Every launch bumps it; a request's
    /// post-`await` writes are gated on `opId == opCounter` so a stale,
    /// superseded, or cancelled task cannot clobber a newer op's state.
    @ObservationIgnored var opCounter: UInt64 = 0

    /// The summary that was `.complete` when the CURRENT in-flight
    /// request launched, snapshotted before `responseText` is cleared.
    /// On a Stop, `cancelStreaming()` restores it (regenerate-preserve
    /// contract) so stopping a regenerate keeps the last good summary;
    /// `nil` when the in-flight request is an INITIAL summarize (Stop →
    /// `.idle`).
    @ObservationIgnored var priorCompletedSummary: String?

    /// The bilingual summary's SEPARATE translation task (feature #90 WI-1),
    /// retained so a re-summarize / mode-flip / language-change / reset can
    /// cancel it. Distinct from `streamTask` (which owns the summarize call).
    @ObservationIgnored var summaryTranslationTask: Task<Void, Never>?

    /// Monotonic op token for the translation half. Every kick bumps it; a
    /// translation's post-`await` writes are gated on `token == summaryTranslationToken`
    /// so a superseded / cancelled translation cannot clobber a newer one.
    @ObservationIgnored var summaryTranslationToken: UInt64 = 0

    // MARK: - Init

    init(
        aiService: AIService,
        contextExtractor: any AIContextExtracting = AIContextExtractor()
    ) {
        self.aiService = aiService
        self.contextExtractor = contextExtractor
    }

    // MARK: - Scope

    /// Updates the Summarize tab's selected scope. Does NOT re-run the
    /// summary — the user explicitly taps Summarize / Regenerate. Every
    /// `AIAssistantViewModel` state change is a method (codebase convention).
    func setScope(_ scope: SummaryScope) {
        selectedScope = scope
    }

    // MARK: - Actions

    /// Summarizes the book at the given scope around the locator.
    ///
    /// `fullText` is the FULL flattened book text — NOT a section snippet.
    /// It is intentionally non-defaulted: the Summarize call site must
    /// pass the full text explicitly so a `.chapter` / `.bookSoFar` scope
    /// can slice a meaningful span (defaulting it would re-introduce the
    /// "scoped summary runs on a pre-extracted snippet" bug).
    func summarize(
        locator: Locator,
        fullText: String,
        format: BookFormat,
        scope: SummaryScope = .section,
        chapterBounds: ChapterBounds? = nil
    ) async {
        await performAction(
            type: .summarize,
            locator: locator,
            fullText: fullText,
            format: format,
            scope: scope,
            chapterBounds: chapterBounds
        )
    }

    /// Explains the text around the given locator. Selection-driven —
    /// always extracts with `.section` scope (out of feature #69's scope).
    func explain(
        locator: Locator,
        textContent: String,
        format: BookFormat
    ) async {
        await performAction(
            type: .explain,
            locator: locator,
            fullText: textContent,
            format: format
        )
    }

    /// Translates the text around the given locator. Selection-driven —
    /// always extracts with `.section` scope.
    func translate(
        locator: Locator,
        textContent: String,
        format: BookFormat,
        targetLanguage: String
    ) async {
        await performAction(
            type: .translate,
            locator: locator,
            fullText: textContent,
            format: format,
            targetLanguage: targetLanguage
        )
    }

    /// Looks up vocabulary in the text around the given locator.
    /// Selection-driven — always extracts with `.section` scope.
    func vocabulary(
        locator: Locator,
        textContent: String,
        format: BookFormat
    ) async {
        await performAction(
            type: .vocabulary,
            locator: locator,
            fullText: textContent,
            format: format
        )
    }

    /// Answers a question about the text around the given locator.
    /// Selection-driven — always extracts with `.section` scope.
    func askQuestion(
        question: String,
        locator: Locator,
        textContent: String,
        format: BookFormat
    ) async {
        await performAction(
            type: .questionAnswer,
            locator: locator,
            fullText: textContent,
            format: format,
            userPrompt: question
        )
    }

    /// Grants AI consent and transitions to idle state.
    func grantConsent() {
        aiService.consentManager.grantConsent()
        state = .idle
    }

    /// Resets the assistant to idle state.
    func reset() {
        streamTask?.cancel()
        streamTask = nil
        priorCompletedSummary = nil
        // Feature #90 WI-1: a summary-translation task could outlive `reset()` /
        // sheet dismiss and later write STALE bilingual state. Tear it down here.
        cancelSummaryTranslation()
        state = .idle
        responseText = ""
        currentAction = nil
    }
}
