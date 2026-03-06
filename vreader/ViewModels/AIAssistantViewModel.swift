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
//
// @coordinates-with: AIService.swift, AIAssistantView.swift

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

    // MARK: - Dependencies

    private let aiService: AIService
    private let contextExtractor: AIContextExtractor

    // MARK: - Private

    private var streamTask: Task<Void, Never>?

    // MARK: - Init

    init(
        aiService: AIService,
        contextExtractor: AIContextExtractor = AIContextExtractor()
    ) {
        self.aiService = aiService
        self.contextExtractor = contextExtractor
    }

    // MARK: - Actions

    /// Summarizes the text around the given locator.
    func summarize(
        locator: Locator,
        textContent: String,
        format: BookFormat
    ) async {
        await performAction(
            type: .summarize,
            locator: locator,
            textContent: textContent,
            format: format
        )
    }

    /// Explains the text around the given locator.
    func explain(
        locator: Locator,
        textContent: String,
        format: BookFormat
    ) async {
        await performAction(
            type: .explain,
            locator: locator,
            textContent: textContent,
            format: format
        )
    }

    /// Translates the text around the given locator.
    func translate(
        locator: Locator,
        textContent: String,
        format: BookFormat,
        targetLanguage: String
    ) async {
        await performAction(
            type: .translate,
            locator: locator,
            textContent: textContent,
            format: format,
            targetLanguage: targetLanguage
        )
    }

    /// Looks up vocabulary in the text around the given locator.
    func vocabulary(
        locator: Locator,
        textContent: String,
        format: BookFormat
    ) async {
        await performAction(
            type: .vocabulary,
            locator: locator,
            textContent: textContent,
            format: format
        )
    }

    /// Answers a question about the text around the given locator.
    func askQuestion(
        question: String,
        locator: Locator,
        textContent: String,
        format: BookFormat
    ) async {
        await performAction(
            type: .questionAnswer,
            locator: locator,
            textContent: textContent,
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
        textContent: String,
        format: BookFormat,
        userPrompt: String? = nil,
        targetLanguage: String? = nil
    ) async {
        // Cancel any pending stream
        streamTask?.cancel()
        streamTask = nil

        state = .loading
        responseText = ""
        currentAction = type

        let context = contextExtractor.extractContext(
            locator: locator,
            textContent: textContent,
            format: format
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
