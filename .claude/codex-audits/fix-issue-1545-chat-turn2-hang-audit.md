---
branch: fix/issue-1545-chat-turn2-hang
threadId: 019e9b7b-1cf7-7071-8981-ed9e0e62904f
rounds: 1
final_verdict: ship-as-is
date: 2026-06-06
---

# Codex audit — Bug #323 (GH #1545): AI chat hangs on the second message

Independent Codex audit (gpt-5.4, read-only sandbox) via `scripts/run-codex.sh`
(stdin-isolated, watchdog-bounded per rule 53). `RUN-CODEX RESULT: SUCCEEDED`.

## Scope

Two production files:

- `vreader/ViewModels/AIChatViewModel+Streaming.swift` — **Fix A**: reset
  `isLoading = false` / `streamTask = nil` BEFORE the awaited
  `await saveSettledTurn(...)` (previously only in the trailing `defer`, which
  runs at scope exit AFTER the save). Decouples the composer from a stalled
  `sessionOpChain` lane (the deterministic root cause). The save stays awaited.
- `vreader/Services/AI/AgenticChatDriver.swift` — **Fix B**: observe cancellation
  in the bounded loop so a Stop aborts a runaway tool loop promptly.

## Findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| AgenticChatDriver.swift (inner tool-call loop) | Medium | `Task.checkCancellation()` only at the OUTER iteration top → a Stop does not abort a round already executing tools (a round with many tool calls, or a long-running tool). "Don't grind after Stop" was fixed for round-trips but not for in-round tool work. | **FIXED** — added `try Task.checkCancellation()` inside `for call in turn.toolCalls` (before each `registry.run(call)`), so a Stop during a multi-tool round aborts before the next call. New deterministic test `cancellationBreaksInRound` (gated tool parks mid-round → cancel → asserts the 2nd in-round tool never runs). Deep per-tool cancellation (making `AITool.run` cancellation-aware so a single long-running tool can be interrupted mid-call) is a documented follow-up — the in-app tools are local + fast, so the per-call check is the appropriate bound. |

### Fix A — explicitly cleared by the auditor (no findings)

Codex verbatim: *"I did not find a correctness issue in `AIChatViewModel+Streaming.swift` from moving the `isLoading = false` / `streamTask = nil` reset earlier. On `@MainActor`, the `opId == opCounter` guard still prevents stale teardown from clobbering a newer send, the trailing `defer` still covers the early-return paths, and the settled-turn save is still awaited on the normal path. Clearing `streamTask` before the save does mean a later resend/transition no longer cancels that already-settled task, but at that point the task is only awaiting persistence; the remaining writes are already guarded, so I don't see a new UI-state or op-identity race from that change."* It also confirmed `saveSettledTurn(...)` is not skipped on any new path (still awaited when the op is current; the session-identity guard inside still discards switched-away turns), and found no dead code / file-structure issues.

## Verdict

**ship-as-is.** Zero Critical/High. The single Medium is fixed in-diff and covered
by a new deterministic test. Deep per-tool cancellation deferred (local fast
tools; tracked).

## Tests (RED → GREEN, real subsystem boundaries)

- `AIChatViewModelTurn2HangTests.secondMessage_composerReEnables_whenSessionSaveStalls`
  — RED on pre-fix-A code (`** TEST FAILED **`, no hang — bounded helpers), GREEN
  after Fix A. Drives real `runSend` / `runSerializedSessionOp` / `saveSettledTurn`
  with the session store's `gateUpdate()` stall (only the persistence store stubbed).
- `AgenticChatDriverTests.cancellationBreaksLoop` + `cancellationBreaksInRound`
  — outer-loop + in-round cancellation, GREEN.
- Regression: `AIChatViewModelSessionsTests` (28), `AIChatViewModelAgenticTests`
  (8), `AgenticChatDriverTests` (11), `AIChatViewModelTurn2HangTests` (2) — all
  pass. Fix A's reorder did NOT break the session-save observability tests (the
  save is still awaited).
