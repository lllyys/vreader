# Feature #91 — Agentic AI tool/function calling (AI chat can search + fetch book content)

**Status:** Gate 1 ✅ + Gate 2 ✅ (Codex audit, 3 rounds → PASS, zero open Critical/High/Medium) → PLANNED. Gate 3 (TDD) is the next phase.
**Tracker row:** `docs/features.md` #91 (TODO → PLANNED). GH: #1482. Tool-activity UI deferred → needs-design #1483.
**Author:** claude (orchestrator)
**Date:** 2026-06-03

## Problem

The AI chat (Feature #14) is a flat single-shot: `AIRequest` carries a
pre-stuffed `contextText` window and the provider streams one text reply, so the
model can only answer from whatever context was stuffed up front (current chapter
/ #86 retrieval). The user wants the chat to **call tools** — *"search the
content, search in other books, get other books content, and so on"* — i.e. an
**agentic loop**: the model decides it needs information, requests a tool, the app
executes it (FTS search, fetch chapter text, list/search other books), feeds the
result back, and the model continues until it produces a final answer. This turns
the chat from "answer from a fixed window" into "read-on-demand across the
library."

## Scope & non-goals

**In scope (this feature):**
- Provider-level tool-use: add a `tools` array to the request body and parse
  tool-call blocks back (Anthropic `tool_use` content blocks; OpenAI-style
  `tool_calls`), gated per-provider on a declared capability.
- A tool registry + 3 read-only tool executors wrapping EXISTING capabilities:
  `search_current_book`, `search_other_books`, `get_book_content`.
- A bounded agentic loop (send → tool_use → execute → tool_result → re-send →
  … → final text), max-iteration-capped, wired into `AIChatViewModel.sendMessage`.
- A feature flag (`agenticTools`, default OFF until verified) + per-provider
  capability gate; when off or unsupported, the chat behaves exactly as today.

**Explicitly OUT of scope (Rule 51 / dependency / risk):**
- **Visible tool-activity UI** (e.g. "🔍 searching…" cards, a tool-call timeline
  in the chat) — NEW UI not in the committed design bundle. Per rule 51, filed as
  a separate `needs-design` issue; the agentic loop runs SILENTLY in this feature
  (the user sees only the final answer in the existing chat bubble, the same
  surface today's reply uses). See **Rule 51** below.
- **Write/mutating tools** (create highlight, edit book, etc.) — read-only only.
- **BookSource / web-scrape tools** — deferred (network + a separate subsystem).
- **Annotation tools** — overlaps #86; deferred to avoid double-owning that surface.
- **Streaming the final tool-using answer** — the agentic path is NON-STREAMING
  (the answer appears when ready, like the Summarize tab). The existing streaming
  path stays for non-tool chats. Streaming-with-tool-use is a documented future
  enhancement (it requires SSE `content_block_start`/`input_json_delta` assembly).

## Prior art / project precedent / rejected alternatives

- **Anthropic tool-use** (`/v1/messages` with a `tools` array; the model returns
  `content` blocks of `type:"tool_use"` `{id,name,input}`; you reply with a `user`
  message carrying `tool_result` blocks `{tool_use_id, content}`) is the canonical
  shape. `AnthropicProvider` already assembles the `messages` body
  (`AnthropicProvider.swift:147-159`) and parses `content[].text`
  (`:87-96`) — the change is additive.
- **OpenAI function-calling** (`tools:[{type:"function",function:{name,description,parameters}}]`,
  the assistant returns `tool_calls:[{id,function:{name,arguments}}]`, you reply
  with `role:"tool"` messages) for `OpenAICompatibleProvider`
  (`AIProvider.swift:128-139`).
- **Precedent — the `WholeBookReducer` / off-actor reducer pattern (#86 WI-5a)**:
  #86 introduced an off-`@MainActor` reducer (`reducerFactory`, generation epoch,
  fresh-reducer-per-read) for the whole-book retrieval cluster. The agentic loop
  is the same shape — an off-VM async driver that the `@MainActor` VM awaits — so
  the loop lives in an `actor`/struct driver, NOT inline in the VM, mirroring #86.
- **Search**: `SearchService.search(query:bookFingerprint:page:pageSize:)`
  (`SearchService.swift:126`) is per-book FTS5; library-wide search = iterate
  `fetchAllLibraryBooks()` (`PersistenceActor+Library.swift:14`) and search each
  indexed book (skip un-indexed). Book content =
  `EPUBChapterTextProvider.sourceText(for:)` / `parser.contentForSpineItem(href:)`;
  book lookup = `PersistenceActor.findBook(byFingerprintKey:)` (`:125`).
- **Rejected — content-block restructure of `AIResponse`**: changing
  `AIResponse.content: String` → `[ContentBlock]` ripples through every existing
  caller (summarize/translate/vocab). REJECTED. Instead add a SEPARATE
  non-streaming `sendToolRequest(_:) -> AIToolTurn` path that returns either
  `.text(String)` or `.toolCalls([ToolCall])`, leaving `AIResponse` untouched.
- **Rejected — streaming agentic loop in v1**: SSE tool_use assembly
  (`input_json_delta` accumulation) is fiddly and error-prone; a non-streaming
  loop is correct and simpler. Deferred.
- **Rejected — exposing tools to the Summarize/Translate tabs**: those are
  single-shot by design; tools are a Chat-only capability in v1.

## Surface area (file-by-file)

### New files

- `vreader/Services/AI/AITool.swift` — the tool contracts:
  - `struct ToolDefinition: Sendable { let name: String; let description: String; let inputSchema: [String: Any] }` (JSON-schema dict; `@unchecked Sendable` wrapper or a `JSONValue` enum to stay `Sendable` — see Risks).
  - `struct ToolCall: Sendable, Equatable { let id: String; let name: String; let input: JSONValue }`.
  - `struct ToolResult: Sendable, Equatable { let toolUseID: String; let content: String; let isError: Bool }`.
  - `protocol AITool: Sendable { var definition: ToolDefinition { get }; func run(_ input: JSONValue) async -> ToolResult }`.
  - `enum JSONValue: Sendable, Equatable, Codable { case string/number/bool/object/array/null }` — a `Sendable` JSON value so tool I/O crosses the actor boundary cleanly (avoids `[String: Any]` Sendable holes).
- `vreader/Services/AI/AIToolRegistry.swift` — `struct AIToolRegistry: Sendable { let tools: [String: any AITool]; func definitions() -> [ToolDefinition]; func run(_ call: ToolCall) async -> ToolResult }` (unknown-tool → `isError` result, never throws).
- `vreader/Services/AI/Tools/SearchCurrentBookTool.swift` — wraps `SearchProviding.search(query:bookFingerprint:page:pageSize:)` for the open book's fingerprint (the open book is already indexed in the live `SearchService`). Thin.
- `vreader/Services/AI/Tools/SearchOtherBooksTool.swift` — **(Gate-2 round-1 High 1) re-planned around the PERSISTENT index store, NOT `SearchService.isIndexed` (in-memory only).** Import no longer auto-indexes (`BookImporter.swift:374-375`), and persisted-index discovery/restoration lives in `ReaderSearchCoordinator` (`SearchIndexStore.isBookIndexed`, `getSegmentBaseOffsets`/`restoreSegmentOffsets`, `markPersistentlyIndexed` — `ReaderSearchCoordinator.swift:127-178`). The tool reuses the SAME safe-restore guards `ReaderSearchCoordinator.setup` applies (`ReaderSearchCoordinator.swift:127`), NOT just `isBookIndexed` (Gate-2 round-2 Medium): for each `fetchAllLibraryBooks()` row — (a) `SearchIndexStore.isBookIndexed(fingerprintKey)` must be true; (b) NOT `requiresReindex(...)` (a schema/version-stale index); (c) for TXT/MD, `getSegmentBaseOffsets` must be non-nil (a nil offset map = stale → would mis-resolve locators), restored via `SearchService.restoreSegmentOffsets`; EPUB/PDF marked in-memory via `markPersistentlyIndexed`. Books failing ANY guard (never-indexed, requires-reindex, or stale-nil-offsets) are EXCLUDED from the search and reported by count in the result text ("N library books are not searchable — not indexed or need re-indexing") so the model knows coverage is partial and never receives a mis-resolved result. NO on-demand (re)indexing in v1 (expensive). Capped book count + per-book result cap.
- `vreader/Services/AI/Tools/GetBookContentTool.swift` — **(Gate-2 round-1 High 2) narrowed contract: LOCAL + supported reflowable formats only.** `findBook(byFingerprintKey:)` → resolve the sandbox file URL (the closed-book reopen path used by `ReaderAICoordinator.swift:298-349` + `LibraryBookItem.swift:171`) → extract text via the format's parser (`EPUBTextExtractor.extractTextUnits(from:fingerprint:)` for epub; the txt/md/pdf equivalents). Explicit error results (never a throw, never silent): `book_not_found`, `book_not_local` (remote-only / failed `BookFileState` — `BookFileState.swift:43-57`), `unsupported_format` (native AZW3/MOBI — there is NO closed-book Foliate text path; note #42 converts NEW Kindle imports to EPUB by default, so only legacy-native `.azw3` rows or override-off imports hit this). Range-limited + byte-capped.
- `vreader/Services/AI/AgenticChatDriver.swift` — `struct AgenticChatDriver { ... func run(history:userPrompt:registry:provider:maxIterations:) async throws -> AgenticResult }` — the bounded loop (send tool request → if `.toolCalls`, run each via registry, append tool_result, re-send → repeat until `.text` or max-iter → return final text). Off-`@MainActor` (mirrors #86 reducer). **(Gate-2 round-1 Medium 1) the driver is handed ONE pre-resolved `any AIProvider`** (resolved once at loop start), so a provider/model/key change mid-loop cannot straddle the operation. **(Gate-2 round-1 Medium 2)** `AgenticResult` carries `{ finalText: String, usedTools: Bool }` so the VM can decide citation handling (see below).
- New tests (see Test catalogue).

### Modified files

- `vreader/Services/AI/AITypes.swift` — add `AIToolRequest` (or extend `AIRequest` with an optional `tools: [ToolDefinition]?` + a `messages: [ToolTurnMessage]?` multi-turn carrier) and `enum AIToolTurn { case text(String); case toolCalls([ToolCall]) }`. **Decision:** add a parallel `AIToolRequest` + `AIToolTurn` rather than mutating `AIRequest`/`AIResponse` (keeps the 5 existing action paths untouched).
- `vreader/Services/AI/AIProvider.swift` — add ONE protocol method `func sendToolRequest(_ request: AIToolRequest) async throws -> AIToolTurn` with a default impl that throws `AIError.toolUseUnsupported` (so non-tool providers compile unchanged) + `var supportsToolUse: Bool { get }` (default false). `OpenAICompatibleProvider` overrides for function-calling.
- `vreader/Services/AI/AnthropicProvider.swift` — implement `sendToolRequest`: assemble the `messages` array (multi-turn, with prior tool_use/tool_result blocks) + a `tools` array; parse the response `content` for `tool_use` blocks → `.toolCalls`, else `.text`. `supportsToolUse = true`.
- `vreader/Services/AI/AnthropicProvider+ToolUse.swift` (new, keeps the file <300) — the body-assembly + content-block parsing for tool-use.
- `vreader/Services/AI/AIService.swift` — **(Gate-2 round-1 Medium 2) mirror the chapter-translation resolved-config seam** (one logical op must not straddle provider/model/key changes): add `func resolveToolProvider() async throws -> (provider: any AIProvider, supportsToolUse: Bool)` that resolves the active profile + key ONCE, and `func currentProviderSupportsToolUse() async -> Bool`. The agentic driver is handed the resolved provider and never re-resolves per turn. (The gates — flag + consent — are checked once at resolve time.)
- `vreader/Services/FeatureFlags.swift` — add `agenticTools` (default false; persisted-revertable like `kindleConvertOnImport`).
- `vreader/ViewModels/AIChatViewModel.swift` — in `sendMessage`, when `agenticTools` is on AND the resolved provider `supportsToolUse` AND scope permits, route through `AgenticChatDriver.run(...)` (non-streaming, single final-answer append) instead of the streaming path; otherwise the existing streaming path is unchanged. Inject the `AIToolRegistry` (built from the open book's `SearchService` + the persistent `SearchIndexStore` + `PersistenceActor`). **(Gate-2 round-1 Medium 3) citations**: the pre-send `ChatMessage.citations` snapshot reflects only the CURRENT context (#86 WI-6 "Drew on"), not what tools read. For v1, when `AgenticResult.usedTools == true`, **SUPPRESS** the citation stamp on that reply (an incomplete/wrong "Drew on" row is worse than none) — documented as a known limitation; returning per-tool-source provenance and merging it into `citations` is a designed follow-up (and overlaps #86). A non-tool reply keeps today's citation behavior.
- `docs/architecture.md` — Services Layer: add `AIToolRegistry` + `AgenticChatDriver` + the tool protocol; note the `agenticTools` flag.

### Files OUT of scope

- `AISummaryTabView` / `AITranslationViewModel` — tools are Chat-only.
- Any `AIChatView` UI — no visible tool-activity (Rule 51; see below).
- `BackupDataCollector` / persistence schema — no new `@Model` (tool I/O is ephemeral).

## Work-item sequencing

| WI | Title | Tier | PR size | Summary |
|----|-------|------|---------|---------|
| WI-1 | Tool DTOs + `JSONValue` | foundational | S | `AITool`/`ToolDefinition`/`ToolCall`/`ToolResult`/`JSONValue`/`AIToolRequest`/`AIToolTurn`. Pure types + Codable + Sendable. |
| WI-2 | `AIProvider.sendToolRequest` seam + capability flag | foundational | S | Protocol method (default throws) + `supportsToolUse` (default false). No provider impl yet. |
| WI-3 | Anthropic tool-use impl | foundational | M | `AnthropicProvider+ToolUse` — body `tools` array + multi-turn messages + `tool_use` parsing. Stub-URLSession tests (mirror `AnthropicProviderTests`). |
| WI-4 | OpenAI function-calling impl | foundational | M | `OpenAICompatibleProvider` `tools`/`tool_calls`. Stub-URLSession tests. |
| WI-5 | `AIToolRegistry` + `JSONValue` plumbing | foundational | S | Registry dispatch + unknown-tool error result. Pure. |
| WI-6a | `search_current_book` tool | behavioral | S | Thin wrap of `SearchService.search` for the open book. Unit tests with a stub `SearchProviding`. |
| WI-6b | `search_other_books` tool (persistent-index-aware) | behavioral | M | **(Gate-2 split)** Query `SearchIndexStore.isBookIndexed` per library book, restore TXT/MD offsets, search persisted-indexed books only, report never-indexed coverage. NOT a thin wrapper — this is where the index-coverage risk lives. Unit tests: indexed vs never-indexed mix, coverage reporting, cap. |
| WI-6c | `get_book_content` tool (format/locality-gated) | behavioral | M | **(Gate-2 split)** Closed-book text via the reopen path for local txt/md/pdf/epub; explicit `book_not_found` / `book_not_local` / `unsupported_format` error results (native AZW3/MOBI, remote-only). Range/byte caps. Unit tests: each format, remote-only, native-Foliate, out-of-range. |
| WI-7 | `AgenticChatDriver` (bounded loop) | behavioral | M | send → tool_calls → run → tool_result → re-send, max-iter cap, error/empty handling, ONE pre-resolved provider. Returns `AgenticResult{finalText, usedTools}`. Unit tests with a scripted stub provider. |
| WI-8 | Wire into `AIChatViewModel` + `agenticTools` flag + resolved-provider + citation-suppression (final) | behavioral (final) | M | Route `sendMessage` through the driver when enabled + resolved-provider `supportsToolUse`; suppress citations on tool replies; flag default OFF; device/integration verify against a real Anthropic provider. → DONE; then a human-gated default-ON flip (symmetric with #42 G2) is a SEPARATE follow-up, not this feature. |

(10 WIs — WI-1..5 foundational, WI-6a/6b/6c/7/8 behavioral. WI-6 split per the Gate-2 round-1 cohesion finding: `search_other_books` and `get_book_content` are architecture/coverage risks, not thin wrappers.)

## Test catalogue

- `AIToolDTOTests` (WI-1) — `JSONValue` Codable round-trip (string/number/bool/object/array/null, nested, CJK); `ToolCall`/`ToolResult` Equatable.
- `AnthropicProviderToolUseTests` (WI-3) — stub URLSession: body carries `tools`; a `tool_use` response parses to `.toolCalls`; a text response → `.text`; multi-turn messages (prior tool_result) serialize correctly; malformed `tool_use` (missing input) → graceful.
- `OpenAICompatibleProviderToolUseTests` (WI-4) — `tools`/`tool_calls` shape; `role:"tool"` reply serialization.
- `AIToolRegistryTests` (WI-5) — dispatch to the named tool; unknown tool → `isError` result (never throws); empty registry.
- `SearchCurrentBookToolTests` / `SearchOtherBooksToolTests` / `GetBookContentToolTests` (WI-6) — stub `SearchProviding` + in-memory `PersistenceActor`: valid input → result snippets; missing/invalid input (no query, unknown bookId, out-of-range) → `isError` result; byte-cap enforced; un-indexed book skipped.
- `AgenticChatDriverTests` (WI-7) — scripted stub provider returns `.toolCalls` then `.text`: the driver runs the tool, appends the result, re-sends, returns final text; **max-iteration cap** (provider keeps returning tool_calls → driver stops at the cap with a graceful message); a tool that errors → the error result is fed back, loop continues; zero tool_calls → returns text immediately.
- `AIChatViewModelToolUseTests` (WI-8) — flag OFF → existing streaming path (no driver); flag ON + provider supports → driver path produces the final assistant message; provider does NOT support tool-use → falls back to streaming.

## Risks + mitigations

- **`[String: Any]` Sendable holes** — tool input/JSON schemas are dictionaries. Mitigation: a `JSONValue` `Sendable`/`Codable` enum for all tool I/O; assemble the provider HTTP body via `JSONSerialization` from `JSONValue.toFoundation()` at the provider boundary only.
- **Unbounded loop / cost** — a model could loop forever. Mitigation: `maxIterations` cap (e.g. 6) in the driver; on cap, return the model's last text or a graceful "couldn't complete" message.
- **Provider capability divergence** — not every provider supports tool-use; OpenAI vs Anthropic shapes differ. Mitigation: `supportsToolUse` gate + per-provider impl; when unsupported, the chat silently uses the existing path (no user-visible failure).
- **Search index coverage + staleness (Gate-2 round-1 High 1 + round-2 Medium)** — import no longer auto-indexes; `SearchService.isIndexed` is in-memory only; persisted-index state lives in `SearchIndexStore.isBookIndexed`. `search_other_books` reuses the coordinator's FULL safe-restore guard set (`isBookIndexed` AND not `requiresReindex` AND non-nil TXT/MD `segment_base_offsets`), searches only books passing every guard, and reports the excluded count (never-indexed / requires-reindex / stale-offsets) so coverage is explicit and no stale index mis-resolves a result. No on-demand (re)indexing in v1.
- **`get_book_content` format/locality coverage (Gate-2 round-1 High 2)** — only local txt/md/pdf/epub are readable closed; native AZW3/MOBI has no closed-book text path, and remote-only/failed rows aren't local. Mitigation: explicit `unsupported_format` / `book_not_local` / `book_not_found` error results (never a throw, never silent); the model learns the limit from the result and routes around it.
- **Tool-read provenance vs the "Drew on" citations (Gate-2 round-1 Medium 3)** — the pre-send citation snapshot doesn't reflect tool-read sources. Mitigation: SUPPRESS citations on tool-driven replies in v1 (no misleading "Drew on"); per-tool-source provenance is a designed follow-up.
- **Mid-loop provider drift (Gate-2 round-1 Medium 1/2)** — a multi-turn op must not straddle a provider/model/key change. Mitigation: resolve ONE provider at loop start (mirrors the chapter-translation resolved-config seam) and pass it into the driver; never re-resolve per turn.
- **Token blow-up from tool results** — large chapter content. Mitigation: byte-cap every tool result (e.g. 8–12 KB, reusing `AIContextBudget`-style limits); `get_book_content` is range-limited.
- **Prompt-injection via book content** — a malicious book's text returned by a tool could carry "ignore previous instructions." Mitigation: tool results are returned as `tool_result` content (data, not system), and the system prompt frames tool output as untrusted data; documented as a known limitation (full mitigation is a research area).
- **Non-streaming UX regression** — tool-using answers don't stream. Accepted (answer appears when ready, like Summarize); documented; streaming-with-tools is a future enhancement.

## Backward compat

- `AIRequest`/`AIResponse` and the 5 existing action paths are UNCHANGED (the
  tool path is a parallel `AIToolRequest`/`AIToolTurn`). Summarize/Translate/
  Vocab/Explain/QA behave identically.
- `agenticTools` defaults OFF → the chat is byte-for-byte today's behavior until
  the flag flips. No persistence/schema change → no migration. Older providers
  without tool-use are gated out gracefully.

## Rule 51

The agentic LOOP is backend (no new UI). The chat shows only the final answer in
the existing bubble. **Any visible tool-call activity** (a "searching…" indicator,
a tool-call/results timeline, a coverage chip) is NEW UI not in
`vreader-fidelity-v1` → **a `needs-design` issue is filed at this plan's Gate-2
pass** for the "AI chat tool-activity affordance," and that surface is OUT of this
feature's scope. The feature ships fully functional without it (tools run
silently); the affordance is a follow-on once designed.

## Audit fixes applied (Gate-2 round 1)

Codex Gate-2 round-1 (threadId `019e9032-14f0-7960-bd23-863c71eac079`) returned
**2 High + 2 Medium** (model-assumption verification otherwise clean — all named
types/signatures confirmed; the parallel `AIToolRequest`/`AIToolTurn` design,
the `sendToolRequest` default-throws + `supportsToolUse` gate, and the silent-tools
Rule-51 boundary all endorsed). All four addressed in v2:

- **High 1 (search_other_books architecture)** → re-planned around the PERSISTENT
  `SearchIndexStore.isBookIndexed` (not in-memory `SearchService.isIndexed`),
  with offset restoration + explicit never-indexed coverage reporting. WI-6b.
- **High 2 (get_book_content coverage)** → narrowed to local txt/md/pdf/epub with
  explicit `unsupported_format` / `book_not_local` / `book_not_found` error
  results for native AZW3/MOBI + remote-only rows. WI-6c.
- **Medium 1+2 (provider snapshotting)** → resolve ONE provider at loop start
  (mirrors the translation resolved-config seam); the driver gets the resolved
  provider, never re-resolves. `AIService.resolveToolProvider()`.
- **Medium 3 (provenance/citations)** → suppress citations on tool-driven replies
  in v1 (`AgenticResult.usedTools`); per-tool provenance is a designed follow-up.
- **Cohesion** → WI-6 split into WI-6a/6b/6c (the two hard tools get their own
  WIs). Plan is now 10 WIs.

## Revision history

- v1 (2026-06-03) — initial plan from the Explore AI-infrastructure map.
- v2 (2026-06-03) — Gate-2 round-1 fixes (2 High + 2 Medium: search-index persistence, get_book_content format/locality gating, provider snapshotting, citation suppression) + WI-6 split.
- v3 (2026-06-03) — Gate-2 round-2 fix (1 Medium: `search_other_books` must carry forward the coordinator's FULL stale-index guard set — `requiresReindex` + nil-`segment_base_offsets` staleness, not just `isBookIndexed` — so a stale TXT/MD index never mis-resolves). Round 1's four findings + WI split all confirmed RESOLVED in round 2.
- **Gate-2 PASSED (2026-06-03)** — round-3 (threadId `019e903c-eb5c-7b72-a91e-19078841ca89`): the round-2 Medium RESOLVED, zero open Critical/High/Medium. Three rounds (threadIds `019e9032` r1 / `019e9038` r2 / `019e903c` r3) caught 2 High + 3 Medium real architecture issues (search-index persistence + staleness, get_book_content format/locality, provider snapshotting, citation provenance) — all folded into v3. Row → PLANNED; Gate 3 next.
