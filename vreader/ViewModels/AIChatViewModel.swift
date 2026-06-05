// Purpose: ViewModel for multi-turn AI chat conversations.
// Manages conversation history, context window, and book context injection.
//
// Key decisions:
// - @Observable + @MainActor for SwiftUI integration.
// - Sliding window: only last N messages sent as context to the AI.
// - Full message history preserved in `messages` for display.
// - Book context text injected via bookContext property (set by reader container).
// - When bookContext is set, it is prepended as "[Book Context]" in the contextText.
// - bookFingerprint is set on the AIRequest for cache key differentiation.
// - Empty/whitespace messages are silently ignored.
// - On error: user message preserved, errorMessage set, conversation continues.
// - Context text for AIRequest is built by serializing book context + conversation history.
//
// @coordinates-with: ChatMessage.swift, AIService.swift, AIChatView.swift

import Foundation

/// ViewModel for multi-turn AI chat conversations.
@Observable
@MainActor
final class AIChatViewModel {

    // MARK: - Published State

    /// Full conversation history (for display).
    /// `internal(set)` so the streaming extension (`+Streaming`) can mutate it.
    internal(set) var messages: [ChatMessage] = []

    // MARK: - Feature #88 session state

    /// The persisted session currently shown, or nil for the empty (not-yet-saved)
    /// state. The setter is `internal` so the session lifecycle (`+Sessions`) and
    /// the streaming save hook (`+Streaming`) — extensions that cannot add stored
    /// properties — can update it. Drives the WI-4 session bar.
    internal(set) var activeSessionId: UUID?

    /// The STORED title of the active session (set when a session is loaded /
    /// switched-to / its first turn creates it; WI-5's rename updates it). Nil for
    /// an unsaved / fresh thread — then `activeSessionTitle` derives from the
    /// thread instead. Observed so the session bar repaints on a switch/rename.
    /// `internal(set)` so the `+Sessions` / `+SessionTransitions` lifecycle sets it.
    internal(set) var storedActiveTitle: String?

    /// The active conversation's display title for the session bar (#88 WI-4): the
    /// loaded/switched/renamed session's STORED title wins; otherwise the derived
    /// title of the in-progress thread (the title it will be saved under), else the
    /// default for a fresh/empty thread. Reading `messages` keeps it observed so the
    /// bar updates live as the first turn is typed.
    var activeSessionTitle: String {
        storedActiveTitle ?? derivedTitle(from: messages) ?? Self.defaultSessionTitle
    }

    // Feature #88 session plumbing. Stored on the base class (extensions cannot add
    // stored properties); `internal` so `+Sessions` / `+Streaming` reach them;
    // `@ObservationIgnored` keeps them out of SwiftUI observation (internal
    // plumbing, not rendered state — mirrors `streamTask`/`opCounter`).

    /// Idempotency guard for the one-shot `loadSessions()` — once it has run for a
    /// fingerprint key it never re-loads (a Chat-tab re-entry must not clobber a
    /// fresh / unsaved thread).
    @ObservationIgnored var loadedFingerprintKey: String?

    /// Monotonic token bumped synchronously at the START of every session
    /// transition (switch / new / delete) AND the lazy-create-on-first-turn path.
    /// Each transition re-checks `token == sessionTransitionToken` after every
    /// await before applying — so a newer transition (or a just-started turn)
    /// supersedes an in-flight older load/switch (Gate-2 rounds 3+4).
    @ObservationIgnored var sessionTransitionToken: UInt64 = 0

    /// The session id the most-recent `switchToSession(_:)` requested, stashed
    /// synchronously before its first await so a rapid B→C switch can detect that
    /// an older B load was superseded (paired with the token).
    @ObservationIgnored var requestedSessionId: UUID?

    /// The messages as of the LAST successfully-settled-and-persisted turn (or a
    /// freshly loaded session). A transition (`switch`/`new`/`delete`) seals THIS
    /// snapshot — never the live `messages` — so a cancelled in-flight turn
    /// (partial / empty assistant) is abandoned, not saved into the old session
    /// (Gate-4 WI-3 High). Empty until the first turn settles.
    @ObservationIgnored var settledMessages: [ChatMessage] = []

    /// Whether a request is currently in flight.
    /// `internal(set)` so the streaming extension can clear it on cancel.
    internal(set) var isLoading: Bool = false

    // Feature #87 WI-1: the in-flight streaming task + an operation counter for
    // the resend race guard. Stored here (extensions cannot add stored
    // properties); `@ObservationIgnored` keeps them out of SwiftUI observation
    // (they are internal plumbing, not rendered state). Mutated by the launcher
    // + cancel API in `AIChatViewModel+Streaming.swift`.
    @ObservationIgnored var streamTask: Task<Void, Never>?
    @ObservationIgnored var opCounter: UInt64 = 0

