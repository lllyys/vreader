// Purpose: Feature #90 WI-1 — the bilingual-summary concern for
// `AIAssistantViewModel`, split out of the base file to keep both under the
// ~300-line guide.
//
// The Summarize tab produces a single-language summary. #90 lets the user show
// that summary as-produced (`.originalOnly`), translated to a target
// `BilingualLanguage` (`.translatedOnly`), or both stacked (`.interlinear`).
// The translation is a SECOND step over the GENERATED SUMMARY (`responseText`),
// kept in a SEPARATE sub-state (`summaryTranslation`) so the summary ships even
// if its translation is pending / failed.
//
// Key decisions:
// - The display mode is a 3-way enum of CONCRETE OBSERVABLE OUTPUTS (Gate-2
//   H1): `.originalOnly` (the summary exactly as produced, the default, NO
//   translation), `.translatedOnly`, `.interlinear`. There is no
//   "reader-language" authority in the codebase.
// - The setters are SYNCHRONOUS pure mutators (mirror `setScope`); a separate
//   `async refreshSummaryTranslationIfNeeded()` is what kicks the (re)translation.
// - The translate step uses a dedicated PRIVATE helper via
//   `aiService.sendRequest(.translate …)` — NOT public `translate()`/
//   `performAction()` (those clear `responseText` + rewrite `state`/
//   `currentAction`, destroying the summary). The result lands ONLY in
//   `summaryTranslation`; `responseText`/`state`/`currentAction` are never touched.
// - The translation half owns its OWN cancellable task + monotonic token
//   (`summaryTranslationTask`/`summaryTranslationToken`, in the base class). A
//   re-summarize / mode-flip / language change cancels + bumps the token so a
//   superseded translation's post-`await` write is dropped (the #87 pattern).
// - `cancelSummaryTranslation()` is called from `reset()` (base file) so a
//   translation cannot outlive reset/dismiss and write stale state.
//
// @coordinates-with: AIAssistantViewModel.swift, AIService.swift,
//   BilingualLanguage.swift, AISummaryCard.swift (WI-3), AISummaryTabView.swift (WI-2)

import Foundation

/// How the completed summary is presented (feature #90 WI-1). Concrete,
/// observable outputs — no "reader-language" comparison (Gate-2 H1).
enum SummaryDisplayMode: Sendable, Equatable {
    /// The summary EXACTLY as the model produced it. No translation. Default.
    case originalOnly
    /// Translate the summary to the target language; show ONLY the translation.
    case translatedOnly
    /// Show BOTH the original and the translation, stacked.
    case interlinear
}

/// The second-step translation sub-state (feature #90 WI-1). Independent of
/// `AIAssistantState`/`responseText` so the summary can ship while its
/// translation independently loads / completes / fails.
enum SummaryTranslationState: Sendable, Equatable {
    case none
    case translating
    case translated(String)
    case failed
}

extension AIAssistantViewModel {

    // MARK: - Synchronous setters (pure mutators — no async work)

    /// Updates the summary display mode. Pure mutator — does NOT run the
    /// translation (the view calls `refreshSummaryTranslationIfNeeded()` after).
    /// Flipping AWAY from a translated mode tears down any in-flight translation
    /// so a stale result cannot land on the now-original-only summary.
    func setSummaryDisplayMode(_ mode: SummaryDisplayMode) {
        guard mode != summaryDisplayMode else { return }
        summaryDisplayMode = mode
        if mode == .originalOnly {
            cancelSummaryTranslation()
        }
    }

    /// Updates the bilingual target language. Pure mutator — does NOT re-run the
    /// translation. Changing the language invalidates any in-flight/finished
    /// translation (it targeted the old language); the view re-kicks via
    /// `refreshSummaryTranslationIfNeeded()`.
    func setSummaryTargetLanguage(_ language: BilingualLanguage) {
        guard language != summaryTargetLanguage else { return }
        summaryTargetLanguage = language
        cancelSummaryTranslation()
    }

    // MARK: - Translation trigger

    /// Kicks (or re-kicks) the summary translation IFF the mode needs it AND a
    /// completed summary exists. No-op for `.originalOnly`, or before a summary
    /// has completed. Supersedes any in-flight translation (the #87 op-token
    /// pattern) so the latest mode/language wins.
    func refreshSummaryTranslationIfNeeded() async {
        guard summaryDisplayMode != .originalOnly else {
            cancelSummaryTranslation()
            return
        }
        guard hasCompletedSummary else { return }
        await runSummaryTranslation()
    }

    /// Re-runs ONLY the translation half (recovery from `.failed`). Same guards
    /// + op-token discipline as `refreshSummaryTranslationIfNeeded`.
    func retrySummaryTranslation() async {
        guard summaryDisplayMode != .originalOnly, hasCompletedSummary else { return }
        await runSummaryTranslation()
    }

    /// Cancels the in-flight translation task and resets the sub-state to
    /// `.none`. Called from `reset()` (base file) + any sheet teardown so a
    /// translation cannot outlive dismiss and write stale state. Bumps the
    /// token so a cancelled-but-returning translate cannot clobber.
    func cancelSummaryTranslation() {
        summaryTranslationTask?.cancel()
        summaryTranslationTask = nil
        summaryTranslationToken &+= 1
        summaryTranslation = .none
    }

    // MARK: - Private

    /// Whether a completed summary is available to translate.
    private var hasCompletedSummary: Bool {
        state == .complete && !responseText.isEmpty
    }

    /// Launches the translation of the CURRENT summary into
    /// `summaryTargetLanguage`, owning the task + token so a supersede/cancel
    /// drops a stale write. Awaits the task so callers see settled sub-state.
    private func runSummaryTranslation() async {
        // Supersede any in-flight translation and bump the token.
        summaryTranslationTask?.cancel()
        summaryTranslationTask = nil
        summaryTranslationToken &+= 1
        let token = summaryTranslationToken

        let summary = responseText
        let language = summaryTargetLanguage.key

        summaryTranslation = .translating

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSummaryTranslation(summary: summary, language: language, token: token)
        }
        summaryTranslationTask = task
        await task.value
    }

    /// Sends the dedicated `.translate` request over the GENERATED SUMMARY and
    /// stores the result ONLY in `summaryTranslation`. Never touches
    /// `responseText`/`state`/`currentAction`. Every post-`await` write is gated
    /// on `!Task.isCancelled && token == summaryTranslationToken` so a
    /// superseded/cancelled translation is dropped (the #87 pattern).
    private func performSummaryTranslation(summary: String, language: String, token: UInt64) async {
        // Entry guard: cancelled/superseded before the child task ran.
        guard !Task.isCancelled, token == summaryTranslationToken else { return }

        let request = AIRequest(
            actionType: .translate,
            bookFingerprint: nil,
            locator: nil,
            contextText: summary,
            userPrompt: nil,
            targetLanguage: language,
            promptVersion: "v1"
        )

        do {
            let response = try await aiService.sendRequest(request)
            guard !Task.isCancelled, token == summaryTranslationToken else { return }
            summaryTranslation = .translated(response.content)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, token == summaryTranslationToken else { return }
            summaryTranslation = .failed
        }
    }
}
