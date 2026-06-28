---
branch: feat/feature-122-wi-4-stats-integration
threadId: codex-exec-f122-wi4
rounds: 2
final_verdict: ship-as-is
date: 2026-06-28
---

# Feature #122 WI-4 (final) — reading-stats DI + TxtReader lifecycle hook + acceptance

WI-4 wires the process-singleton stats stack (`ReadingStatsRepository` +
`ReadingTimeTracker`) into `AppContainer`, brackets a reading session from the
TXT reader's lifecycle, shows the auto-fading in-reader session pill, and adds
the on-device acceptance test driving the real tracker→repo→Room path.

Files: `VReaderApp.kt`, `reader/TxtReaderActivity.kt`, `stats/ReadingTimeTracker.kt`,
`androidTest/.../stats/ReadingStatsConnectedTest.kt`.

## Round 1 — findings

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | TxtReaderActivity (stats block) | **Critical** | `tracker.stop()` launched in `rememberCoroutineScope` (composition-owned) — can be cancelled during teardown before the suspending `ReadingStatsDao.addMinutes` commits; `flushLocked()` advances accounting marks before the write, so cancellation permanently drops minutes | FIXED — start/stop now launched on `container.appScope` (process-lifetime `SupervisorJob`, survives the Activity teardown); `flushLocked()` wraps the Room writes in `withContext(NonCancellable)` so the durable bank can't be interrupted after the marks advance |
| 2 | TxtReaderActivity (DisposableEffect) | **High** | `LifecycleEventObserver` installed only after `TxtUiState.Loaded`; if the async load finishes after `ON_RESUME`, the observer would miss the already-past resume and never call `start()` for the initial open | FIXED — relies on `LifecycleRegistry`'s documented event-replay: `addObserver` syncs a new observer up to the current state, dispatching `ON_RESUME` if already `RESUMED`. Proven on-device by the new `lifecycleHook_replayStartsAndKeyedStopBanks_onDevice` test (registers the observer at `RESUMED`, asserts `start()` fired and banked) |
| 3 | TxtReaderActivity (stop) | Medium | process-singleton tracker `stop()` had no session/book token — a stale Activity could stop another's session | FIXED — `stop(bookKey: String? = null)` no-ops unless `activeBook == bookKey`; reader passes its `bookKey` |
| 4 | TxtReaderActivity (ticker + periodic flush) | Medium | the two infinite `LaunchedEffect(Unit)` loops weren't lifecycle-gated — woke every 1s/60s while the composition existed even when backgrounded | FIXED — both loops now run inside `lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED)`; inner loops cancel while backgrounded |
| 5 | VReaderApp.kt:35 | Medium | repo and tracker each got a separate `SystemDateClock()` (each captures `ZoneId.systemDefault()` at construction) → dashboard "today" could drift from tracker bucket dates | FIXED — one `dateClock` singleton in `AppContainer`, injected into both |
| 6 | ReadingStatsConnectedTest.kt:50 | Medium | the connected test proved tracker→repo→Room aggregation but not the Activity lifecycle hook / registration replay / keyed-stop scoping | FIXED — added `lifecycleHook_replayStartsAndKeyedStopBanks_onDevice` driving a real `LifecycleRegistry` through the bracket (register-at-RESUMED replay → start; keyed stop banks; stale keyed stop for a different book no-ops) |

## Round 2 — verify

All six resolved; zero remaining Critical/High/Medium.

> Residual (accepted, not a finding): the lifecycle connected test uses a real
> `LifecycleRegistry`, not a full Compose `TxtReaderActivity` launch — it proves
> the AndroidX replay contract + the reader's observer logic, not full UI
> composition timing. Disproportionate to launch the whole Activity for the
> remaining risk; the accounting state machine is exhaustively unit-tested.

## Tests
- `:app:connectedDebugAndroidTest` (ReadingStatsConnectedTest, 2 tests) — **SUCCEEDED** on `vreader-test(AVD)` API 35.
- `:app:testDebugUnitTest --tests 'com.vreader.app.stats.*'` — **SUCCEEDED**.

## Verdict
**ship-as-is.** Critical lifecycle-cancellation bug fixed (the load-bearing
must-finish write now runs on the process scope under `NonCancellable`); all
medium hygiene findings resolved; on-device acceptance + lifecycle harness green.
