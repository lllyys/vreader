# Feature #88 — AI conversation sessions (multiple switchable chats per book)

- **Feature row**: `docs/features.md` #88 (Medium, TODO → this plan). GH: pending (created at the Gate-2 → PLANNED flip).
- **Design (binding)**: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/conversation-sessions-88.md` + `VReader Session Switcher Canvas.html` + `session-switcher-artboards.jsx` (needs-design #1477, delivered 2026-06-05). Go-ahead given by user 2026-06-05.
- **Revision history**: v1 2026-06-05. v2 — cleared round-1 (Codex `019e96bd`: 3H+2M+1L). v3 — cleared round-2 (Codex `019e96d3`: 1H+2M refinements). v4 2026-06-05 — cleared round-3 (Codex `019e96e0`: H7+M8 resolved; 2 Medium async-race refinements — the load-hook lifetime + the stale-load transition token — addressed below). The plan converged 6→3→2 findings; round-3's two localized async-race fixes were applied (not escalated, per the converging trend). v5 2026-06-05 — round-4 (Codex `019e96ec`) confirmed M11 + no other Critical/High/Medium in the 5-WI split/migration/persistence/UI; 2 narrow Mediums (the cold-open load-vs-first-turn race + an over-stated "live draft" claim) addressed below. Gate-2 round-5 (confirming): _pending_.

## Problem

The Chat tab is a single **ephemeral** thread per book: `AIChatViewModel.messages` is **in-memory only** (no persisted model — confirmed: no `ChatSession`/`ConversationRecord` `@Model` exists), and the toolbar trash button (`clearHistory()`) **wipes** it. There is no history to return to and no way to keep several conversations about a book. #88 adds **multiple, switchable, persisted conversations per book**.

## Design (binding)

A slim **session bar** docked under the Chat segmented tab (Chat-tab-only): left = active conversation title + chevron (tap → Conversations sheet), right = a **"New"** compose button. A nested **Conversations sheet**: a "New conversation" row on top, then the list (title + snippet/last-active) with the current thread tagged a green **"Active"** pill; per-row **switch** (tap) / **rename** / **delete**; an **empty state** for a book with no prior conversations. Rule 51 satisfied by the design note + canvas.

## Surface area (file-by-file)

### WI-1 — `ChatSession` `@Model` + SchemaV9 + persistence envelope + DTO (foundational)
- **NEW `vreader/Models/ChatSession.swift`** — `@Model final class ChatSession` (template = `Highlight`):
  - `@Attribute(.unique) var sessionId: UUID`
  - `var bookFingerprintKey: String` (the primitive lookup key, matches `Book.fingerprintKey`; general chat is OUT of scope — see edge cases)
  - `var title: String` (auto-derived from the first user message, else "New conversation")
  - `var messagesData: Data?` (JSON of the **persistence envelope**, NOT the domain type — see below; `@Transient` accessor maps blob ⇄ `[ChatMessage]`, like `Highlight.anchorData`/`anchor`)
  - **Denormalized summary fields (Gate-2 Medium 1)** so the Conversations-sheet list renders WITHOUT decoding every blob: `var lastMessageSnippet: String`, `var messageCount: Int` (maintained on every save).
  - `var createdAt: Date`, `var updatedAt: Date` (list sort = `updatedAt` desc; `updatedAt` is also `lastMessageAt`)
  - `var book: Book?` — the **optional INVERSE back-reference only** (Gate-2 High 1: the cascade lives on the PARENT array, see the `Book` change).
- **MODIFY `vreader/Models/Book.swift` (Gate-2 High 1)** — add `@Relationship(deleteRule: .cascade) var chatSessions: [ChatSession]` right after the existing cascade block (`Book.swift:103-106` already declares `readingPosition`/`bookmarks`/`highlights`/`annotations` this exact way), initialize it `= []` in `Book.init`. THIS is what makes book-delete cascade to its sessions; `ChatSession.book` is just the inverse.
- **NEW `vreader/Models/ChatSessionPayload.swift` (Gate-2 High 2)** — a dedicated **`Codable` persistence envelope**, decoupled from the live domain/UI types (which are NOT Codable: `ChatMessage` `ChatMessage.swift:22`, `ChatCitation` `ChatCitation.swift:20`):
  - `struct PersistedChatMessage: Codable { id: UUID; role: String; content: String; timestamp: Date; citations: [PersistedChatCitation] }` (`role` ⇄ `ChatRole` raw value).
  - **`struct PersistedChatCitation: Codable`** mirroring `ChatCitation`'s ACTUAL fields (Gate-2 round-2 High — confirmed shape, `ChatCitation.swift:30-42`): `id: UUID`, `sourceKind: String` (⇄ `ChatCitation.SourceKind` raw value), `label: String`, `locator: Locator?` (**`Locator` is `Codable` — `Locator.swift:24`**, store directly), `spanUTF16: ClosedRange<Int>?` (Codable), `sequence: Int?`, `aheadOfReader: Bool`. (Every field is Codable, so the envelope encodes cleanly.)
  - `enum ChatSessionPayloadMapper` — pure `static` map `[ChatMessage] ⇄ [PersistedChatMessage]` + `ChatCitation ⇄ PersistedChatCitation` (string-raw the two enums; pass `Locator?`/`ClosedRange?` through). The actor encodes/decodes via this; the domain types are never serialized directly, so a domain-shape change can't corrupt the blob. A top-level `payloadVersion: Int` rides the envelope (`struct ChatSessionPayload: Codable { version: Int; messages: [PersistedChatMessage] }`) for forward-compat.
- **NEW `vreader/Services/ChatSessionRecord.swift`** — `struct ChatSessionRecord: Sendable, Equatable, Identifiable` (full DTO across the actor boundary): `sessionId`, `bookFingerprintKey`, `title`, `messages: [ChatMessage]`, `createdAt`, `updatedAt`. Plus `struct ChatSessionSummary: Sendable, Identifiable` (id, title, `snippet` ← `lastMessageSnippet`, `updatedAt`, `messageCount`) — built from the DENORMALIZED columns, no blob decode.
- **NEW `vreader/Models/Migration/SchemaV9.swift`** — `enum SchemaV9: VersionedSchema`, `versionIdentifier = Schema.Version(9, 0, 0)`, `models` = all 11 SchemaV8 models + `ChatSession.self`.
- **MODIFY `vreader/Models/Migration/SchemaV1.swift`** (confirmed: `VReaderMigrationPlan` lives here) — append `SchemaV9.self` to `schemas`; `stages` stays empty. **Migration is lightweight** (Codex-confirmed): a new entity + a new to-many `Book.chatSessions` relationship needs no explicit `MigrationStage` (no backfill/transform).
- **MODIFY `vreader/App/ModelContainerFactory.swift`** (confirmed: the live `ModelContainer` schema site, used by `VReaderApp.swift`) — bump the current schema to `SchemaV9.models`.
- **NEW `vreaderTests/Models/Migration/SchemaV9MigrationTests.swift`** (template = `SchemaV8MigrationTests`): version (9,0,0); `ChatSession` added; plan tail SchemaV9; **V8→V9 round-trip on a POPULATED store** (build a V8 store with a Book + Highlight + Bookmark, reopen under V9 with the plan, assert existing rows survive + a ChatSession inserts + book-delete cascades to its sessions).

### WI-2 — `PersistenceActor+ChatSessions` CRUD + protocol (foundational)
- **NEW `vreader/Services/ChatSessionPersisting.swift`** (boundary protocol, mirrors `HighlightPersisting` which lives at `vreader/Services/HighlightPersisting.swift` — Gate-2 Low path fix, NOT a `Persistence/` subfolder):
  - `func createChatSession(bookFingerprintKey: String, title: String, messages: [ChatMessage]) async throws -> ChatSessionRecord`
  - `func fetchChatSessionSummaries(forBookWithKey key: String) async throws -> [ChatSessionSummary]` (sorted `updatedAt` desc)
  - `func fetchChatSession(sessionId: UUID) async throws -> ChatSessionRecord?`
  - `func updateChatSession(sessionId: UUID, messages: [ChatMessage], title: String?) async throws -> ChatSessionRecord` (bumps `updatedAt`)
  - `func renameChatSession(sessionId: UUID, title: String) async throws`
  - `func deleteChatSession(sessionId: UUID) async throws`
- **NEW `vreader/Services/PersistenceActor+ChatSessions.swift`** — `extension PersistenceActor: ChatSessionPersisting` (the `ModelContext(modelContainer)` + `#Predicate` + `try context.save()` pattern from `+Highlights`). Sessions attach to the `Book` (fetch by `fingerprintKey`); deleting a `Book` cascade-deletes its sessions.
- **NEW `vreaderTests/Services/PersistenceActor+ChatSessionsTests.swift`** — in-memory `ModelContainer(SchemaV9)`: create/fetch/update/rename/delete; sort order; cascade-on-deleteBook; CJK title/messages; empty-messages session; idempotency.

