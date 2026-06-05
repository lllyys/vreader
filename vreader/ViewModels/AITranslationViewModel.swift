// Purpose: ViewModel for AI-powered translation with a re-skinned
// result card. Manages translation state, language selection, and
// caching through AIService.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Stores both originalText and translatedText for the result card.
// - Uses AIService for the full gate sequence (feature flag, consent, API key, cache).
// - Context extraction uses AIContextExtractor (same as summarize).
// - Caching is built into AIService — same content + language uses cache.
// - Default target language is "Chinese" (most common for CJK users).
// - **In-flight cancellation (feature #65 WI-3)**: the re-skinned
//   Translate language rail fires `translate(...)` on every pill tap
//   (the design has no separate Translate button), so rapid taps
//   overlap. `translate(...)` holds the running `Task`, cancels it
//   before starting a new one, and a request that finds its task
//   cancelled discards its result without writing state — so a stale
//   superseded response can never overwrite the newest selection.
//   `translate(...)` stays `async` from the caller's perspective: it
//   awaits the task it owns, so callers still see settled state on
//   return.
//
// @coordinates-with: AIService.swift, TranslationPanel.swift,
//   TranslationResultCard.swift

import Foundation

/// ViewModel for AI-powered translation with bilingual view support.
@Observable
@MainActor
final class AITranslationViewModel {

    // MARK: - Published State

    /// The original text that was sent for translation.
    var originalText: String = ""

    /// Bug #314: true when the Translate tab was opened from a text SELECTION
    /// (the selection-popover path sets `originalText` to the selection + this
    /// flag). When set, a language-pill tap translates the selection VERBATIM
    /// (no `.section` context-window re-extraction). Cleared by `reset()` — the
    /// cold "Open AI Translate" path — so a no-selection open falls back to the
    /// current reading context. Owned by the consumer (`ReaderContainerView`),
    /// read by `TranslationPanel.requestTranslation`.
    var hasExplicitSelection: Bool = false

    /// The translated text result (nil before first translation).
    var translatedText: String?

    /// The currently selected target language.
    var targetLanguage: String = "Chinese"

    /// Whether a translation request is in progress.
    private(set) var isLoading: Bool = false

    /// Error message to display, or nil if no error.
    private(set) var errorMessage: String?

    /// List of supported target languages.
    let supportedLanguages: [String] = [
        "Chinese", "Japanese", "Korean", "Spanish", "French",
        "German", "Portuguese", "Russian", "Arabic"
    ]

    // MARK: - Dependencies

    private let aiService: AIService
    private let contextExtractor: AIContextExtractor

    /// The currently-running translate task, retained so a fresh
    /// `translate(...)` can cancel a still-in-flight predecessor before
    /// starting. `nil` when no translate is in progress.
    private var translateTask: Task<Void, Never>?

    // MARK: - Init

    init(
        aiService: AIService,
        contextExtractor: AIContextExtractor = AIContextExtractor()
    ) {
        self.aiService = aiService
        self.contextExtractor = contextExtractor
    }

    // MARK: - Actions

    /// Translates the given text into `targetLanguage`.
    ///
    /// If a previous translate is still in flight (the re-skinned
    /// language rail fires this on every pill tap), that predecessor is
    /// cancelled first; its result — if it still arrives — is discarded
    /// so it cannot overwrite this newer request. The method stays
    /// `async`: it awaits the task it owns, so the caller sees settled
    /// state on return.
    ///
    /// `targetLanguage` is taken as a parameter, not re-read from the
    /// `targetLanguage` property: each request's language is fixed at
    /// the call site, so an overlapping later tap that mutates shared
    /// state cannot retarget an already-spawned request. The property
    /// is updated from the parameter so the rail's selection highlight
    /// still follows the request.
    ///
    /// - Parameters:
    ///   - originalText: The text to translate.
    ///   - locator: The reading position for context extraction.
    ///   - format: The book format.
    ///   - targetLanguage: The language to translate into.
    func translate(
        originalText: String,
        locator: Locator,
        format: BookFormat,
        targetLanguage: String,
        // Bug #314: translate `originalText` VERBATIM (the user's selection),
        // skipping the `.section` context-window re-extraction. Default false
        // preserves the cold context-translate path.
        isExplicitSelection: Bool = false
    ) async {
        // Supersede any in-flight predecessor — its result will be
        // discarded once it observes cancellation.
        translateTask?.cancel()

        self.originalText = originalText
        self.targetLanguage = targetLanguage
        self.translatedText = nil
        self.errorMessage = nil
        self.isLoading = true

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performTranslation(
                originalText: originalText,
                locator: locator,
                format: format,
                targetLanguage: targetLanguage,
                isExplicitSelection: isExplicitSelection
            )
        }
        translateTask = task
        await task.value
    }

    /// Runs one translation request and applies its result — but only
    /// if this task was not superseded. Every state write is guarded by
    /// `Task.isCancelled` so a stale, cancelled request silently drops
    /// its outcome rather than clobbering a newer translate.
    private func performTranslation(
        originalText: String,
        locator: Locator,
        format: BookFormat,
        targetLanguage: String,
        isExplicitSelection: Bool = false
    ) async {
        // Bug #314: an explicit selection is translated verbatim; only the cold
        // context-translate re-extracts the `.section` window around the locator.
        let context = isExplicitSelection
            ? originalText
            : contextExtractor.extractContext(
                locator: locator,
                textContent: originalText,
                format: format
            )

        guard !context.isEmpty else {
            applyFailure(AIError.contextExtractionFailed.localizedDescription)
            return
        }

        let request = AIRequest(
            actionType: .translate,
            bookFingerprint: locator.bookFingerprint,
            locator: locator,
            contextText: context,
            userPrompt: nil,
            targetLanguage: targetLanguage,
            promptVersion: "v1"
        )

        do {
            let response = try await aiService.sendRequest(request)
            // A superseded request must not write its result.
            guard !Task.isCancelled else { return }
            translatedText = response.content
            isLoading = false
        } catch {
            applyFailure(error.localizedDescription)
        }
    }

    /// Applies a failure outcome unless this task was superseded — a
    /// cancelled request must surface neither a result nor an error.
    private func applyFailure(_ message: String) {
        guard !Task.isCancelled else { return }
        errorMessage = message
        isLoading = false
    }

    /// Resets all state to initial values and cancels any in-flight
    /// translate.
    func reset() {
        translateTask?.cancel()
        translateTask = nil
        originalText = ""
        hasExplicitSelection = false  // Bug #314: cold reset → context-translate
        translatedText = nil
        errorMessage = nil
        isLoading = false
    }

    /// Feature #87 WI-2: user-triggered Stop of an in-flight translate. Cancels the
    /// task and clears `isLoading`; surfaces NO error (a user stop is not a failure
    /// — the post-`await` guard in `translate` + `applyFailure` already drop a
    /// cancelled task's result/error). Does NOT wipe `originalText`/`translatedText`
    /// (a Stop keeps any prior result; that's `reset()`'s job).
    func cancelStreaming() {
        translateTask?.cancel()
        translateTask = nil
        isLoading = false
    }
}
