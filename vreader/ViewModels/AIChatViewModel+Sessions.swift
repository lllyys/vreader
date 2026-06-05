// Purpose: Feature #88 WI-3 — the chat-session lifecycle for AIChatViewModel,
// split out of the base file to keep it under the ~300-line guide. Owns the
// one-shot load, lazy create-on-first-turn, the settled-turn save, and the
// switch / new / rename / delete transitions — all guarded by the
// `sessionTransitionToken` so a late async load/fetch can't clobber a newer
// thread (Gate-2 rounds 3+4 async-race hardening).
//
// Key decisions:
// - nil `chatSessionStore` ⇒ every method is a no-op (general chat / tests keep
//   the pre-#88 ephemeral single thread).
// - `loadSessions()` is idempotent + non-clobbering: it runs at most once per
//   fingerprint key and never overwrites a non-empty / active local thread.
// - EVERY transition (switch/new/delete) AND the lazy-create-on-first-turn path
//   bumps `sessionTransitionToken` BEFORE its first await; each re-checks the
//   token after every await before applying, so a superseding transition (or a
//   just-started send) wins.
// - The settled-turn save is debounced (one write per settled turn, never per
//   streamed chunk) and runs from the streaming extension's placeholder cleanup.
//
// @coordinates-with: AIChatViewModel.swift, AIChatViewModel+Streaming.swift,
//   ChatSessionPersisting.swift, ChatSessionRecord.swift, ChatMessage.swift

import Foundation
import OSLog

private let sessionLog = Logger(subsystem: "com.vreader.app", category: "ChatSessions")

extension AIChatViewModel {

    /// The default title a fresh session carries until the first user message
    /// derives one. Mirrors `ChatSession.init`'s default.
    static let defaultSessionTitle = "New conversation"

    // MARK: - One-shot load

    /// Loads the most-recent NON-EMPTY persisted session for the current book into
    /// `messages` / `activeSessionId`, else leaves the designed empty state
    /// (`activeSessionId == nil`, `messages == []`) — an empty session is NEVER
    /// persisted on open. Idempotent + non-clobbering: a no-op when the store is
    /// nil, there is no book key, it has already run for this key, or local session
    /// state already exists. Owned by `ReaderAICoordinator` (one-shot after VM
    /// construction), NOT a view `.task` (which reruns on Chat-tab re-entry).
    ///
    /// Cold-open race (Gate-2 round-4): a user can send a first message before this
    /// fetch returns. The post-await + pre-apply re-checks (`activeSessionId == nil
    /// && messages.isEmpty && token == sessionTransitionToken`) abandon the load if
    /// a turn started meanwhile, so the just-started thread is never overwritten.
    func loadSessions() async {
        guard chatSessionStore != nil else { return }
        await runSerializedSessionOp { await self._loadSessions() }
    }

