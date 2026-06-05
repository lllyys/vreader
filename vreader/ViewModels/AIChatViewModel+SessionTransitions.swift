// Purpose: Feature #88 WI-3 — the chat-session TRANSITIONS for AIChatViewModel
// (switch / new / rename / delete) + their private helpers, split out of
// `AIChatViewModel+Sessions.swift` to keep both files under the ~300-line guide.
//
// Key decisions (Gate-4 structural fix):
// - EVERY public transition runs its mutating body through the single serialized
//   lane (`runSerializedSessionOp`, on the base class) so two session-mutating
//   ops can never interleave across an await on the @MainActor.
// - The SYNCHRONOUS pre-lane steps stay OUTSIDE the lane: cancel the in-flight
//   stream + bump `sessionTransitionToken` (+ stash `requestedSessionId` for
//   switch). This lets a rapid superseding op bump the token before the older
//   op's laned body runs, so the superseded body bails early on its token check.
// - DEADLOCK CONSTRAINT: a laned op body must NEVER call another laned PUBLIC op.
//   The internal helpers `sealCurrentSessionIfNeeded()` / `loadMostRecentRemaining`
//   are invoked WITHIN laned bodies, so they stay NON-laned.
//
// @coordinates-with: AIChatViewModel.swift, AIChatViewModel+Sessions.swift,
//   AIChatViewModel+Streaming.swift, ChatSessionPersisting.swift

import Foundation
import OSLog

private let transitionLog = Logger(subsystem: "com.vreader.app", category: "ChatSessions")

extension AIChatViewModel {

    // MARK: - Transitions

    /// Seals the current conversation and resets to the empty state. The former
    /// `clearHistory` toolbar entry point becomes this. Cancels any in-flight
    /// stream + bumps the transition token FIRST (so a late reply / in-flight load
    /// is discarded), seals the current session if it has content, then resets.
    func newConversation() async {
        cancelStreamingForTransition()        // synchronous — immediate stream abort, BEFORE the lane
        sessionTransitionToken &+= 1           // synchronous — a rapid superseding op bumps the token first
        let token = sessionTransitionToken
        await runSerializedSessionOp { await self._newConversation(token: token) }
    }

    private func _newConversation(token: UInt64) async {
        await sealCurrentSessionIfNeeded()
        guard token == sessionTransitionToken else { return }
        messages = []
        settledMessages = []
        activeSessionId = nil
        storedActiveTitle = nil   // #88 WI-4: a fresh thread derives its title from messages
        errorMessage = nil
    }

    /// Switches to a persisted session: saves the current thread (if it has
    /// content), loads the target, and replaces `messages` / `activeSessionId`.
    /// Cancels any in-flight stream + bumps the token + stashes `requestedSessionId`
    /// synchronously BEFORE the first await; re-checks both after every await so a
    /// rapid B→C switch lets the newer C win and abandons the older B load.
    func switchToSession(_ id: UUID) async {
        guard chatSessionStore != nil else { return }
        cancelStreamingForTransition()        // synchronous — immediate stream abort, BEFORE the lane
        sessionTransitionToken &+= 1           // synchronous — a rapid B→C switch bumps the token first
        requestedSessionId = id                // synchronous — so a superseded body bails on the id check
        let token = sessionTransitionToken
        await runSerializedSessionOp { await self._switchToSession(id, token: token) }
    }

