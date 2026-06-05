---
branch: feat/feature-87-wi-3-summary-stop
threadId: 019e96b3-9d92-76e3-b7a9-8b0d04374d69
rounds: 2
final_verdict: ship-as-is
date: 2026-06-05
---

# Gate-4 Implementation Audit — Feature #87 WI-3 (Summary stop, FINAL WI)

Independent Codex audit (author = implementer subagent + orchestrator fixes; auditor = Codex via `scripts/run-codex.sh`). 2 rounds → `ship-as-is` (the round-2 `block` was solely the pre-commit untracked-file state, resolved by committing the new file in this WI).

## Scope
`vreader/ViewModels/AIAssistantViewModel.swift` (own the request Task; access relaxations), `AIAssistantViewModel+Streaming.swift` (new — `cancelStreaming`, `performAction`, `runRequest`), `vreader/Views/Reader/AISummaryTabView.swift` (in-place Stop morph), `vreaderTests/Views/Reader/AISummaryTabViewTests.swift`.

## Round 1 — Codex `019e96aa-d257-75a1-8f8e-6d0de1ea307d`
| file:line | sev | issue | resolution |
|---|---|---|---|
| AIAssistantViewModel+Streaming.swift:138 | Medium | `runRequest` has no ENTRY guard — a cancelled/superseded pre-start task still enters `sendRequest` (runs provider work, populates cache) | **Fixed**: top `guard !Task.isCancelled, opId == opCounter else { return }` before the provider call; `defer { if opId == opCounter { streamTask = nil } }` nils the owned task on settle. |
| AIAssistantViewModel+Streaming.swift:46 | Medium | `cancelStreaming()` not idempotent — a stray/late call after the request settled would wipe a completed summary to `.idle` | **Fixed**: `guard case .loading = state else { return }` — Stop is a no-op when not in flight. |
| AISummaryTabViewTests.swift:304 | Medium | `summarize_ownsRetainedTask_cancellable` doesn't prove task ownership (passes even if `streamTask` were never assigned) | **Fixed**: `GatedAIProvider`/`GateState` now record `Task.isCancelled` after the gate; the test asserts `observedCancellation == true` — proving the retained task was cancelled. |

## Round 2 — Codex `019e96b3-9d92-76e3-b7a9-8b0d04374d69`
3 round-1 Mediums confirmed resolved (not re-flagged). Sole remaining finding: `pbxproj` references `AIAssistantViewModel+Streaming.swift` while `git status` showed it untracked — a **pre-commit working-tree state**, not a code defect; resolved by `git add`-ing the new file in this WI's commit (the committed changeset tracks it). No code Critical/High/Medium remain.

## Verdict
`ship-as-is`. The VM-lifecycle refactor (own the one-shot request in a retained `streamTask` + opId token, entry + post-`await` cooperative-cancel guards on every write, regenerate-preserve contract, idempotent in-flight-gated `cancelStreaming`) is race-correct and unit-pinned (incl. a proof-of-ownership cancellation test). `AIAssistantViewModelTests` + `AISummaryTabViewTests` → `RUN-TESTS RESULT: SUCCEEDED`.
