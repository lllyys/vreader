---
branch: feat/feature-87-wi-1-chat-stop
threadId: 019e968d-dfd5-7672-bb11-72d1b59fa15a
rounds: 3
final_verdict: ship-as-is
date: 2026-06-05
---

# Gate-4 Implementation Audit — Feature #87 WI-1 (Chat AI stop/cancel)

Independent Codex audit (author = implementer subagent + orchestrator fixes; auditor = Codex via `scripts/run-codex.sh`). 3 rounds, converged to `ship-as-is`.

## Scope
`vreader/ViewModels/AIChatViewModel.swift`, `AIChatViewModel+Streaming.swift` (new), `vreader/Views/AI/AIChatComposerState.swift` (new), `AIChatView+Composer.swift`, `vreaderTests/ViewModels/AIChatViewModelTests.swift`, `AIChatViewModelAgenticTests.swift`.

## Round 1 — Codex `019e967b-8e62-7393-a575-060e8cb6016a`
| file:line | sev | issue | resolution |
|---|---|---|---|
| AIChatViewModel+Streaming.swift:127 | High | Cancelled/superseded op still writes `errorMessage` in the non-`CancellationError` catch arms (stale-error race) | **Fixed**: `if !Task.isCancelled, opId == opCounter { errorMessage = … }` on both the `AIError` and generic catch. |
| AIChatViewModelTests.swift:555 | Medium | Agentic-cancel + cancellation-adjacent error paths unpinned | **Fixed**: added `cancelledOpErroring_doesNotSurfaceStaleError` + `agenticCancel_abortsTurn_noPartialNoError` (gated `ToolGate`). |
| AIChatView+Composer.swift:99 | Low | `canSend` now dead code | **Fixed**: removed (state resolved via `composerSendState`). |
| AIChatViewModelTests.swift:1 | Low | Test file >300 lines | **Accepted** with rationale: file was already 634 lines pre-WI-1; a focused split is a tracked follow-up. |

## Round 2 — Codex `019e9687-9932-72f2-9d14-44e4c68bb40f`
| file:line | sev | issue | resolution |
|---|---|---|---|
| AIChatViewModel+Streaming.swift:59 | High | `runSend` mutates `errorMessage`/appends user msg/sets `isLoading` BEFORE the line-82 guard → an op cancelled/superseded before its child task runs leaves a ghost user turn + clears errorMessage | **Fixed**: early `guard !Task.isCancelled, opId == opCounter else { return }` at the very top of `runSend`, before any state mutation. |
| AIChatViewModelTests.swift:899 | Medium | `ChatStreamGateRegistry.release` is a lost no-op if `registerCall` hasn't run → test hang | **Fixed**: registry buffers `pendingReleases`; `ChatStreamGate` gains `init(preReleased:)`. |
| AIChatViewModelTests.swift:723 | Medium | Stale-error test only exercises the `Task.isCancelled` half of the catch guard, not the `opId` (supersede) half | **Fixed**: added `supersededOpErroring_doesNotSurfaceStaleError`. |

## Round 3 — Codex `019e968d-dfd5-7672-bb11-72d1b59fa15a`
All round-2 findings confirmed resolved; **no remaining or new Critical/High/Medium**. Verdict: `ship-as-is`.

## Verdict
`ship-as-is`. The cancellation primitive (single task-owning `sendMessage` launcher, opId operation token, post-`await` cooperative-cancel guards on every success/error write incl. the agentic + whole-book-boundary paths, id-based message writes, `clearHistory` cancel-first) is race-correct and unit-pinned. Targeted suites green: `AIChatViewModelTests` + `ComposerSendStateTests` + `AIChatViewModelAgenticTests` → `RUN-TESTS RESULT: SUCCEEDED`.
