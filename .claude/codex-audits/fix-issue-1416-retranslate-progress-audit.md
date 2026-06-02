---
branch: fix/issue-1416-retranslate-progress
threadId: codex-exec (RUN-CODEX RESULT SUCCEEDED, see /tmp/fix1416-audit.txt)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Gate-4 Codex audit — Bug #311 / #1416 (re-translate progress fabricated/coarse)

Independent audit (Codex gpt-5.4, high effort, read-only) of the diff threading
a real per-chunk `onChunkProgress` callback from `ChapterTranslationService`
through `ChapterReTranslating` into `ChapterReTranslateViewModel`. One round;
author=this session, auditor=Codex (rule-48 separation).

## Findings & resolutions

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `ChapterReTranslateViewModel.swift:348` | Medium | The progress tick is delivered via an unstructured `Task { @MainActor }` with no run-identity check. A queued tick from an old/cancelled run could land after `cancel()`/`dismiss()` reset `progress` to 0.0 (or during a rapid cancel→retry) and push the idle/new bar into the 0.5–0.95 band. The `max()` guard only protects the terminal 1.0, not the reset-to-0.0 paths. | **FIXED** — added a per-submit `runGeneration` token: `submit()` bumps it and captures the value into the callback; `applyChunkProgress` drops a tick unless `generation == runGeneration && sheetState == .running`. `cancel()` and `dismiss()` also bump the generation to invalidate queued ticks. |
| 2 | `ChapterReTranslateViewModelTests.swift:202` | Low | The new tests cover plumbing + mapping bounds but not the stale-tick race above. | **FIXED** — added `staleChunkTick_afterDismiss_doesNotMoveIdleBar`: captures the callback, dismisses, fires a late tick, drains the main-actor hop, asserts `progress` stays 0.0. |

## Verified by the auditor (no change needed)

- `translate()` callers are covered by the new default `nil`
  (`BookTranslationCoordinator`, `ChapterTranslationPrefetcher`).
- `ChapterReTranslating` has only the production service extension + the test
  mock as conformers — no other call site breaks on the new (no-default) param.
- The `0.5 → 0.95` mapping is sound: clamps over/under-count, handles
  `totalChunks <= 0` with no division by zero.
- No leftover fake-progress comments; the ETA heuristic note is still accurate
  (the design's `(1-progress)*18s`, now driven by real progress — view unchanged).

## Verdict

`ship-as-is` — both findings fixed (Medium: run-generation + `.running` guard;
Low: stale-tick regression test). Targeted suites green
(`ChapterReTranslateViewModelTests`, `ChapterTranslationServiceTests`).
