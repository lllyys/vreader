// Purpose: The streaming + cancellation concern for AIChatViewModel (Feature #87
// WI-1), split out of the base file to keep it under the ~300-line guide.
//
// Key decisions:
// - `sendMessage(_:) async` is the SOLE public launcher (the view, DebugBridge,
//   and tests all call it). It OWNS the streaming Task internally: it cancels any
//   in-flight op, bumps the op counter, launches `runSend`, retains the handle,
//   and awaits it so callers keep completion semantics.
// - `cancelStreaming()` cancels the task and optimistically clears `isLoading` so
//   Stop stays responsive even while the whole-book pre-read await unwinds.
// - An operation counter (`opId == opCounter`) guards teardown + post-await
//   writes so a superseded (resent) op cannot clobber the newer op's state.
// - Streamed chunks are written into the assistant message by STABLE id
//   (`ChatMessage.id`), never a raw array index across awaits — a concurrent
//   clearHistory()/resend cannot corrupt the wrong row.
//
// @coordinates-with: AIChatViewModel.swift, AIChatView+Composer.swift,
//   ChatMessage.swift, AIService.swift, AgenticChatDriver.swift

import Foundation

extension AIChatViewModel {

    // MARK: - Public launch + cancel API

    /// Sends a user message and streams the AI response incrementally.
    /// Empty or whitespace-only messages are silently ignored.
    ///
    /// Feature #87 WI-1: the single public launcher OWNS the streaming Task — it
    /// supersedes any in-flight op (resend), tags this op with a monotonic id,
    /// launches `runSend`, retains the handle for `cancelStreaming()`, and awaits
    /// it so callers (view / DebugBridge / tests) keep completion semantics.
    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        streamTask?.cancel()                 // supersede any in-flight op
        opCounter &+= 1
        let opId = opCounter
        let task = Task { await self.runSend(trimmed, opId: opId) }
        streamTask = task
        await task.value                     // callers still get completion semantics
    }

    /// Aborts the in-flight stream, keeping any partial assistant reply. Idempotent
    /// (a no-op when nothing is in flight). Clears `isLoading` immediately so the
    /// Stop affordance is responsive even during the whole-book pre-read await —
    /// the cancelled task's post-await guards discard any late work.
    func cancelStreaming() {
        streamTask?.cancel()
        isLoading = false
    }

    /// Feature #88 (Gate-2 High 3): the FIRST step of every session transition —
    /// cancel the in-flight stream AND bump `opCounter` so a late provider reply
    /// from the superseded op cannot land in (or seal) the new / deleted session.
    /// The in-flight `runSend`'s post-await `opId == opCounter` guards then discard
    /// its placeholder cleanup write + its settled-turn save. Distinct from
    /// `cancelStreaming()` (the Stop button), which keeps the op id stable so the
    /// stopped turn's partial is still saved as a real turn.
    func cancelStreamingForTransition() {
        cancelStreaming()
        opCounter &+= 1
    }

    // MARK: - Send pipeline

    /// One send operation. `opId` tags this op so a superseded predecessor's late
    /// teardown / writes can be discarded (`opId == opCounter`).
    private func runSend(_ trimmed: String, opId: UInt64) async {
        // Gate-4 r2 High: if this op was cancelled or superseded BEFORE its child
        // task got to run, bail before ANY state mutation — no ghost user turn, no
        // stray errorMessage clear. (The launcher cancels + bumps opCounter
        // synchronously; this task starts a hop later.)
        guard !Task.isCancelled, opId == opCounter else { return }

        // Clear previous error
        errorMessage = nil

        // Feature #88: if this is the first real turn of an unsaved thread, bump the
        // session transition token NOW (synchronously, before any await) so an
        // in-flight loadSessions fails its post-await re-check and cannot overwrite
        // the thread this turn is starting (cold-open race, Gate-2 round-4). Snapshot
        // the active session id so the settled-turn save only writes if the reply
        // still belongs to the session it was sent for (streaming handoff guard).
        noteFirstTurnStartedIfNeeded()
        let sessionAtSend = activeSessionId

        // Add user message to history
        let userMessage = ChatMessage(role: .user, content: trimmed)
        messages.append(userMessage)

        isLoading = true
        // Teardown keyed to operation identity: a superseded op's late defer must
        // not clobber the current op's isLoading / streamTask (plan H2).
        defer { if opId == opCounter { isLoading = false; streamTask = nil } }

        // Feature #86 WI-5b: the Whole-book scope reads on the FIRST question
        // ("reads on your next question"). Trigger the on-demand read and await it
        // so the digest is folded into `bookContext` before the answer is built.
        if scope == .wholeBook, let retrieval = wholeBookRetrieval, !retrieval.isReady {
            await onWholeBookReadRequested?()
        }

        // Feature #87 WI-1 (round-3 High): a Stop during the whole-book pre-read
        // must land no reply. The pre-read await unwinds even after cancel
        // (WholeBookRetrievalViewModel.cancel() does not force-kill the read), so
        // guard BEFORE the citation snapshot / placeholder append / provider start.
        guard !Task.isCancelled, opId == opCounter else { return }

        // Feature #86 WI-6: SNAPSHOT the citations the context drew on, AFTER any
        // whole-book read (so the snapshot reflects the digest) but BEFORE the
        // async stream — so a scope/source change mid-send can't mis-stamp the reply.
        let citationSnapshot = pendingCitations

        // Build context from conversation history (sliding window)
        let contextText = buildContextText()

        let request = AIRequest(
            actionType: .questionAnswer,
            bookFingerprint: bookFingerprint,
            locator: nil,
            contextText: contextText,
            userPrompt: trimmed,
            targetLanguage: nil,
            promptVersion: "v1"
        )

        // Create an empty assistant message (stamped with the citation snapshot)
        // for incremental streaming. Write by STABLE id, never index.
        let assistantMessage = ChatMessage(role: .assistant, content: "", citations: citationSnapshot)
        let assistantId = assistantMessage.id
        messages.append(assistantMessage)

        do {
            // Feature #91: when `agenticTools` is on (live) AND a non-empty registry is
            // injected, resolve the provider ONCE. If it supports tool-use, run the
            // agentic loop; otherwise stream through the SAME pinned config (no second
            // resolution — Gate-4 Medium). Otherwise the default streaming path.
            if featureFlags.agenticTools, let registry = agenticRegistry, !registry.isEmpty {
                let (config, supportsToolUse) = try await aiService.resolveToolProvider()
                if supportsToolUse {
                    try await runAgenticTurn(
                        assistantId: assistantId, opId: opId, config: config, registry: registry)
                } else {
                    try await consumeStream(
                        aiService.streamRequest(request, using: config), into: assistantId)
                }
            } else {
                try await consumeStream(aiService.streamRequest(request), into: assistantId)
            }
        } catch is CancellationError {
            // A user Stop is not an error — keep any partial; surface no errorMessage.
        } catch let aiError as AIError {
            // Cooperative cancel (Gate-4 High): a cancelled or superseded op must
            // not surface a stale provider error — the contract is "user cancel is
            // not an error". Only the current, live op writes error state.
            if !Task.isCancelled, opId == opCounter { errorMessage = aiError.localizedDescription }
        } catch {
            if !Task.isCancelled, opId == opCounter { errorMessage = error.localizedDescription }
        }

        // Cleanup (plan C2): remove the assistant placeholder iff its content is
        // still empty — UNCONDITIONALLY (cancel-before-chunk → empty → removed;
        // cancel-mid-stream → non-empty → kept; provider returned nothing → removed).
        if let assistant = message(withId: assistantId), assistant.content.isEmpty {
            removeMessage(withId: assistantId)
        }

        // Bug #323: the user-visible turn is DONE the moment the reply has settled.
        // Reset the composer state HERE — BEFORE the persistence save — so a stalled
        // session-op lane (e.g. a slow cold-store `loadSessions()` still parked ahead
        // of this turn's save on the serialized `sessionOpChain`) can NEVER keep
        // `isLoading` true and freeze the composer. Pre-fix this reset lived only in
        // the trailing `defer`, which runs at scope exit — AFTER the awaited save
        // below — so a stuck save left `isLoading == true`, the Send button disabled
        // (`canSend` ⇒ `!isLoading`), and the user unable to send the next message.
        // The `defer` remains the safety net for the early cancel/guard returns
        // above; this is the normal-completion reset.
        if opId == opCounter {
            isLoading = false
            streamTask = nil
        }

        // Feature #88: persist the SETTLED turn (debounced — one write here, never
        // per chunk). Still AWAITED so callers/tests observe the write, but it no
        // longer gates the composer (reset above): a slow/stuck save jams only the
        // persistence lane, never the chat (Bug #323). Only the CURRENT, live op
        // writes: a superseded (resent) op must not save (opId != opCounter), and the
        // save itself re-checks that the active session still matches the one
        // captured at send time (a switch / new / delete mid-send cancelled this op +
        // changed the active session, so its reply must not land in — or seal — the
        // wrong session). A cancelled op that kept a partial reply is still a real
        // turn worth saving, so we do NOT gate on `Task.isCancelled` here — only on
        // op + session identity.
        if opId == opCounter {
            await saveSettledTurn(capturedSessionId: sessionAtSend)
        }
    }

    /// Consume a stream into the assistant message (by stable id), stopping early
    /// if the op is cancelled.
    ///
    /// Bug #323: streamed deltas are COALESCED (`StreamCoalescer`) so the
    /// `@Observable messages` array is re-published at a capped rate (~30/s or per
    /// ~96 chars) instead of on every token. Per-token mutation re-rendered the
    /// entire transcript on every token and saturated the main thread on long
    /// replies → whole-app freeze. The first token still shows promptly, the final
    /// remainder is drained on completion, and nothing is lost.
    private func consumeStream(
        _ stream: AsyncThrowingStream<AIStreamChunk, Error>, into assistantId: UUID
    ) async throws {
        var coalescer = StreamCoalescer()
        // Bug #323 (Codex audit High): drain on EVERY exit path — normal completion,
        // a `break` on Stop, OR a thrown CancellationError / provider error. A throw
        // would otherwise skip the post-loop drain and drop the last buffered batch,
        // regressing the "keep the partial reply" contract (pre-fix, each token was
        // appended immediately, so a throw kept everything received so far).
        do {
            for try await chunk in stream {
                if Task.isCancelled { break }
                if let flush = coalescer.accept(chunk.text, now: DispatchTime.now().uptimeNanoseconds) {
                    appendToAssistant(id: assistantId, flush)
                }
            }
        } catch {
            if let remainder = coalescer.drain() {
                appendToAssistant(id: assistantId, remainder)
            }
            throw error
        }
        if let remainder = coalescer.drain() {
            appendToAssistant(id: assistantId, remainder)
        }
    }

    /// Feature #91: run the bounded agentic loop through the PINNED `config` and
    /// write the single final answer into the assistant message. Suppresses the
    /// "Drew on" citation stamp on a tool-driven reply (the pre-send snapshot
    /// doesn't reflect what tools read — Gate-2 Medium 3).
    private func runAgenticTurn(
        assistantId: UUID, opId: UInt64, config: ResolvedAIProviderConfig, registry: AIToolRegistry
    ) async throws {
        // The empty assistant placeholder appended above is dropped by the mapper,
        // so the history ends on the user's prompt; the current book's UNTRUSTED
        // context rides as a leading user turn.
        var history = AIChatHistoryMapper.toolTurns(from: messages, window: contextWindowSize)
        if let prelude = AIChatHistoryMapper.contextPrelude(bookContext: bookContext) {
            history.insert(prelude, at: 0)
        }
        let result = try await AgenticChatDriver().run(
            systemPrompt: AIChatHistoryMapper.systemPrompt(),
            history: history,
            registry: registry,
            provider: AIServiceToolUseAdapter(service: aiService, config: config),
            maxTokens: config.maxTokens)

        // Feature #87 WI-1 (round-2 High): Swift cancellation is cooperative — a
        // task cancelled AFTER the driver already returned would still write a full
        // reply. Guard before mutating the assistant message (agentic Stop = abort,
        // no partial).
        guard !Task.isCancelled, opId == opCounter else { return }

        if let assistant = message(withId: assistantId) {
            var updated = assistant
            updated.content = result.finalText
            if result.usedTools { updated.citations = [] }
            replaceMessage(updated)
        }
    }

    // MARK: - id-based message writes (plan H4 / C2)

    /// Returns the message with `id`, or nil if it no longer exists.
    private func message(withId id: UUID) -> ChatMessage? {
        messages.first { $0.id == id }
    }

    /// Appends `text` to the assistant message identified by `id`. If the message
    /// no longer exists (cleared / resent), stops writing silently.
    private func appendToAssistant(id: UUID, _ text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].content += text
    }

    /// Replaces the stored message that shares `updated.id`. No-op if it is gone.
    private func replaceMessage(_ updated: ChatMessage) {
        guard let index = messages.firstIndex(where: { $0.id == updated.id }) else { return }
        messages[index] = updated
    }

    /// Removes the message with `id` if present.
    private func removeMessage(withId id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages.remove(at: index)
    }

    // MARK: - Context building

    /// Builds a serialized context string from the recent conversation history.
    /// Uses the sliding window to limit context size.
    /// When `bookContext` is set, prepends it as a "[Book Context]" section.
    private func buildContextText() -> String {
        var parts: [String] = []

        // Prepend book context if available
        if let ctx = bookContext, !ctx.isEmpty {
            parts.append("[Book Context]\n\(ctx)")
        }

        let windowMessages = recentMessages()
        if !windowMessages.isEmpty {
            let historyText = windowMessages.map { msg in
                let roleLabel: String
                switch msg.role {
                case .user: roleLabel = "User"
                case .assistant: roleLabel = "Assistant"
                case .system: roleLabel = "System"
                }
                return "\(roleLabel): \(msg.content)"
            }.joined(separator: "\n")
            parts.append(historyText)
        }

        return parts.joined(separator: "\n\n")
    }

    /// Returns the most recent messages within the context window size.
    private func recentMessages() -> [ChatMessage] {
        if messages.count <= contextWindowSize {
            return messages
        }
        return Array(messages.suffix(contextWindowSize))
    }
}