    private func _switchToSession(_ id: UUID, token: UInt64) async {
        guard let store = chatSessionStore else { return }
        await sealCurrentSessionIfNeeded()
        guard transitionIsCurrent(token: token, id: id) else { return }
        do {
            guard let record = try await store.fetchChatSession(sessionId: id) else { return }
            guard transitionIsCurrent(token: token, id: id) else { return }
            messages = record.messages
            settledMessages = record.messages   // a loaded session is fully settled
            activeSessionId = record.sessionId
            storedActiveTitle = record.title    // #88 WI-4: the bar shows the stored title
            errorMessage = nil
        } catch {
            transitionLog.error("switchToSession failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Renames the active session (title only). A no-op when there is no active
    /// session or no store. Does not touch `messages` / `activeSessionId`.
    func renameActiveSession(_ title: String) async {
        guard chatSessionStore != nil else { return }
        await runSerializedSessionOp { await self._renameActiveSession(title) }
    }

    private func _renameActiveSession(_ title: String) async {
        guard let store = chatSessionStore, let id = activeSessionId else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await store.renameChatSession(sessionId: id, title: trimmed)
            // M1 follow-up (#88 WI-5): repaint the session bar — the active
            // session's stored title now wins over the derived one.
            storedActiveTitle = trimmed
        } catch {
            transitionLog.error("renameActiveSession failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Renames ANY session by id (the Conversations sheet's inline rename — #88
    /// WI-5). When the renamed session is the ACTIVE one, also updates
    /// `storedActiveTitle` so the session bar repaints. A no-op when there is no
    /// store or the trimmed title is empty/whitespace. Does not touch `messages`
    /// / `activeSessionId`. Routed through the serialized lane like every other
    /// session-mutating op.
    func renameSession(id: UUID, to title: String) async {
        guard chatSessionStore != nil else { return }
        await runSerializedSessionOp { await self._renameSession(id: id, to: title) }
    }

    private func _renameSession(id: UUID, to title: String) async {
        guard let store = chatSessionStore else { return }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await store.renameChatSession(sessionId: id, title: trimmed)
            // Repaint the bar only if the renamed session is the active one.
            if id == activeSessionId {
                storedActiveTitle = trimmed
            }
        } catch {
            transitionLog.error("renameSession failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Deletes a session. When the active one is deleted, falls back to the
    /// most-recent remaining NON-EMPTY session (or the empty state when none
    /// remain). Cancels any in-flight stream + bumps the token FIRST.
    func deleteSession(_ id: UUID) async {
        guard chatSessionStore != nil else { return }
        // Only a delete of the CURRENTLY-active session is a transition that must
        // abort the in-flight stream + supersede the active send (Gate-4 WI-3 r6
        // High): deleting an UNRELATED non-active session must NOT cancel the
        // active session's stream — that would bump `opCounter`, make `runSend`
        // skip its settled-turn save (`opId != opCounter`), and lose the active
        // session's latest turn (a later seal would then persist the older
        // snapshot). Non-active deletes still run through the serialized lane;
        // they just leave the active send untouched.
        if id == activeSessionId {
            cancelStreamingForTransition()    // synchronous — immediate stream abort, BEFORE the lane
            sessionTransitionToken &+= 1       // synchronous — a rapid superseding op bumps the token first
        }
        let token = sessionTransitionToken
        await runSerializedSessionOp { await self._deleteSession(id, token: token) }
    }

    private func _deleteSession(_ id: UUID, token: UInt64) async {
        guard let store = chatSessionStore else { return }
        // Captured inside the laned body: a prior op that drained ahead of this one
        // may have changed which session is active, so reflect the state at the
        // moment the delete actually runs.
        let wasActive = activeSessionId == id
        do {
            try await store.deleteChatSession(sessionId: id)
        } catch {
            transitionLog.error("deleteSession failed: \(String(describing: error), privacy: .public)")
            return
        }
        guard wasActive else { return }
        guard token == sessionTransitionToken else { return }
        // Reset locally first so a fallback failure still leaves a clean empty state.
        messages = []
        settledMessages = []
        activeSessionId = nil
        storedActiveTitle = nil   // #88 WI-4 (reset; loadMostRecentRemaining re-sets it if a session remains)
        errorMessage = nil
        await loadMostRecentRemaining(token: token)
    }

    // MARK: - Private helpers

    /// True iff the captured token + requested id still match the latest transition.
    private func transitionIsCurrent(token: UInt64, id: UUID) -> Bool {
        token == sessionTransitionToken && requestedSessionId == id
    }

    /// Saves the current thread to its session if it has content, so switching /
    /// starting a new conversation never loses the conversation being left. A no-op
    /// when the thread is empty (an empty thread is never persisted) or has no
    /// active session yet AND no content to lazily create from.
    ///
    /// NON-laned: it is called only from WITHIN a laned transition body — laning it
    /// would re-enter the chain head and deadlock.
    private func sealCurrentSessionIfNeeded() async {
        guard let store = chatSessionStore, let key = bookFingerprintKey else { return }
        // Seal the SETTLED snapshot, never the live `messages` — a cancelled
        // in-flight turn (the transition just `cancelStreamingForTransition`'d it)
        // is abandoned, not persisted (Gate-4 WI-3 High). No settled content (e.g.
        // a transition during the very first, still-in-flight turn) → no-op, so the
        // abandoned turn never even creates a session.
        let snapshot = settledMessages
        guard !snapshot.isEmpty else { return }
        let title = derivedTitle(from: snapshot)
        do {
            if let id = activeSessionId {
                // PRESERVE the stored title on seal-update (#88 WI-4 audit r2 Medium):
                // leaving a renamed session via new/switch must not revert its
                // persisted title to the first user message. Title is set only at
                // CREATE (below) + on rename (WI-5).
                _ = try await store.updateChatSession(sessionId: id, messages: snapshot, title: nil)
            } else {
                let record = try await store.createChatSession(
                    bookFingerprintKey: key, title: title ?? Self.defaultSessionTitle,
                    messages: snapshot)
                activeSessionId = record.sessionId
            }
        } catch {
            transitionLog.error("sealCurrentSession failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// After deleting the active session, loads the most-recent remaining NON-EMPTY
    /// session, else leaves the empty state. Re-checks the token before applying.
    /// NON-laned (called only from within the laned `_deleteSession`).
    private func loadMostRecentRemaining(token: UInt64) async {
        guard let store = chatSessionStore, let key = bookFingerprintKey else { return }
        do {
            let summaries = try await store.fetchChatSessionSummaries(forBookWithKey: key)
            guard token == sessionTransitionToken, activeSessionId == nil else { return }
            guard let target = summaries.first(where: { $0.messageCount > 0 }) else { return }
            guard let record = try await store.fetchChatSession(sessionId: target.id) else { return }
            guard token == sessionTransitionToken, activeSessionId == nil else { return }
            messages = record.messages
            settledMessages = record.messages   // a loaded session is fully settled
            activeSessionId = record.sessionId
            storedActiveTitle = record.title    // #88 WI-4: the bar shows the stored title
        } catch {
            transitionLog.error("loadMostRecentRemaining failed: \(String(describing: error), privacy: .public)")
        }
    }
}
