---
branch: fix/issue-1545-aichat-2nd-message-freeze
threadId: 019eabba-108a-7ff2-badf-ab01730aa3d1
rounds: 1
final_verdict: ship-as-is
date: 2026-06-09
---

# Codex Audit — Bug #323 / GH #1545 (AI chat 2nd-message / long-reply whole-app freeze)

## Root cause (reopened mechanism)

`AIChatViewModel.consumeStream` mutated the `@Observable messages` array per
streamed token (`messages[index].content += chunk.text`). Each mutation
re-publishes the whole array, so SwiftUI re-evaluated + re-laid the ENTIRE
transcript on EVERY token (cost ≈ history-length × reply-length). Fast providers
emit hundreds of tokens/sec → main-thread saturation → the app freezes during a
long reply / on the 2nd+ message. (The earlier v3.59.13 fix addressed a different
facet — the composer-vs-save coupling — which is why the freeze survived it.)

## Fix

New value type `StreamCoalescer` (`vreader/ViewModels/StreamCoalescer.swift`)
batches streamed deltas: the first chunk flushes promptly (first token visible),
then flush when pending reaches `maxChars` (96) OR `minIntervalNanos` (33 ms)
elapsed since the last flush; `drain()` flushes the remainder. `consumeStream`
feeds chunks through it with `DispatchTime.now().uptimeNanoseconds`. Per-token
publishes collapse to ≤ ~30/s, eliminating the churn.

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| AIChatViewModel+Streaming.swift (`consumeStream`) | High | `coalescer.drain()` ran only after a NORMAL loop exit. A stream that THROWS (CancellationError / provider error) propagates out before the post-loop drain → the last buffered batch is dropped, regressing the "keep the partial reply" contract (pre-fix, each token was appended immediately). | **Fixed** — wrapped the loop in `do { … } catch { drain(); throw }` so the buffered tail is drained on the error path too, then rethrown; the normal post-loop drain stays. Test: `AIChatStreamCoalesceTests.bufferedTailKeptWhenStreamThrows` (chunk 1 flushes, chunk 2 buffers, stream throws → final content keeps chunk 2). |

Codex confirmed (no other findings): the `now &- last` unsigned subtraction is
safe (both from monotonic `DispatchTime.now().uptimeNanoseconds`); the `nil`
first-flush logic is correct; `StreamCoalescer` is a local var inside the
`@MainActor` `consumeStream`; 96 chars / 33 ms is a reasonable initial policy.

## Tests

- `StreamCoalescerTests` — first-chunk-prompt, char-batching, time-interval flush,
  losslessness, empty drain (deterministic, injected `now`).
- `AIChatStreamCoalesceTests` — drain-on-throw keeps the buffered tail;
  normal multi-chunk stream assembles the full text.
- Regression: `AIChatViewModelTests`, `AIChatViewModelTurn2HangTests` green.

## Verdict

ship-as-is — the one High fixed + covered; coalescing eliminates the per-token
churn. Device verification: 2-message chat smoke on the merged build (no freeze,
composer re-enables after each turn).