    // Feature #88 WI-3 (Gate-4 structural fix): the single serialized lane every
    // session-mutating op runs through, so two ops can never interleave across an
    // `await` on the @MainActor (the whole lost-message / wrong-active-session /
    // duplicate-orphan / stuck-load interleaving-race class). Stored on the base
    // class (extensions cannot add stored properties); `@ObservationIgnored`
    // keeps it out of SwiftUI observation (internal plumbing).
    @ObservationIgnored private var sessionOpChain: Task<Void, Never>?

    /// Runs `body` on a single serialized lane: it waits for the prior session op
    /// to FULLY complete (across its awaits) before running, so two
    /// session-mutating ops can never interleave. Runs on the @MainActor; the
    /// prior task is captured synchronously, so the ordering is the call order.
    ///
    /// DEADLOCK CONSTRAINT: a laned op's body must NEVER call another laned PUBLIC
    /// op — that would `await` the current chain head (this op) and deadlock. The
    /// internal helpers `sealCurrentSessionIfNeeded()` / `loadMostRecentRemaining`
    /// are invoked WITHIN laned bodies, so they stay NON-laned.
    func runSerializedSessionOp(_ body: @escaping @MainActor () async -> Void) async {
        let prior = sessionOpChain
        let task = Task { @MainActor in
            await prior?.value
            await body()
        }
        sessionOpChain = task
        await task.value
    }

    /// Error message from the last failed request, nil if no error.
    var errorMessage: String?

    /// Feature #78 (Ask-AI on selection): a one-shot pre-fill for the chat
    /// INPUT field. When a user taps "Ask AI" on a text selection, the reader
    /// host seeds this with the selected text; `AIChatView` consumes it into its
    /// input (NOT auto-sent — the user edits/frames the question), then clears
    /// it. Nil when there is nothing pending. Set only via `seedInput(_:)`.
    private(set) var seededInput: String?

    /// Seeds the chat input with `text` (one-shot; consumed + cleared by the
    /// view). Whitespace-only / empty text is ignored (no seed).
    func seedInput(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        seededInput = text
    }

    /// Clears any pending seed without applying it (the view calls this once it
    /// has decided whether to consume the seed — see `AIChatView`).
    func clearSeed() {
        seededInput = nil
    }

    // MARK: - Configuration

    /// Book fingerprint for book-context mode. Nil = general chat.
    let bookFingerprint: DocumentFingerprint?

    /// Maximum number of messages to include in the AI context window.
    let contextWindowSize: Int

    /// Current book content text for context injection.
    /// Set by the reader container with the visible section/chapter/page text.
    /// When non-nil and non-empty, prepended as "[Book Context]" in the AI request.
    var bookContext: String?

    /// Feature #86 WI-3: the breadth of book text the Chat tab reads. Drives the
    /// context-bar scope chip. Changing it (via `setScope`) re-assembles
    /// `bookContext` through `onScopeChanged` (the coordinator's single funnel).
    /// Default `.chapter` matches the shipped WI-1 behavior.
    private(set) var scope: ChatContextScope = .chapter

    /// Set by the reader coordinator: invoked after a scope change so the
    /// coordinator re-computes `bookContext` for the new scope.
    var onScopeChanged: (() -> Void)?

    /// Selects a new Chat context scope and re-assembles the book context.
    /// A no-op when the scope is unchanged (avoids a redundant re-assembly).
    func setScope(_ newScope: ChatContextScope) {
        guard newScope != scope else { return }
        scope = newScope
        onScopeChanged?()
    }

    /// Feature #86 WI-4: which of the reader's own annotation kinds (Notes /
    /// Highlights / Bookmarks) are folded into the AI context. Drives the
    /// context-bar sources chip. Changing it re-assembles `bookContext` via the
    /// same coordinator funnel as scope.
    private(set) var sources: ChatSourceSelection = .default

    /// Per-book annotation counts for the sources popover (notes / highlights /
    /// bookmarks). Set by the coordinator from the `ChatAnnotationCache`.
    var sourceCounts: (notes: Int, highlights: Int, bookmarks: Int) = (0, 0, 0)

    /// Feature #86 WI-6: the citations the CURRENT assembled context drew on (set
    /// by the coordinator's funnel). `sendMessage` snapshots these at send time and
    /// stamps the assistant reply's "Drew on" row from the snapshot.
    var pendingCitations: [ChatCitation] = []

    /// Toggles a single source kind and re-assembles the book context.
    func setSources(_ newSources: ChatSourceSelection) {
        guard newSources != sources else { return }
        sources = newSources
        onScopeChanged?()   // same single re-assembly funnel as scope
    }

    /// Feature #86 WI-5b: the whole-book retrieval state machine (set by the
    /// coordinator). Drives the context bar's Armed/Reading/Ready cluster when the
    /// scope is `.wholeBook`.
    var wholeBookRetrieval: WholeBookRetrievalViewModel?

