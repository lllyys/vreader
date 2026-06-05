// Purpose: Feature #87 WI-3 — the request-lifecycle / Stop concern for
// `AIAssistantViewModel`, split out of the base file to keep it under the
// ~300-line guide.
//
// The Summarize VM did NOT own a live task before #87 WI-3: `performAction`
// awaited a one-shot `sendRequest` inline and wrote `.complete` UNGUARDED,
// and `streamTask` was vestigial (never assigned). This extension makes the
// request a retained, cancellable Task and adds the user-triggered Stop:
//
// - `streamTask = Task { … }` around `sendRequest` (the task is now real).
// - A monotonic `opId`/`opCounter` token; EVERY post-`await` write is gated
//   on `!Task.isCancelled, opId == opCounter` (the `AITranslationViewModel`
//   precedent) — a cancelled one-shot request can RETURN NORMALLY from the
//   provider, so the guard, not just a `CancellationError` catch, is what
//   prevents a stale `.complete` write.
// - The regenerate-preserve contract: `performAction` clears `responseText`
//   before launch, so a naive `.idle` on Stop would drop a prior summary on
//   a regenerate. The prior `.complete` is snapshotted before clearing and
//   restored by `cancelStreaming()` when present.
//
// Stored properties (`streamTask`, `opCounter`, `priorCompletedSummary`)
// cannot live in an extension — they stay in the base class body as
// `@ObservationIgnored internal` so this file can mutate them.
//
// @coordinates-with: AIAssistantViewModel.swift, AIService.swift,
//   AIContextExtracting.swift, AISummaryTabView.swift

import Foundation

extension AIAssistantViewModel {

    // MARK: - Stop

    /// Feature #87 WI-3: user-triggered Stop of an in-flight summarize.
    /// A one-shot `sendRequest` cannot keep a partial result — so Stop is
    /// abort, not partial-keep.
    ///
    /// Regenerate-preserve contract: `performAction` clears `responseText`
    /// before launch, so a naive `.idle` here would drop a previously-
    /// completed summary on a REGENERATE. When the in-flight request was a
    /// regenerate (`priorCompletedSummary != nil`), restore that prior
    /// `.complete` summary; otherwise (an INITIAL summarize) return to the
    /// `.idle` prompt. No error is surfaced — a user Stop is not a failure
    /// (the post-`await` guard in `runRequest` drops the cancelled task's
    /// result anyway).
    func cancelStreaming() {
        // Gate-4 Medium: idempotent — a Stop is meaningful ONLY while a request is
        // in flight (`state == .loading`). A stray/late call after the request has
        // settled (`.complete`/`.error`/`.idle`) must NOT wipe a completed summary
        // back to `.idle`.
        guard case .loading = state else { return }
        streamTask?.cancel()
        streamTask = nil
        // Bump so the cancelled task's post-`await` guard fails even if it
        // returns normally from the provider.
        opCounter &+= 1
        if let prior = priorCompletedSummary {
            responseText = prior
            state = .complete
        } else {
            responseText = ""
            state = .idle
        }
        priorCompletedSummary = nil
        currentAction = nil
    }

    // MARK: - Request lifecycle

    func performAction(
        type: AIActionType,
        locator: Locator,
        fullText: String,
        format: BookFormat,
        scope: SummaryScope = .section,
        chapterBounds: ChapterBounds? = nil,
        userPrompt: String? = nil,
        targetLanguage: String? = nil
    ) async {
        // Supersede any pending request, and bump the op token so a stale
        // task's post-`await` writes are dropped.
        streamTask?.cancel()
        streamTask = nil
        opCounter &+= 1
        let opId = opCounter

        // Feature #90 WI-1 (Gate-4 r1 High): a fresh action (incl. a
        // re-summarize) must invalidate any in-flight bilingual-summary
        // translation BEFORE `responseText` is cleared, so a translation of the
        // OLD summary cannot land stale against the NEW one. (`reset()` already
        // does this for the dismiss path; re-summarize goes through here, not
        // `reset()`.)
        cancelSummaryTranslation()

        // Regenerate-preserve snapshot (feature #87 WI-3): capture the
        // currently-completed summary BEFORE `responseText` is cleared so
        // `cancelStreaming()` can restore it if this request is a Stop'd
        // regenerate. `nil` for an initial summarize (Stop → `.idle`).
        priorCompletedSummary = (state == .complete && !responseText.isEmpty)
            ? responseText
            : nil

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
            priorCompletedSummary = nil
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

        // Own the request Task so a Stop / supersede can cancel it. The
        // outer method stays `async` (awaits the task it owns) so callers
        // still see settled state on return.
        let task = Task { await self.runRequest(request, opId: opId) }
        streamTask = task
        await task.value
    }

    /// Runs one `sendRequest` and applies its result — but only if this
    /// task is still current and not cancelled. Swift cancellation is
    /// cooperative: a cancelled one-shot request can still RETURN NORMALLY
    /// from the provider, so EVERY post-`await` write is gated on
    /// `!Task.isCancelled, opId == opCounter` (the
    /// `AITranslationViewModel` precedent). A `CancellationError` is
    /// swallowed — `cancelStreaming()` owns the terminal state.
    private func runRequest(_ request: AIRequest, opId: UInt64) async {
        // Nil the owned task once this op settles (so a settled request doesn't
        // leave `streamTask` pointing at a completed task — Gate-4 Medium).
        defer { if opId == opCounter { streamTask = nil } }
        // Entry guard (Gate-4 Medium): if this op was cancelled/superseded before
        // its child task actually ran, don't even make the provider request — the
        // post-`await` guards alone would still let a dropped request consume
        // provider work + populate cache. @MainActor reentrancy makes the
        // "performAction awaits task.value" rationale insufficient.
        guard !Task.isCancelled, opId == opCounter else { return }
        do {
            let response = try await aiService.sendRequest(request)
            guard !Task.isCancelled, opId == opCounter else { return }
            priorCompletedSummary = nil
            responseText = response.content
            state = .complete
        } catch is CancellationError {
            return
        } catch let error as AIError {
            guard !Task.isCancelled, opId == opCounter else { return }
            priorCompletedSummary = nil
            switch error {
            case .featureDisabled:
                state = .featureDisabled
            case .consentRequired:
                state = .consentRequired
            default:
                state = .error(error.localizedDescription)
            }
        } catch {
            guard !Task.isCancelled, opId == opCounter else { return }
            priorCompletedSummary = nil
            state = .error(error.localizedDescription)
        }
    }
}
