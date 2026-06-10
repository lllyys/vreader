---
branch: feat/feature-98-wi-2-resume-interrupted
threadId: 019eb338-89ab-7c33-b5b7-37b42e5cfda0
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Codex Gate-4 audit — feature #98 WI-2 (resolver seam + descriptor + resume-at-reader-open)

Runner: `scripts/run-codex.sh` (codex exec, gpt-5.4, read-only sandbox).
Sessions: r1 `019eb332-5f16-7993-89b4-c4de74913bf1`, r2
`019eb338-89ab-7c33-b5b7-37b42e5cfda0`.

## Round 1 — needs-fixes

| Finding | Severity | Resolution |
|---|---|---|
| `BookTranslationCoordinator.swift:192,441` — a stale descriptor survived a manual restart with a different provider: expired-with-A → manual restart with B → failure → auto-resume wrongly retried A | Medium | FIXED (ec1d1268): `start()` refreshes an EXISTING descriptor to the current run's `{targetLanguage, style, providerProfileID}` (runs with no prior descriptor still don't create one); regression test `manualRestart_refreshesRetainedDescriptor_toTheNewRun` |
| `BookTranslationCoordinator.swift:216` — the zero-unit completion path left a retained descriptor behind → every later provider arrival re-resumed an already-finished job | Medium | FIXED (ec1d1268): the `total == 0` branch removes the descriptor before publishing `.completed`; test `zeroUnitCompletion_clearsRetainedDescriptor` |
| `InterruptedTranslationJobStore.swift:49,71` — `rawEntries()` whole-dictionary `as? [String: Data]` cast dropped ALL valid siblings when one value had a wrong type; the next save/remove rewrote the store from `{}` | Low | FIXED (ec1d1268): per-value `compactMapValues { $0 as? Data }`; test `interruptedJobStore_survivesMixedTypeCorruption_keepsSiblings` |

## Round 2 — clean

All three round-1 findings confirmed resolved with their regression tests;
"Fresh issues: none in the latest fix set or the wider WI-2 diff."
VERDICT: clean.

## Summary

2 rounds, 3 findings (2 Medium, 1 Low), all fixed;
`BookTranslationCoordinatorTests` (8 new WI-2 tests + 3 regression tests)
and `BookTranslationViewModelTests` (restartObserving) green. Ship as-is.
