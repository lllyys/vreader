# #1477 · AI conversation sessions — switcher (Feature #88)

> Resolves needs-design [#1477](https://github.com/lllyys/vreader/issues/1477) — the visible affordance for **Feature #88** (multiple switchable chat sessions per book).
> Source of truth: `VReader Session Switcher Canvas.html` (every state × themes). Components in `session-switcher-artboards.jsx`. Transcript: `chats/chat20-tool-activity-1483.md`.
> Status: **design landed — implementation deferred** (recorded, not built; Swift held for a separate go-ahead).

## The gap

Today the Chat tab is a single ephemeral thread. #1477 adds multiple, switchable conversations per book.

## Decision (binding) — a slim SESSION BAR under the Chat tab + a Conversations sheet

1. **Session bar** — docked directly under the Chat segmented tab: left = the active conversation's title + chevron (tap → Conversations sheet), right = a **"New"** compose button. Scoped to the **Chat tab only** (not the shared sheet header), so it stays off Summarize / Translate where conversations don't exist — mirroring where the Summarize tab puts its scope chips.
2. **Conversations sheet** (nested) — a **New conversation** row on top, then the list of past conversations (title + snippet/last-active), with the **current thread tagged a green "Active"** pill. Per-row actions: **switch** (tap), **rename**, **delete**. An **empty state** for a book with no prior conversations.

## Production wiring (deferred — do NOT build without go-ahead)

- Requires the persisted chat-session model #88 specified (a `@Model ChatSession` + message records keyed by `bookFingerprint` via `PersistenceActor`); today `AIChatViewModel.messages` is in-memory only and the trash button wipes it.
- New session bar in `AIChatView` (Chat tab) + a `ConversationsSheet`; `AIChatViewModel` loads/saves the active session; today's `clearHistory` becomes "New conversation". Rule 51 satisfied by this note + canvas.
- Pairs with Feature #89 (back up sessions via WebDAV) once persistence lands.
