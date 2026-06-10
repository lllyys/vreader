---
branch: feat/feature-98-wi-1-background-token
threadId: 019eb31f-675a-7c80-a6af-e716649059a3
rounds: 3
final_verdict: ship-as-is
date: 2026-06-11
---

# Codex Gate-4 audit — feature #98 WI-1 (BackgroundExecutionToken + grace windows + expiry checkpoint)

Runner: `scripts/run-codex.sh` (codex exec, gpt-5.4, read-only sandbox).
Sessions: r1 `019eb311-9c7e-7bc0-8a4c-fad85667f080`, r2
`019eb319-1b77-7b03-8469-d769f9b1dbe1`, r3
`019eb31f-675a-7c80-a6af-e716649059a3`.

## Round 1 — needs-fixes

| Finding | Severity | Resolution |
|---|---|---|
| `BackgroundExecutionToken.swift:83` — expiry handler captured the token WEAKLY; a token dropped without `end()` left the expiry handler unable to end the task (iOS may terminate the app) | Medium | FIXED (f26c64f7): end-state moved to a shared `@MainActor EndState` box captured STRONGLY by the expiration handler; both `end()` and the handler consume it idempotently; new test `leakedToken_expiryStillEndsTheTask` |
| `BookTranslationCoordinatorTests.swift:413` — expiry test gated `sourceText`, not the translate request; a token narrowed to source-text loading would still pass | Medium | FIXED (f26c64f7): `GatedTranslationSender` suspends inside `sendTranslationRequest`; expiry fires mid-request |
| count-only begin/end assertions (coordinator + 4 VM tests) | Low | FIXED (f26c64f7): exact `UIBackgroundTaskIdentifier` sequence assertions |

## Round 2 — needs-fixes

| Finding | Severity | Resolution |
|---|---|---|
| `BookTranslationCoordinator.swift:118` — expiry handler enqueued the stop flag via fire-and-forget `Task {}` actor hop; the job loop could observe the flag as false and start another unit after iOS expired the window (the test masked this by polling the flag before releasing the gate) | Medium | FIXED (d5c07e59): per-run lock-backed `BackgroundExpiryLatch` (`OSAllocatedUnfairLock<Bool>`) set synchronously in the `@MainActor` handler, read synchronously between units; created per `start()` so stale inheritance is impossible by construction; actor-side `expiredJobKeys` + test seams removed; resume test drives a real expiry → restart |

Round 2 also confirmed: r1-M1/M2/L1 resolved; `nonisolated(unsafe)` deinit
read acceptable (DEBUG best-effort only); requester→handler→EndState→requester
retain shape acceptable (UIApplication process-lifetime; mock test-only).

## Round 3 — clean

"No blocking findings. The round-2 race is resolved: the expiration handler
now sets a per-run synchronous latch directly from the @MainActor expiry
callback, and the loop reads that latch synchronously before starting the
next unit. The new restart test exercises a real expiry → stop → restart
path." VERDICT: clean.

## Summary

3 rounds, 4 findings (3 Medium, 1 Low), all fixed; all three suites
(`BackgroundExecutionTokenTests`, `BookTranslationCoordinatorTests`,
`ChapterReTranslateViewModelTests`) green after each round. Ship as-is.