    private func _loadSessions() async {
        guard let store = chatSessionStore, let key = bookFingerprintKey else { return }
        guard loadedFingerprintKey != key else { return }
        guard activeSessionId == nil, messages.isEmpty else {
            // Local state already exists — record the key so a later call no-ops too.
            loadedFingerprintKey = key
            return
        }
        // Mark as run for this key up front so a concurrent load double-fetch can't
        // race; the token discipline below handles the load-vs-turn race.
        loadedFingerprintKey = key
        let token = sessionTransitionToken

        do {
            let summaries = try await store.fetchChatSessionSummaries(forBookWithKey: key)
            guard loadIsStillValid(token: token) else { return }
            guard let target = summaries.first(where: { $0.messageCount > 0 }) else {
                return  // no non-empty session → keep the empty state
            }
            guard let record = try await store.fetchChatSession(sessionId: target.id) else { return }
            guard loadIsStillValid(token: token) else { return }
            messages = record.messages
            settledMessages = record.messages   // a loaded session is fully settled
            activeSessionId = record.sessionId
            storedActiveTitle = record.title    // #88 WI-4: the bar shows the stored title
        } catch {
            sessionLog.error("loadSessions failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The cold-open guard: the load may apply ONLY if no turn started and no
    /// transition superseded it since the token was captured.
    private func loadIsStillValid(token: UInt64) -> Bool {
        activeSessionId == nil && messages.isEmpty && token == sessionTransitionToken
    }

    // MARK: - Lazy create + settled-turn save (called from +Streaming)

    /// Called synchronously at the START of a send when this is the first real user
    /// turn of an unsaved thread (`activeSessionId == nil`) on a book chat with a
    /// store. Bumps `sessionTransitionToken` so an in-flight `loadSessions` fails
    /// its re-check and cannot overwrite the just-started thread (Gate-2 round-4).
    /// The session row itself is created lazily on the settled-turn save.
    func noteFirstTurnStartedIfNeeded() {
        guard chatSessionStore != nil, bookFingerprintKey != nil, activeSessionId == nil else { return }
        sessionTransitionToken &+= 1
    }

    /// Persists the active conversation after a SETTLED turn. Debounced by the
    /// caller (runs once after the placeholder cleanup, never per chunk). Creates
    /// the session lazily on the first turn, updates it thereafter. Guarded by the
    /// streaming op identity + session identity captured at send time so a
    /// superseded / switched-away turn never writes to the wrong session.
    ///
    /// - Parameters:
    ///   - capturedSessionId: `activeSessionId` snapshot at send time. The save is
    ///     skipped if the active session changed (switch/new/delete) since then —
    ///     UNLESS it was nil at send time and is still nil now (the lazy-create case).
    func saveSettledTurn(capturedSessionId: UUID?) async {
        guard chatSessionStore != nil else { return }
        await runSerializedSessionOp { await self._saveSettledTurn(capturedSessionId: capturedSessionId) }
    }

    private func _saveSettledTurn(capturedSessionId: UUID?) async {
        guard let store = chatSessionStore, let key = bookFingerprintKey else { return }
        // The reply must still belong to the session it was sent for.
        guard activeSessionId == capturedSessionId else { return }
        guard !messages.isEmpty else { return }

        // Snapshot the transition token: a switch / new / delete that fires DURING
        // the create await must not have its empty-state reset clobbered by this
        // turn adopting a freshly-created session id (the create-vs-transition race).
        let token = sessionTransitionToken
        let snapshot = messages
        let title = derivedTitle(from: snapshot)
        do {
            if let id = activeSessionId {
                // Promote the settled snapshot to transition-visible state BEFORE the
                // persistence await (Gate-4 WI-3 r4 High): a `switch`/`new`/`delete`
                // racing this update must seal the FRESH snapshot, not the older one
                // — otherwise its seal would overwrite the just-settled turn with
                // stale data. (`messages` here is the same session's settled history,
                // so it's safe to promote eagerly.)
                settledMessages = snapshot
                // PRESERVE the stored title on update (#88 WI-4 audit r2 Medium):
                // pass `title: nil` so a later settled turn never reverts a renamed
                // (or otherwise stored-title-differs) session back to the first
                // user message. The title is set only at CREATE (below) + on rename
                // (WI-5). The store's carry-forward contract keeps the existing title
                // when `title == nil`.
                _ = try await store.updateChatSession(sessionId: id, messages: snapshot, title: nil)
            } else {
                let record = try await store.createChatSession(
                    bookFingerprintKey: key, title: title ?? Self.defaultSessionTitle,
                    messages: snapshot)
                // Adopt the new id ONLY if no transition superseded this turn during
                // the create await. Otherwise a `newConversation` / switch that fired
                // mid-create ABANDONED this turn — DELETE the just-created orphan row
                // (Gate-4 WI-3 High: a cancelled send must not leave a duplicate
                // session) and do not adopt it.
                guard token == sessionTransitionToken, activeSessionId == nil else {
                    // A transition abandoned this turn during the create await — roll
                    // back the orphan row. Best-effort + LOGGED (not swallowed): if the
                    // delete fails the orphan is a harmless abandoned (non-active)
                    // session, surfaced in the log rather than silently retained
                    // (Gate-4 WI-3 r2 Medium). Compensating, not atomic: a brief window
                    // exists between create-return and delete; acceptable for a
                    // low-stakes empty/abandoned chat row.
                    do {
                        try await store.deleteChatSession(sessionId: record.sessionId)
                    } catch {
                        sessionLog.error(
                            "saveSettledTurn orphan cleanup failed: \(String(describing: error), privacy: .public)")
                    }
                    return
                }
                activeSessionId = record.sessionId
                settledMessages = snapshot
                storedActiveTitle = title ?? Self.defaultSessionTitle   // #88 WI-4
            }
        } catch {
            sessionLog.error("saveSettledTurn failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The session title: derived from the first user message when the session is
    /// still on the default title (or unsaved); else nil (leave the stored title).
    /// `internal` (not `private`) so the `+SessionTransitions` seal path reuses it.
    func derivedTitle(from source: [ChatMessage]) -> String? {
        guard let firstUser = source.first(where: { $0.role == .user }) else { return nil }
        let trimmed = firstUser.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(Self.titleMaxLength))
    }

    static let titleMaxLength = 80

    // MARK: - Transitions moved to AIChatViewModel+SessionTransitions.swift
}
