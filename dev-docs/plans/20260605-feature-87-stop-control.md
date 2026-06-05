# Feature #87 — AI input-bar Stop control (interrupt an in-flight AI request)

- **Feature row**: `docs/features.md` #87 (Medium, TODO → this plan).
- **Design (binding)**: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/stop-control-87.md` + `VReader Chat Stop Canvas.html` + `chat-stop-artboards.jsx` (needs-design #1476, delivered 2026-06-05).
- **Revision history**: v1 2026-06-05 (author: claude). v2 — cleared Gate-2 round-1 (Codex `019e9651`: 2C+4H+3M+1L). v3 — cleared round-2 (Codex `019e965a`: 2 new High + 1 Medium, cooperative-cancel guards). v4 2026-06-05 — cleared round-3 (Codex `019e9661`: rounds-1/2 confirmed; 1 new High on the whole-book pre-send await boundary). The plan converged 10→3→1 findings; round-3's single localized fix was applied (not escalated, per the converging trend). v5 2026-06-05 — Gate-2 round-4 (Codex `019e9668`) certified **0 Critical / 0 High** (whole-book fix + non-force-kill scope decision confirmed sound); the sole remaining Medium was a stale `send(_:)`-wrapper doc reference contradicting the adopted single-`sendMessage` launcher — removed (lines 94 + the WI-1 test). **Gate 2 PASSED** (0 open Critical/High/Medium; the resolved Medium was a mechanical doc-consistency fix on an already-design-certified plan, not warranting a further independent round).

## Problem

There is no user-facing way to stop an in-flight AI request on any AI tab. On
**Chat**, while a reply streams the send button (`chatSendButton`, `arrow.up`) is
merely `.disabled(!canSend)` (greyed out) and `AIChatView.sendCurrentMessage`
launches `Task { await viewModel.sendMessage(text) }` **discarding the handle**;
`AIChatViewModel` stores no `Task` and exposes no cancel → a chat stream is
**uncancellable**. **Summarize** (`AIAssistantViewModel`) and **Translate**
(`AITranslationViewModel`) DO hold a cancellable task internally
(`streamTask` / `translateTask`, cancelled only implicitly when a NEW request
supersedes the old, feature #65 WI-3) but neither surfaces a stop affordance. A
user who fires a long/wrong request must wait it out.

The design's binding decision: the composer's 32px send disc **morphs in place**
into a stop control (white square + sweeping ring) while a request is in flight;
tapping it aborts and **keeps the partial reply**. Summarize/Translate route stop
through their own generate/language control (no composer disc on those tabs).

## Surface area (file-by-file)

### WI-1 — Chat cancellation primitive + send-disc morph (behavioral)

**`vreader/ViewModels/AIChatViewModel.swift`** (modify; currently 341 lines — already over the ~300 guideline, so the new primitive goes in an extension file, see below)
- **Single task-owning launch API (H1).** `sendMessage(_:) async` stays the ONE public entry — the view, DebugBridge (`AIReaderPanel+DebugBridgeAIAction.swift:128` awaits it), and tests all keep calling it. It is rewritten to OWN the task internally rather than run inline:
  ```
  func sendMessage(_ text: String) async {
      let trimmed = …; guard !trimmed.isEmpty else { return }
      streamTask?.cancel()                 // supersede any in-flight op (resend)
      opCounter &+= 1; let opId = opCounter
      let task = Task { await self.runSend(trimmed, opId: opId) }
      streamTask = task
      await task.value                     // callers still get completion semantics
  }
  ```
  The old inline body becomes `private func runSend(_:opId:) async`. There is NO second public launcher (avoids the audit's double-entry hazard).
- Add `private var streamTask: Task<Void, Never>?` and `private var opCounter: UInt64 = 0`.
- Add `func cancelStreaming()` — `streamTask?.cancel()`. Idempotent / no-op when nothing is in flight. Does NOT clear `messages` (partial kept).
- **Resend race guard (H2).** `runSend`'s teardown is keyed to operation identity: `defer { if opId == opCounter { isLoading = false; streamTask = nil } }`. A superseded task's late defer cannot clobber the new op's `isLoading`/`streamTask`.
- **Whole-book pre-send await boundary (round-3 High).** In `.wholeBook` scope `runSend` awaits `onWholeBookReadRequested?()` (`AIChatViewModel.swift:193-195`) BEFORE the provider request, and that closure waits on the whole-book read task which `WholeBookRetrievalViewModel.cancel()` does NOT itself cancel. So: (a) add **`guard !Task.isCancelled, opId == opCounter else { return }` immediately after `await onWholeBookReadRequested?()`** (before the citation snapshot / placeholder append / provider start) so a Stop during pre-read lands no reply; (b) `cancelStreaming()` sets **`isLoading = false` immediately** (optimistic) so the Stop button is responsive even though the awaited read continues to unwind — the cancelled task's post-`await` guards discard any late work. **Scope decision:** #87 does NOT force-kill the in-flight whole-book digest read (that requires a #86 retrieval-cancellation capability `WholeBookRetrievalViewModel.cancel()` lacks today); the background read finishes harmlessly (it only caches the digest for the next question) and no reply is produced. Force-cancelling the read is a documented #86 follow-up.
- **Cancellation-aware streaming, partial kept, correct cleanup (C2):**
  - Stream into the assistant message by **stable identity** (`ChatMessage.id`), not a raw array index, so a concurrent `clearHistory()`/resend cannot corrupt the wrong row (also fixes H4's index invalidation). Write helper: look up the assistant message by id; if it no longer exists, stop writing.
  - On the chat streaming path (`consumeStream`): `for try await chunk { if Task.isCancelled { break }; append }`.
  - `catch is CancellationError` (or the `Task.isCancelled` break) → no `errorMessage`.
  - **Cleanup, corrected:** after the do/catch, remove the assistant placeholder **iff its content is still empty** — unconditionally, NOT gated on `!Task.isCancelled`. (Cancel-before-first-chunk → empty → removed; cancel-mid-stream → non-empty → kept; provider-returned-nothing → empty → removed.) This is the exact inversion the round-1 audit flagged.
- **Agentic stop = abort, no partial (H3) + cooperative-cancel post-`await` guard (round-2 High).** `AgenticChatDriver` has no interim text and no `Task.isCancelled` checkpoints, and `runAgenticTurn` writes `result.finalText` **unconditionally** after `await AgenticChatDriver.run(...)` (`AIChatViewModel.swift:281`). Swift cancellation is cooperative — a task cancelled after the driver already returned would still write a full reply. So: after the agentic `await`, **`guard !Task.isCancelled, opId == opCounter else { return }`** before mutating the assistant message (mirrors `AITranslationViewModel.swift:179`). On a clean abort the empty placeholder is removed (content empty). Do NOT claim partial-keep for the agentic path. (Real in-driver checkpointing is a follow-up, out of #87 scope.)
- **clearHistory safety (H4).** `clearHistory()` calls `cancelStreaming()` first, then clears; combined with id-based writes, a mid-flight clear cannot index-corrupt. The clear button is also `.disabled` while `isLoading` (defence in depth) — confirm this is consistent with the design (clear is not part of #87's stop affordance; disabling it during a request is the safe default).
- The new primitive (`streamTask`, `opCounter`, `sendMessage` launcher, `cancelStreaming`, `runSend`, id-based write helper) lands in a new extension file **`vreader/ViewModels/AIChatViewModel+Streaming.swift`** so the base file does not grow past ~300 lines (the existing `sendMessage`/`consumeStream`/`runAgenticTurn` move there with it).
- **Button-state resolver (M1)** — pure + unit-testable, includes the disabled dimension:
  `enum ComposerSendState { case disabled, send, stop }` +
  `static func composerSendState(isLoading: Bool, hasInput: Bool, isComposerDisabled: Bool) -> ComposerSendState`
  (`isLoading → .stop`; `!hasInput || isComposerDisabled → .disabled`; else `.send`). In a small sibling `vreader/Views/AI/AIChatComposerState.swift` (kept out of the VM to avoid view-state in the model).

**`vreader/Views/AI/AIChatView+Composer.swift`** (modify — the real send-button location, `:62-73`, NOT `AIChatView.swift`)
- The send disc (`:62-73`) binds to `ComposerSendState.resolve(isLoading: viewModel.isLoading, hasInput: !trimmedInput.isEmpty, isComposerDisabled: viewModel.isComposerDisabled)`. Three looks per the design: **disabled** (neutral disc, muted arrow, not pressable), **send** (accent disc, white `arrow.up`), **stop** (accent disc, white `square.fill` + sweeping ring overlay).
- Tap action: `.stop → viewModel.cancelStreaming()`; `.send → sendCurrentMessage()`; `.disabled → no-op`. `.disabled(state == .disabled)`.
- `sendCurrentMessage()` (`:129-132`) keeps `Task { await viewModel.sendMessage(text) }` — unchanged (the VM now owns cancellation internally, so the outer Task need not be retained).
- Accessibility: keep `accessibilityIdentifier("chatSendButton")`; `accessibilityLabel` = "Stop" in `.stop`, "Send" otherwise (XCUITest-observable morph).

### WI-2 — Translate stop affordance (behavioral)

**`vreader/ViewModels/AITranslationViewModel.swift`** (modify) — already owns a live `translateTask` (`:73`, assigned `:138`, cancelled on re-issue `:120` + teardown `:200`).
- Add `func cancelStreaming()` (public) — `translateTask?.cancel(); translateTask = nil; isLoading = false`; do NOT set `errorMessage` (a user stop is not an error). Guard with an opId-style check only if the existing re-issue path needs it (it already cancels-then-replaces, so a simple guarded clear suffices).

**`vreader/Views/Reader/TranslationPanel.swift`** (modify) — while `viewModel.isLoading`, the language/generate control renders the **stop** look; tap calls `cancelStreaming()`. Reuse the Chat stop visual.

### WI-3 — Summary stop affordance (behavioral, **VM-lifecycle refactor**, final WI)

**`vreader/ViewModels/AIAssistantViewModel.swift`** (modify) — **C1: today this VM does NOT stream and does NOT own a live task.** It uses a `state: AIAssistantState` enum (not `isLoading`), `performAction` is one-shot `await aiService.sendRequest(...)` (`:238`), writes `responseText = response.content; state = .complete` **unguarded** (`:239-240`), clears `responseText = ""` before launch (`:205`), and `streamTask` is vestigial (only ever `= nil` at `:183,:203`, never assigned).
- **Refactor to own the request Task:** in `summarize`/`performAction`, assign `streamTask = Task { … }` around the `await aiService.sendRequest` so the in-flight request is retained + cancellable. Apply the same opId resend guard.
- **Cooperative-cancel post-`await` guard (round-2 High):** gate EVERY success/error write after the `await` with **`guard !Task.isCancelled, opId == opCounter else { return }`** (the existing `AITranslationViewModel.swift:179` + `applyFailure:191` pattern) — `defer`/`CancellationError`-catch alone is insufficient because a cancelled task can return normally and still write `.complete`. Catch `CancellationError` → `return` (let `cancelStreaming()` own the terminal state).
- **Regenerate-preserve contract (round-2 Medium):** `performAction` clears `responseText` before launch, so a naive `state = .idle` on cancel would drop a previously-completed summary back to the idle prompt on a *regenerate*. Contract: **snapshot the prior `.complete` (responseText) before clearing**; `cancelStreaming()` restores it (`state = .complete`, `responseText = prior`) when a prior summary existed, and sets `state = .idle` only when cancelling an INITIAL request with no prior result. (Stop during regenerate keeps the last good summary; Stop during the first summarize returns to the prompt.)
- Add `func cancelStreaming()` (public) — cancels `streamTask`; applies the regenerate-preserve terminal state above. One-shot → **abort, no partial** ("keep partial summary" is impossible and is NOT claimed).

**`vreader/Views/Reader/AISummaryTabView.swift`** (modify) — while a request is in flight (`state == .loading`/`.streaming`), the generate control renders the **stop** look; tap calls `cancelStreaming()`.

### Files OUT of scope
- No SwiftData / persistence / backup change — all three AI surfaces are in-memory.
- No `AIService` / provider / streaming-protocol change — cancellation is Task-level at the VM; the provider stream/request is abandoned by the cancelled task.
- `AgenticChatDriver` internals — not modified; agentic Stop = abort-no-partial (H3).
- Real agentic interim-text checkpointing — out of scope (possible follow-up).

## Prior art / project precedent / rejected alternatives

- **Precedent — `AITranslationViewModel` (#65 WI-3)**: already stores `translateTask` and `.cancel()`s on re-issue + teardown. WI-1 mirrors that ownership pattern for Chat; WI-2 just makes the existing cancel user-triggerable.
- **Precedent — `AIAssistantViewModel.streamTask`**: same ownership shape; WI-2 surfaces it.
- **Rejected — a separate Stop button beside Send**: the design explicitly rejects a second control "dead 95% of the time"; the chat-app convention is one primary control that morphs. Adopted.
- **Rejected — discarding the partial reply on stop**: the design keeps the streamed-so-far text in the thread. Adopted (don't remove non-empty assistant content on cancel).
- **Rejected — a second public launcher (`send(_:)`) alongside `sendMessage`**: round-1 flagged this as a double-entry hazard (DebugBridge calls `sendMessage` directly). Adopted instead: `sendMessage(_:) async` stays the SOLE public entry and is rewritten to own the task internally (`streamTask = Task { await runSend(...) }; await task.value`); `runSend` is private. Existing `AIChatViewModelTests` keep awaiting `sendMessage` unchanged.

## Work-item sequencing

(M3: split Translate — a clean surface-the-existing-task WI — from Summary — a real VM-lifecycle refactor.)

| WI | Title | Tier | PR size | Notes |
|----|-------|------|---------|-------|
| WI-1 | Chat cancellation primitive + send-disc morph | behavioral | ~M (VM extension + composer + tests) | New primitive (single launch API, opId race guard, id-based writes, clearHistory safety, agentic abort) + headline UI. |
| WI-2 | Translate stop affordance | behavioral | ~S | Surface stop on `TranslationPanel`, wired to the EXISTING owned `translateTask`. |
| WI-3 | Summary stop affordance (VM-lifecycle refactor) | behavioral (final) | ~M | Refactor `AIAssistantViewModel` to OWN its request Task (it currently doesn't), add `cancelStreaming()` (abort-no-partial), surface stop on `AISummaryTabView`. Completes the feature → row `DONE`. |

## Test catalogue

**WI-1 — `vreaderTests/ViewModels/AIChatViewModelTests.swift`** (extend; gated-provider pattern mirrors `AITranslationTests.WI3GatedTranslationProvider`):
- `cancelStreaming_midStream_keepsPartialAssistantReply` — gate a provider, stream 2 chunks, `cancelStreaming()`, assert the assistant message retains the streamed text, `isLoading == false`, `errorMessage == nil`.
- `cancelStreaming_beforeFirstChunk_removesEmptyAssistantPlaceholder` — cancel before any chunk; assert the empty assistant placeholder is removed and the user message remains.
- `cancelStreaming_noActiveStream_isNoOp` — call with nothing in flight; no crash, no state change.
- `sendMessage_thenCancelStreaming_keepsPartial` — launch `Task { await vm.sendMessage(text) }` (the view's pattern), then `cancelStreaming()`; partial kept, `isLoading==false`, no error (poll `isLoading`; the sole public launcher owns the task).
- `composerSendState_resolves` — parameterized: `(isLoading,hasInput) → .stop/.send/.disabled`.
- Regression: existing `sendMessage` happy-path + agentic-path tests stay green.

- `sendMessage_thenSendMessageAgain_resendDoesNotClobberLoading` (H2) — gate op1, start op1 (`isLoading==true`), start op2 (supersedes op1), release op1's now-stale task; assert `isLoading` reflects op2 (still true), not clobbered false.
- `clearHistory_midStream_cancelsAndDoesNotCorrupt` (H4) — start a stream, `clearHistory()`, assert no crash, `messages` empty, `isLoading==false`.
- `agenticCancel_abortsTurn_noPartialAndNoError` (H3) — with `agenticTools` on + a gated tool provider, cancel mid-turn; assert the assistant placeholder is removed (no partial), `errorMessage==nil`.
- `cancelStreaming_duringWholeBookPreRead_clearsLoadingImmediately_landsNoReply` (round-3 High) — `.wholeBook` scope, gate `onWholeBookReadRequested`, `send`, `cancelStreaming()`: assert `isLoading==false` immediately and that when the gated read later releases no assistant reply is appended (post-`await` guard held).

**WI-2 — `vreaderTests/ViewModels/AITranslationTests.swift`** (extend, reuse `WI3GatedTranslationProvider`):
- `cancelStreaming_stopsTranslate_clearsLoading_noError`.

**WI-3 — `vreaderTests/.../AIAssistantViewModelTests.swift`** (extend, gated provider):
- `cancelStreaming_initialSummary_returnsToIdle_noError` (abort the first summarize → `.idle`, no partial, no error).
- `cancelStreaming_afterProviderReturnedNormally_doesNotWriteCompleted` (round-2 High: gate the provider to return BUT cancel before the continuation runs; assert the post-`await` guard prevents `.complete`/`responseText` write).
- `cancelStreaming_duringRegenerate_preservesPriorSummary` (round-2 Medium: complete a summary, regenerate, cancel mid-regenerate → prior `.complete` summary restored, NOT `.idle`).
- `summarize_ownsRetainedTask_cancellable` (the refactor: `streamTask` is now actually assigned).

**XCUITest (WI-1, optional Gate-5a aid)** — assert `chatSendButton` `accessibilityLabel` flips "Send"→"Stop" while `isLoading` (the morph is observable even though the *stream* needs a provider).

## Risks + mitigations

- **R1 — agentic turn cancellation is abort-only (no interim text).** `AgenticChatDriver` has no `Task.isCancelled` checkpoints and surfaces no partial. Mitigation: #87 defines agentic Stop as abort-the-turn-no-partial (explicit, tested via `agenticCancel_abortsTurn_noPartialAndNoError`); cancel takes effect at the driver's next provider `await`. Real agentic checkpointing is a documented follow-up, out of scope.
- **R2 — resend race could clobber `isLoading`.** Mitigation: opId operation token — teardown only when the finishing task is still current (`opId == opCounter`); covered by `…resendDoesNotClobberLoading`.
- **R3 — mid-flight `clearHistory()`/resend could index-corrupt the assistant message.** Mitigation: write streamed chunks by stable `ChatMessage.id`, not array index; `clearHistory()` cancels first; clear disabled while loading. Covered by `clearHistory_midStream_cancelsAndDoesNotCorrupt`.
- **R4 — Summary VM has no live task today.** Mitigation: WI-3 is scoped as a real VM-lifecycle refactor (assign `streamTask`), not a "surface the existing task" no-op; abort-no-partial semantics (no false "keep partial" claim).
- **R5 — Rule 51 for Translate/Summary stop visual.** The design note declares "Rule 51 satisfied by this note + canvas" and that the generate/language control "doubles as the stop affordance." Reuse the Chat stop visual; do not invent a new style.
- **R6 — Gate-5 device observation needs a live AI provider** (a stream/request to interrupt). Mitigation: the cancellation *logic* + button-morph *state* are fully unit/XCUITest-verifiable without a provider; the live abort observation is provider-gated → Gate-5 `partial` (provider-gated), same posture as the #314/#311 AI bugs. Implementation reaches `DONE`; `VERIFIED` awaits a provider-configured device pass.

## Audit fixes applied (Gate-2 round 1 — Codex `019e9651`)

| # | Sev | Finding | Resolution |
|---|-----|---------|-----------|
| 1 | Critical | `AIAssistantViewModel` doesn't stream / `streamTask` never assigned / one-shot `sendRequest` — Summary stop assumptions wrong | WI-3 rewritten as a VM-lifecycle refactor that ASSIGNS `streamTask`; "keep partial summary" dropped → abort-no-partial. |
| 2 | Critical | Empty-placeholder cleanup logic inverted (`!Task.isCancelled && empty` doesn't remove on cancel-before-chunk) | Cleanup corrected to unconditional "remove iff content still empty"; no `isCancelled` gate. |
| 3 | High | Double-entry: DebugBridge calls `sendMessage` directly; a separate `send()` wouldn't own that path | Collapsed to ONE public launch API — `sendMessage` itself owns the task; no second launcher; `runSend` private. |
| 4 | High | Resend race clobbers `isLoading` via stale `defer` | opId operation token guards teardown. |
| 5 | High | Agentic cancellation overstated (no checkpoints, no partial) | Agentic Stop defined as abort-no-partial; not claimed to keep partial. |
| 6 | High | `clearHistory()` mid-flight invalidates `assistantIndex` | id-based writes + clearHistory cancels first + clear disabled while loading. |
| 7 | Medium | `composerSendState` ignores `isComposerDisabled` | Resolver gains the `isComposerDisabled` dimension. |
| 8 | Medium | Wrong file paths (`AIChatView.swift`; `Views/AI/` for Summary/Translate) | Retargeted: `AIChatView+Composer.swift`; `Views/Reader/AISummaryTabView.swift` + `Views/Reader/TranslationPanel.swift`. |
| 9 | Medium | WI-2 not uniformly behavioral (Summary ≠ surface-existing-task) | Split into WI-2 Translate (easy) + WI-3 Summary (refactor). |
| 10 | Low | `[weak self]` Task unnecessary on `@MainActor @Observable` | Dropped; VM owns the task directly (`Task { … }` actor-bound). |

### Gate-2 round 2 — Codex `019e965a` (round-1 fixes confirmed resolved)

| # | Sev | Finding | Resolution |
|---|-----|---------|-----------|
| 11 | High | WI-3 Summary relies on `CancellationError`; a cancelled task that returns normally still writes `responseText`/`.complete` after Stop | Post-`await` guard `guard !Task.isCancelled, opId == opCounter else { return }` before every success/error write (mirrors `AITranslationViewModel:179/191`); catch `CancellationError` → return. |
| 12 | High | Chat agentic write after `AgenticChatDriver.run(...)` is unconditional (`AIChatViewModel:281`) → cancelled task lands a full reply | Same post-`await` guard before mutating the assistant message on the agentic path. |
| 13 | Medium | Summary `state = .idle` on cancel drops a prior completed summary on regenerate (`performAction` clears `responseText` at `:205`) | Regenerate-preserve contract: snapshot prior `.complete` before launch; `cancelStreaming()` restores it when present, `.idle` only for an initial request with no prior result. |

### Gate-2 round 3 — Codex `019e9661` (rounds-1/2 confirmed resolved)

| # | Sev | Finding | Resolution |
|---|-----|---------|-----------|
| 14 | High | Chat Stop misses the whole-book pre-send await boundary (`onWholeBookReadRequested?()` at `AIChatViewModel:193-195`; `WholeBookRetrievalViewModel.cancel()` doesn't cancel the read) → Stop can stay stuck / proceed into request setup | Post-`await` guard after `onWholeBookReadRequested?()`; `cancelStreaming()` clears `isLoading` immediately (responsive); explicit scope decision that #87 doesn't force-kill the in-flight read (harmless background completion; #86 follow-up). |

## Backward compat

No persisted state, schema, or backup-format change (all three AI surfaces are
in-memory). Existing send/summarize/translate happy paths are unchanged when no
stop is issued. Older clients/backups unaffected (no data shape touched).
