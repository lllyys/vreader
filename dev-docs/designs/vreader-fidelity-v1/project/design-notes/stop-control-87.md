# #1476 · AI input-bar Stop control (Feature #87)

> Resolves needs-design [#1476](https://github.com/lllyys/vreader/issues/1476) — the visible affordance for **Feature #87** (AI stop/cancel control).
> Source of truth: `VReader Chat Stop Canvas.html` (every state × themes). Components in `chat-stop-artboards.jsx`. Transcript: `chats/chat20-tool-activity-1483.md`.
> Status: **design landed — implementation deferred** (recorded, not built; Swift held for a separate go-ahead).

## Decision (binding) — the send disc morphs IN PLACE into a stop button

The composer's 32px send disc changes glyph + adds a sweeping activity ring while a response is in flight; tapping it aborts the request. Same disc, same position — no width gain, no second button that's dead 95% of the time (the chat-app convention: one primary control that's always the right thing to press).

The send disc's three resting looks, formalised:
- **disabled** — empty input. Neutral disc, muted arrow. Not pressable.
- **send** — has input. Accent disc, white arrow. Submits.
- **stop** — request in flight. Accent disc, **white square + sweeping ring**. Aborts.

**Partial reply is kept** on stop (the streamed text so far stays in the thread). **Summarize / Translate** route stop through their own generate control (those tabs have no composer disc — the generate/language control doubles as the stop affordance while a request is in flight).

## Production wiring (deferred — do NOT build without go-ahead)

- Chat: `AIChatView` send button (`chatSendButton`) renders the **stop** look while `viewModel.isLoading`; tapping it calls the cancellation primitive (`AIChatViewModel` must store the streaming `Task` + expose `cancelStreaming()` — the missing primitive #87 noted). Keep the partial assistant message.
- Summarize/Translate: their VMs already hold cancellable tasks (`AIAssistantViewModel.streamTask` / `AITranslationViewModel.translateTask`) — surface a stop state on the generate/language control. Rule 51 satisfied by this note + canvas.