### WI-3 — `AIChatViewModel` session lifecycle + streaming handoff (behavioral)
- **MODIFY `vreader/ViewModels/AIChatViewModel.swift`** — inject `chatSessionStore: (any ChatSessionPersisting)?` (optional; nil ⇒ today's ephemeral behavior, e.g. general chat / tests that don't exercise sessions) + an `activeSessionId: UUID?`.
  - **Concrete load hook — owned by the long-lived coordinator (Gate-2 round-3 Medium)**: the one-shot session load is triggered by **`ReaderAICoordinator`** (the long-lived owner that constructs the VM + already does async setup like the agentic-registry injection) right after it builds the book-chat VM — NOT by `AIChatView.task`. Rationale: the Chat tab conditionally mounts `AIChatView` only when selected (`AIReaderPanel.swift:138`), so a view-level `.task` reruns on every tab re-entry and would clobber a fresh empty conversation / a just-streamed-but-not-yet-saved turn. `loadSessions()` is **idempotent + non-clobbering**: a `private var loadedFingerprintKey: String?` guard makes it a no-op once it has run for the current key OR when local session state already exists (`activeSessionId != nil || !messages.isEmpty`).
  - **Cold-open load-vs-first-turn race (Gate-2 round-4 Medium)**: a user can send a first message BEFORE the async `loadSessions()` fetch returns. So: (a) `loadSessions()` **re-checks `activeSessionId == nil && messages.isEmpty` after every `await` and again immediately before applying** the loaded messages — if a turn started meanwhile, abandon the load (don't overwrite the just-started thread); and (b) the **lazy-create path** (first user turn → `sendMessage` creating the session) **bumps `sessionTransitionToken`**, so an in-flight `loadSessions` fails its post-await token re-check. A WI-3 test pins "cold open → send before load resolves → the sent turn wins, the load is abandoned."
  - **Out of scope — unsent composer draft preservation**: the composer's draft text is view-local `@State inputText` (`AIChatView.swift:35`); #88 does NOT hoist it into the VM, so an unsent draft is NOT preserved across a Chat-tab remount (unchanged from today). Session/message state IS preserved (owned by the coordinator-held VM). The acceptance language makes no live-draft claim.
  - General chat (nil store) → `loadSessions()` is a no-op.
  - **Lazy session creation (Gate-2 Medium 2)**: `loadSessions()` loads the **most-recent NON-EMPTY** session for `bookFingerprintKey` if one exists, else leaves `activeSessionId == nil` with empty `messages` (the designed empty state). **Do NOT persist an empty session on open** — a session is created/persisted only on the **first real user turn** or an explicit "New conversation" after content exists.
  - **Save**: persist the active session after a **settled turn** (`isLoading` fell + the assistant placeholder cleanup ran), debounced — never per streamed chunk. On save, refresh the denormalized `title` (from the first user message if still default), `lastMessageSnippet`, `messageCount`, `updatedAt`.
  - **New conversation**: the UI's former `clearHistory()` becomes **"New conversation"** — seal/save the current session (if it has content), reset `activeSessionId = nil` + `messages = []` (the next user turn lazily creates the new session).
  - **Switch**: `switchToSession(_ id: UUID)` — **set a transition token + the requested id BEFORE the first `await` (Gate-2 round-3 Medium)**: bump a monotonic `sessionTransitionToken` and stash `requestedSessionId = id` synchronously, THEN `await` save-current + fetch-target; after EACH await, re-check `token == sessionTransitionToken` (and `requestedSessionId == id`) before applying — abandon if a newer switch superseded this one. Only on the final apply set `activeSessionId = id` + replace `messages`. (Do NOT use post-load `activeSessionId` as the only stale-load guard — rapid B→C→… switches would otherwise let an older load win.) `loadSessions()` uses the same token discipline.
  - `func renameActiveSession(_:)`, `func deleteSession(_:)` (deleting the active one → load most-recent-remaining or reset to the empty state; both bump the transition token first).
- **Streaming handoff (Gate-2 High 3 — `AIChatViewModel+Streaming.swift` IS in WI-3 scope):** a session transition (switch / new / delete) must, **as its FIRST step — before any load/delete/save work begins (Gate-2 round-2 Medium ordering)** — `cancelStreaming()` + bump `opCounter`, so a late provider reply can't land in the wrong (or a deleted) session. Only after the op is bumped does the method load/seal/delete. The settled-turn **save** runs only after the placeholder cleanup / settled completion. Late writes are guarded by BOTH `opId == opCounter` AND the **active-session identity** (capture `activeSessionId` at send time; on completion, only append/save if it's still the active session). The WI-1 stop-control opId discipline extends to carry the session id.
  - Concurrency: VM `@MainActor`; store is the actor; `ChatSessionRecord`/`ChatMessage`/`ChatSessionSummary` are `Sendable`. An async `fetchChatSession` resolving after the user already switched applies only if its id still matches `activeSessionId` (R2 guard).
