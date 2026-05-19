---
branch: fix/issue-932-debugreader-settle-waiter
threadId: 019e3f20-83e3-7182-9875-610badfba4fb
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit — issue #932 / bug #227

`DebugReaderRegistrySettleCleanupTests.case11b` failed deterministically:
`awaitReaderSettled(token: B, timeout: 2.0)` threw `.settleTimeout` fast
(~0.06s) instead of resolving when probe B's `markReaderSettled` fired.

## Diagnosis (Codex-confirmed)

Root cause is a **test-isolation defect**, not a production bug. The three
DebugBridge settle suites (`DebugReaderRegistrySettle{Core,EdgeCase,Cleanup}Tests`)
all drove the `DebugReaderRegistry.shared` singleton via `shared.reset()` in
their `makeRegistry()` helper. Swift Testing runs `@Test` methods in parallel.
`case11b` keeps a `settleWaiter` suspended for ~100ms (a background `Task`
unregisters probe A at +50ms, then `markReaderSettled(token: B)` at +100ms).
During that window a *concurrent* test's `shared.reset()` wipes `settleWaiters`
and resumes `case11b`'s waiter with a spurious `.settleTimeout`.

Empirical proof:
- `-parallel-testing-enabled NO` → all 6 cleanup tests pass (serial run).
- `-parallel-testing-enabled` default (ON) → `case11b` fails fast.

The GH issue's two hypotheses (A's `unregister` cancels B's waiter; same-key
reopen mis-tracks B's waiter) are both **incorrect** — the production
`awaitReaderSettled` / `markReaderSettled` / `clearSettleState` / `unregister`
same-key-reopen bookkeeping is correct, confirmed by the serial pass and by
tracing `clearSettleState(preservingToken:)`. The issue author's "3/3 isolated
runs" used a suite-level `-only-testing` filter, which still runs all six
methods in parallel — that is not true isolation.

## Fix

1. `vreader/Services/DebugBridge/DebugReaderRegistry.swift` — added a
   DEBUG-only static factory `makeIsolatedForTests() -> DebugReaderRegistry`
   that constructs a fresh instance via the existing `private init()`.
   `static let shared` and `private init()` are unchanged; production paths
   still use `shared`.
2. `DebugReaderRegistrySettle{Core,EdgeCase,Cleanup}Tests.swift` — each
   `makeRegistry()` now returns `DebugReaderRegistry.makeIsolatedForTests()`
   (a fresh per-test instance) instead of `DebugReaderRegistry.shared.reset()`.
   This removes the shared mutable state entirely; a fresh instance starts
   empty so no `reset()` is needed.

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| (bug #227 scope) | — | No findings. Diagnosis correct; settle-suite fix logically complete. A fresh instance starts with `activeReader`/`expectedReaderToken`/`waiters`/`settledKeys`/`settleWaiters`/webview-slots all empty or nil; dropping the helper-side `reset()` loses no needed cleanup. `makeIsolatedForTests()` is `@MainActor`-isolated (static member of a `@MainActor final class`); multiple instances raise no `Sendable` concern (access stays actor-confined). Factory is inside the same `#if DEBUG` region — no Release leak. No remaining `.shared` routing in the three fixed files. | none required |
| `vreaderTests/Services/DebugBridge/DebugReaderRegistryAwaitReaderTests.swift:40` | Medium | Same isolation-defect *class* — this suite still uses `DebugReaderRegistry.shared.reset()` and suspends on the registry's separate `waiters` store. Codex explicitly classified this as **out of bug #227's scope** (it is the `awaitReader`/`waiters` failure mode, not the `settleWaiters` one the issue reports, and it is not observed failing). | **Deferred — filed as a separate bug** per the repo working agreement (discover-a-bug → file, do not fix in an unrelated PR). New bug row added to `docs/bugs.md` + GH issue. NOT fixed in this PR. |

Codex verdict on the other sibling suites (`DebugReaderRegistryTests` XCTest,
`RealDebugBridgeContextTests`): leaving them on `.shared` does not undermine
bug #227 — the fixed settle suites no longer share the singleton, and those
suites are not part of the reported `awaitReaderSettled` race.

## Verification

3 settle suites (`Settle{Core,EdgeCase,Cleanup}Tests`, 17 tests) run in
parallel — passed 3/3 consecutive runs. `case11b` consistently resolves in
~0.10s via probe B's `markReaderSettled` (the full intended ~100ms window),
not by timeout.

## Summary verdict

ship-as-is. The fix is correct and complete for bug #227's scope. The
`DebugReaderRegistryAwaitReaderTests` Medium is a separate, out-of-scope
isolation defect on different state — filed as its own bug, not a blocker
for this PR under the repo's workflow.
