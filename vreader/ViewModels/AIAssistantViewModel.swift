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
    private(set) var state: AIAssistantState = .idle

    /// Accumulated response text (from streaming or complete response).
    private(set) var responseText: String = ""

    /// The action type of the current/last request.
    private(set) var currentAction: AIActionType?

    /// The AI Summarize tab's selected scope chip. Defaults to `.section`
    /// (the pre-feature-#69 behavior). Mutated only via `setScope`.
    private(set) var selectedScope: SummaryScope = .section

    // MARK: - Dependencies

    private let aiService: AIService
    private let contextExtractor: any AIContextExtracting

    // MARK: - Private

    private var streamTask: Task<Void, Never>?

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
        state = .idle
        responseText = ""
        currentAction = nil
    }

    // MARK: - Private

    private func performAction(
        type: AIActionType,
        locator: Locator,
        fullText: String,
        format: BookFormat,
        scope: SummaryScope = .section,
        chapterBounds: ChapterBounds? = nil,
        userPrompt: String? = nil,
        targetLanguage: String? = nil
    ) async {
        // Cancel any pending stream
        streamTask?.cancel()
        streamTask = nil

        state = .loading
        responseText = ""
        currentAction = type

        // `contextExtractor` is `any AIContextExtracting`, so the 6-arg
        // requirement is called with `maxUTF16` passed explicitly — a
        // protocol-requirement default argument is not visible through
        // the existential (see AIContextExtracting.swift).
        let context = contextExtractor.extractContext(
            locator: locator,
            fullText: fullText,
            format: format,
            scope: scope,
            chapterBounds: chapterBounds,
            maxUTF16: AIContextBudget.defaultMaxUTF16
        )

        guard !context.isEmpty else {
            state = .error(AIError.contextExtractionFailed.localizedDescription)
            return
        }

        let request = AIRequest(
            actionType: type,
            bookFingerprint: locator.bookFingerprint,
            locator: locator,
            contextText: context,
            userPrompt: userPrompt,
            targetLanguage: targetLanguage,
            promptVersion: "v1"
        )

        do {
            let response = try await aiService.sendRequest(request)
            responseText = response.content
            state = .complete
        } catch let error as AIError {
            switch error {
            case .featureDisabled:
                state = .featureDisabled
            case .consentRequired:
                state = .consentRequired
            default:
                state = .error(error.localizedDescription)
            }
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}
