---
branch: fix/issue-954-selective-restore-progress-flake
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex Audit — Bug #230 / GH #954 flaky-test fix

## Audit context

Test-only change, fixed inline by the orchestrator (single-file, well-understood
race). Codex MCP not invoked — manual fallback per `.claude/rules/47-feature-workflow.md`.
The change touches exactly one test method's local harness; no production code,
no protocol, no public surface.

## Diff under audit

```
 vreaderTests/Services/Backup/SelectiveRestoreCoordinatorTests.swift | ~18 +/-
```

One test method (`progress_movesMonotonically_through3Phases`): the local
`actor Collector` + `progress: { v in Task { await collector.record(v) } }` +
double `await Task.yield()` replaced with a synchronous lock-guarded
`final class Collector: @unchecked Sendable` recording inline
(`progress: { v in collector.record(v) }`).

## Manual Audit Evidence

### Files read

- `vreaderTests/Services/Backup/SelectiveRestoreCoordinatorTests.swift` (the test method, full)
- `vreader/Services/Backup/SelectiveRestoreCoordinator.swift` line 104-110 — the `restoreSelectively` signature, confirming `progress: @Sendable (Double) -> Void` is a SYNCHRONOUS closure (not async), so inline recording is valid and ordered.

### Symbols / signatures verified

- `restoreSelectively(manifest:selectedKeys:metadataSections:progress:)` — `progress` is `@Sendable (Double) -> Void`. Synchronous. The coordinator calls it inline as it advances through phases, so by the time the `await`ed call returns, every progress value has been delivered to the closure in call order.
- `NSLock` — used for thread-safety because `@Sendable` means the closure could in principle be invoked from any executor; the lock makes `record` / `values` safe regardless of caller executor. In practice the coordinator calls it serially, but the lock is correct defense.
- `@unchecked Sendable` on the `Collector` class — required because it holds mutable `storage` behind a manual lock (the compiler can't prove the lock discipline). Standard pattern for lock-guarded value holders.

### Edge cases checked

- **Ordering**: synchronous inline recording preserves call order (the bug was the detached Task losing order under load). FIXED — values are appended in the exact order the coordinator calls `progress`.
- **Completeness**: no `Task.yield()` reliance — all values are recorded before `restoreSelectively` returns because the closure is synchronous. The final `1.0` callback runs inline before the `await`ed call completes. FIXED.
- **Thread-safety**: `NSLock` guards both `record` (write) and `values` (read). Even if a future coordinator change calls `progress` off the main executor, the lock keeps `storage` consistent.
- **Determinism**: 5/5 consecutive isolated runs green (the bug was a load-dependent intermittent — 5/5 is strong evidence the structural race is gone, since the old code would flake under the same isolated-run conditions when the scheduler delayed the last Task).

### Risks accepted

- **Cannot deterministically reproduce the OLD flake on demand** (it was load-dependent). The fix removes the race structurally (no detached Task, no yield-drain), which is the correct fix regardless of repro. 5/5 green confirms no regression. Risk: low — the change only makes the test stricter (synchronous capture), it cannot introduce a new flake.
- **`@unchecked Sendable`** — accepted because the lock discipline is correct and self-contained (4 lines). The alternative (keeping the actor) is what caused the bug.

### Tests added or intentionally deferred

- No new test added — the FIX IS the test. The deterministic version of `progress_movesMonotonically_through3Phases` is itself the regression guard. Running it 5/5 green is the verification.

## Per-dimension review

| # | Dimension | Finding | Severity |
|---|---|---|---|
| 1 | Correctness | Removes the detached-Task ordering race; synchronous inline recording is ordered + complete by call-return. | none |
| 2 | Edge cases | Ordering / completeness / thread-safety / determinism all checked above. | none |
| 3 | Security | n/a — test-only. | none |
| 4 | Duplicate code | The `Collector` is local to the one test method; no duplication. | none |
| 5 | Dead code | Removed the `Task.yield()` drain (was dead reliance). | none |
| 6 | Shortcuts | None — this is the canonical fix direction the bug row itself proposed ("collect progress values synchronously in the closure, no detached Task"). | none |
| 7 | VReader compliance | Swift 6 concurrency: `@unchecked Sendable` + `NSLock` is the sanctioned lock-guarded-value pattern; no actor-isolation violation. | none |
| 8 | Bridge safety | n/a. | none |

## Final verdict

**ship-as-is**. The fix is the exact direction the bug row proposed, it's test-only, it's deterministic (5/5), and it removes the race structurally rather than papering over it with a longer yield/sleep.
