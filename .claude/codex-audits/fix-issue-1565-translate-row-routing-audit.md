---
branch: fix/issue-1565-translate-row-routing
threadId: 019e9fb1-d73a-7603-8ddf-f52127bda8e8
rounds: 2
final_verdict: ship-as-is
date: 2026-06-07
---

# Codex audit — Bug #328 / GH #1565 translate-row tap routing

Fix: tapping the Book Details "Translate entire book…" row while a job is
already running now opens the in-progress `TranslateStatusSheet` instead of
re-opening the estimate/confirm alert.

## Scope (Swift diff vs `main`)

- `vreader/ViewModels/BookTranslationViewModel.swift` — new `handleTranslateRowTap(...)`
  (refresh `progress` from the coordinator, branch on `isRunning` → status sheet,
  else `presentConfirm`); race-hardening in `presentConfirm` + `confirmTranslate`.
- `vreader/Views/Reader/BookDetails/BookDetailsSheet+Actions.swift` — `.translateBook`
  tap calls `handleTranslateRowTap`.
- tests: `BookTranslationViewModelTests` (running→status, idle→confirm,
  presentConfirm-while-running→status).

## Round 1 (threadId 019e9fb1-d73a-7603-8ddf-f52127bda8e8)

**1 Medium** — `handleTranslateRowTap` snapshotted `currentProgress` once; a
job starting on another surface (library long-press / reader chrome) DURING
`presentConfirm`'s estimate `await` could still surface the confirm alert for a
now-running job (partial reintroduction of #328 under a race). The
one-job-per-book invariant prevents a duplicate run, but the user would have to
re-confirm to reach progress/cancel.

**Resolution (applied exactly as recommended):** `presentConfirm` now re-checks
`coordinator.currentProgress(forBookWithKey:)` after resolving the estimate and
before setting `isShowingConfirmAlert`; if running, it opens the status sheet
and returns. `confirmTranslate` re-checks at entry and, if already running,
opens the status sheet without issuing a redundant `coordinator.start`. The
re-check inside `presentConfirm` covers ALL callers, not just the row tap.

Phase routing confirmed correct: only `.running` re-opens the status sheet;
`.idle`/`.completed`/`.cancelled`/`.failed` fall through to confirm (consistent
with the issue's stated expectation — the status sheet is a live progress/cancel
surface; terminal states restart/resume through confirm).

## Round 2 (threadId 019e9fb6-01a4-7a00-856c-af6c9bbccc96)

**No findings.** The Round-1 Medium is closed; `confirmTranslate`'s
already-running branch still calls `startObserving()` (no skipped setup);
reassigning `progress` from `currentProgress` is consistent with the VM's
UI-mirror role; `@MainActor`/actor-await usage is correct (the awaits cross to
the coordinator actor and resume on the main actor before mutating VM state).

## Verdict

**ship-as-is** after 2 rounds. Three new VM tests pass under
`scripts/run-tests.sh` (the running-state tests drive the real
`BookTranslationCoordinator` actor through its start→running transition via a
mocked network sender — the legitimate external boundary).