- **MODIFY the construction sites** — `ReaderAICoordinator` (book chat) injects the `ChatSessionPersisting` (the app's `PersistenceActor`); `LibraryView` general chat passes `nil` (general chat stays ephemeral — out of scope).
- **MODIFY tests** `AIChatViewModelTests` — session lazy-create / save-on-settled / switch / new / delete-active + the streaming-handoff race (switch mid-send cancels + doesn't land the reply in the new session), with a mock `ChatSessionPersisting`.

### WI-4 — Session bar (Chat-tab) (behavioral)
- **NEW `vreader/Views/AI/ChatSessionBar.swift`** — the slim bar: active title + chevron (→ presents the Conversations sheet) + "New" button (→ `viewModel`'s new-conversation). Docks under the Chat tab, above `ChatContextBar` (Chat-tab-only — NOT on Summarize/Translate, mirroring where the scope chips live). Reuse v2 chrome tokens.
- **MODIFY `vreader/Views/AI/AIChatView.swift`** — render `ChatSessionBar` (book chat only); the trash toolbar button becomes/relabels to "New conversation" per the design (or is removed in favor of the bar's New button — confirm against the canvas).

### WI-5 — Conversations sheet (behavioral, **final WI**)
- **NEW `vreader/Views/AI/ConversationsSheet.swift`** — New-conversation row + the session list (title + snippet + last-active), current = green "Active" pill; per-row tap = switch (dismiss), swipe/`…` = rename + delete; empty state. Driven by `fetchChatSessionSummaries`. Reuse v2 list chrome.
- Completes the feature → row `DONE`.

### Files OUT of scope
- **General chat** (`bookFingerprint == nil`, LibraryView) — sessions are book-scoped; general chat keeps its ephemeral single thread + no session bar.
- **WebDAV backup of sessions** — Feature #89 (depends on this); not in #88.
- **The AI request/streaming MECHANICS** (provider call, chunk consumption) — unchanged. But the streaming FILE (`AIChatViewModel+Streaming.swift`) IS touched in WI-3 for the session-transition cancel/handoff + settled-turn save hook (Gate-2 High 3) — it is NOT out of scope.
- **Summarize / Translate tabs** — no sessions (the bar is Chat-tab-only).

## Prior art / project precedent / rejected alternatives
- **Precedent — `Highlight`/`HighlightRecord`/`PersistenceActor+Highlights`/`HighlightPersisting`**: the exact `@Model` + DTO + actor-extension + boundary-protocol + cascade-from-`Book` shape #88 mirrors.
- **Precedent — `ChapterTranslation` (SchemaV7)**: the most recent additive `@Model` + schema-version bump; the lightweight-migration template.
- **Precedent — `messagesData: Data?` JSON blob**: mirrors `Highlight.anchorData` (a `@Transient` computed accessor over a `Data?` column) — avoids a separate `ChatMessageRecord @Model` + relationship (simpler; the message array is always read/written whole per session). **Rejected alternative**: a separate `@Model ChatMessageRecord` with a `@Relationship` to `ChatSession` — more normalized but heavier (per-message rows, relationship migration); the blob matches the access pattern (load/save a whole conversation) and the `Highlight.anchorData` precedent.
- **Rejected — sessions for general (book-less) chat**: the design scopes sessions to a book (`bookFingerprintKey`); general chat has no book to key on. Kept ephemeral.

## Work-item sequencing

| WI | Title | Tier | PR size | Notes |
|----|-------|------|---------|-------|
| WI-1 | `ChatSession @Model` + SchemaV9 + DTO + migration test | foundational | ~M | additive schema; no user-observable behavior. |
| WI-2 | `PersistenceActor+ChatSessions` CRUD + `ChatSessionPersisting` | foundational | ~M | persistence layer + tests. |
| WI-3 | `AIChatViewModel` session lifecycle (load/save/new/switch/rename/delete) | behavioral | ~M | wires persistence into the VM; debounced save. |
| WI-4 | Session bar (Chat-tab) | behavioral | ~S | the docked bar + New button. |
| WI-5 | Conversations sheet (list / switch / rename / delete / empty) | behavioral (final) | ~M | completes the feature → DONE. |

5 WIs ⇒ Large feature (1 plan audit + 1 audit per WI; the two foundational schema/persistence WIs may batch one audit if they share the surface).

## Test catalogue
- **WI-1**: `SchemaV9MigrationTests` (version, model-set, plan-tail, V8→V9 round-trip), `ChatSessionTests` (messagesData ⇄ `[ChatMessage]` round-trip incl. CJK + citations, title default).
- **WI-2**: `PersistenceActor+ChatSessionsTests` (create/fetch-summaries/fetch-full/update/rename/delete, sort by updatedAt, cascade-on-deleteBook, empty-messages, idempotency, CJK).
- **WI-3**: `AIChatViewModelTests` session leg (load most-recent-non-empty / no-persist-empty-on-open / save-on-settled-turn / new-conversation seals+resets / switch replaces messages / delete-active falls back / title-from-first-user-message), with a mock `ChatSessionPersisting`. Race tests: **switch mid-send cancels + the reply doesn't land in the new session** (streaming handoff); **rapid B→C switch — the older B load is abandoned** (transition token); **cold open → send before load resolves → the sent turn wins, the load is abandoned** (cold-open race).
- **WI-4/WI-5**: view-behavior tests where unit-pinnable (the bar's title/active-state resolver; the sheet's summary list mapping + the rename/delete callbacks), mirroring `TranslateLanguageRail`'s `static tapAction` precedent.

## Risks + mitigations
- **R1 — debounced save vs streaming**: a naive save-per-`messages`-change would write per streamed chunk. Mitigation: save on a *settled* turn (after `isLoading` falls / on teardown), debounced; the streaming path is unchanged.
- **R2 — load/switch race**: an async `fetchChatSession` resolving after the user already switched could clobber `messages`. Mitigation: an `activeSessionId`/opId guard (the WI-1 stop-control discipline) — apply a fetched session only if it's still the requested active id.
- **R3 — schema migration on a populated store**: a real device has a populated V8 store. Mitigation: ChatSession is purely additive (no field changes to existing models) → SwiftData lightweight migration; the V8→V9 round-trip test asserts existing rows survive; **device-verify the migration on a populated store at Gate-5** (open the app on a pre-V9 build's data, confirm no data loss).
- **R4 — general chat (nil fingerprint)**: must not crash / must keep ephemeral behavior with a nil store. Mitigation: optional store; the session bar renders only for book chat.
- **R5 — Gate-5 acceptance is partly AI-provider-gated** (creating real conversations to switch needs AI replies). Mitigation: the persistence + switch/rename/delete + the migration are fully device-verifiable with SEEDED sessions (DebugBridge / a debug seed) WITHOUT a provider; only "have a real AI conversation then switch" needs a provider. Plan a DebugBridge `seed-chat-session` affordance or seed via the persistence layer for Gate-5.

## Audit fixes applied (Gate-2 round 1 — Codex `019e96bd`)

| # | Sev | Finding | Resolution |
|---|-----|---------|-----------|
| 1 | High | Cascade lives on the PARENT array (`Book.highlights`), not the child back-ref; plan never added `Book.chatSessions` → book-delete cascade missing | Add `@Relationship(deleteRule: .cascade) var chatSessions: [ChatSession]` to `Book` (+ init `= []`); `ChatSession.book` is the optional inverse only. |
| 2 | High | `messagesData` as JSON of `[ChatMessage]` fails — `ChatMessage` + `ChatCitation` are NOT `Codable` | Dedicated `Codable` persistence envelope (`PersistedChatMessage`/`PersistedChatCitation` + `ChatSessionPayloadMapper`, `payloadVersion`); domain types never serialized directly. |
| 3 | High | `AIChatViewModel+Streaming.swift` marked out-of-scope, but session-transition cancel + settled-save + opId/streamTask handoff live there → in-flight sends leak across sessions | Streaming is IN WI-3 scope: cancel/bump op on switch/new/delete; persist only after settled completion; guard late writes by `opId` AND active-session identity. |
| 4 | Medium | Summary list with only title/timestamps/blob requires decoding every blob (contradicts the no-decode claim) | Denormalized `lastMessageSnippet` + `messageCount` columns on `ChatSession`, maintained on save; `ChatSessionSummary` reads them without a blob decode. |
| 5 | Medium | "Load-or-create-empty on attach" persists empty sessions on open + breaks the empty state | Lazy creation: `activeSessionId` stays nil until the first real user turn / explicit New; an empty session is never persisted. |
| 6 | Low | Wrong template path (`Services/Persistence/HighlightPersisting.swift`) | Corrected to `vreader/Services/ChatSessionPersisting.swift` (mirrors `Services/HighlightPersisting.swift`). |

### Gate-2 round 2 — Codex `019e96d3` (round-1 all resolved)

| # | Sev | Finding | Resolution |
|---|-----|---------|-----------|
| 7 | High | `PersistedChatCitation` must mirror `ChatCitation`'s ACTUAL fields | Specified exactly: `id`, `sourceKind: String`, `label`, `locator: Locator?` (Locator IS Codable, `Locator.swift:24`), `spanUTF16: ClosedRange<Int>?`, `sequence: Int?`, `aheadOfReader: Bool`. |
| 8 | Medium | Transition methods must bump op BEFORE load/delete work | Made explicit: cancel + bump `opCounter` is the FIRST step of switch/new/delete, before any load/seal/delete. |
| 9 | Medium | The concrete VM load hook was unspecified | `AIChatView` calls `await viewModel.loadSessions()` from `.task(id: bookFingerprintKey)` (book chat only; nil-store no-op). |

### Gate-2 round 3 — Codex `019e96e0` (H7 + M8 resolved)

| # | Sev | Finding | Resolution |
|---|-----|---------|-----------|
| 10 | Medium | `.task(id:)` on `AIChatView` reruns on every Chat-tab re-entry (conditionally mounted, `AIReaderPanel.swift:138`) → clobbers a live draft / fresh conversation / unsaved turn | Load is owned by the long-lived `ReaderAICoordinator` (one-shot after VM construction), NOT `AIChatView.task`; `loadSessions()` is idempotent + non-clobbering (`loadedFingerprintKey` guard + skip when local state exists). |
| 11 | Medium | Stale-load guard relied on post-load `activeSessionId` → rapid B→C switches could let an older load win | A monotonic `sessionTransitionToken` + `requestedSessionId` set BEFORE the first await; re-checked after every awaited save/fetch before applying. All transitions (switch/new/delete/load) bump it first. |

### Gate-2 round 4 — Codex `019e96ec` (M11 confirmed; no other C/H/M in the rest of the plan)

| # | Sev | Finding | Resolution |
|---|-----|---------|-----------|
| 12 | Medium | Cold-open race: a first user turn sent before the async `loadSessions` fetch returns could be overwritten by the load | `loadSessions()` re-checks `activeSessionId == nil && messages.isEmpty` after every await + before applying (abandon if a turn started); the lazy-create path bumps `sessionTransitionToken`. WI-3 test: "cold open → send before load resolves → sent turn wins." |
| 13 | Medium | Over-stated "live draft" claim — the composer draft is view-local `@State`, not preserved across remounts | Removed the claim; unsent-draft preservation is explicitly OUT of scope (#88 doesn't hoist `inputText`); session/message state IS preserved (coordinator-held VM). |

## Backward compat
ChatSession is a **new, additive** entity — SchemaV8 stores migrate to V9 with no data loss (lightweight). Older clients (pre-V9) never see the column. The WebDAV backup format is **unchanged** in #88 (AI sessions enter the backup only in #89) — older/newer backups round-trip unaffected. Reverting to a pre-#88 build leaves the ChatSession rows unread (harmless).