    /// Set by the coordinator: triggers the on-demand whole-book read and awaits
    /// it (so the digest is in `bookContext` before the question is answered).
    var onWholeBookReadRequested: (() async -> Void)?

    /// The composer is disabled while the whole book is being read.
    var isComposerDisabled: Bool {
        if case .reading = wholeBookRetrieval?.phase { return true }
        return false
    }

    // MARK: - Dependencies

    // `internal` (not `private`) so the streaming extension can reach them.
    let aiService: AIService

    /// Feature #91: live feature-flag source, so the agentic path re-checks the
    /// CURRENT `agenticTools` value each send (a mid-session OFF flip falls back to
    /// streaming — Gate-4 Medium), not a value latched at construction.
    let featureFlags: FeatureFlags

    /// Feature #91: the agentic tool registry. nil/empty (or a non-tool provider, or
    /// the flag OFF) → the chat uses the existing streaming path unchanged. The
    /// construction site builds it OFF-MAIN and injects it via `setAgenticRegistry`
    /// (a message sent before it lands simply streams); activation is gated on the
    /// live flag.
    private(set) var agenticRegistry: AIToolRegistry?

    /// Inject the agentic registry after construction (the live build opens the
    /// persistent FTS store off-main, so it can't be ready at init).
    func setAgenticRegistry(_ registry: AIToolRegistry?) {
        agenticRegistry = registry
    }

    /// Feature #88: chat-session persistence. `nil` ⇒ ephemeral behavior (general
    /// chat / tests that don't exercise sessions) — `loadSessions()` no-ops and no
    /// session is ever created/saved, so the pre-#88 single-thread flow is
    /// unchanged. Non-nil (book chat) ⇒ multiple switchable persisted sessions.
    /// `internal` so the `+Sessions` / `+Streaming` extensions can reach it.
    let chatSessionStore: (any ChatSessionPersisting)?

    /// The book's primitive lookup key (matches `Book.fingerprintKey`), derived
    /// from `bookFingerprint`. Nil for general chat. The session store keys on it.
    var bookFingerprintKey: String? { bookFingerprint?.canonicalKey }

    // MARK: - Init

    /// Creates a new chat view model.
    ///
    /// - Parameters:
    ///   - aiService: The AI service for sending requests.
    ///   - bookFingerprint: If non-nil, book context is included in requests.
    ///   - contextWindowSize: Max messages in the sliding context window (default 10).
    ///   - featureFlags: live flag source for the agentic gate (default `.shared`).
    ///   - agenticRegistry: Feature #91 — when non-nil + non-empty AND `agenticTools`
    ///     is on AND the resolved provider supports tool-use, the chat routes through
    ///     the agentic loop.
    ///   - chatSessionStore: Feature #88 — when non-nil (book chat), enables multiple
    ///     switchable persisted conversations. nil (general chat / tests) keeps the
    ///     pre-#88 ephemeral single-thread behavior.
    init(
        aiService: AIService,
        bookFingerprint: DocumentFingerprint? = nil,
        contextWindowSize: Int = 10,
        featureFlags: FeatureFlags = .shared,
        agenticRegistry: AIToolRegistry? = nil,
        chatSessionStore: (any ChatSessionPersisting)? = nil
    ) {
        self.aiService = aiService
        self.bookFingerprint = bookFingerprint
        self.contextWindowSize = contextWindowSize
        self.featureFlags = featureFlags
        self.agenticRegistry = agenticRegistry
        self.chatSessionStore = chatSessionStore
    }

    // MARK: - Actions

    /// Clears the entire conversation history and resets state. Feature #87 WI-1:
    /// cancels any in-flight stream FIRST (combined with id-based writes in the
    /// streaming extension, a mid-flight clear cannot index-corrupt the thread).
    ///
    /// Feature #88: this is the LOW-LEVEL clear (the cancel path). It does NOT seal
    /// the active session — `newConversation()` (in `+Sessions`) is the session-aware
    /// entry point that seals + resets `activeSessionId`. `clearHistory` leaves
    /// `activeSessionId` untouched so a cancel doesn't orphan the session identity.
    func clearHistory() {
        cancelStreaming()
        messages = []
        isLoading = false
        errorMessage = nil
    }

    // The streaming + cancellation concern (sendMessage launcher, runSend,
    // cancelStreaming, consumeStream, runAgenticTurn, context builders, and the
    // id-based write helper) lives in `AIChatViewModel+Streaming.swift`; the
    // Feature #88 session lifecycle (loadSessions / newConversation / switch /
    // rename / delete + the settled-turn save hook) lives in
    // `AIChatViewModel+Sessions.swift`, both to keep this base file under the
    // ~300-line guide.
}
