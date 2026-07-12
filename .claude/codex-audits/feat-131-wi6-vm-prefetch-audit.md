---
branch: feat/131-wi6-vm-prefetch
threadId: 019f552f-5ed5-78f0-9b62-38fe542f73ab
rounds: 3
final_verdict: ship-as-is
---

# Gate-4 Audit — feature #131 WI-6 (Android BilingualViewModel position-driven prefetch)

Tool: `scripts/run-codex.sh -e high` (rule 53). Author/auditor separation held
(Codex `gpt-5.6-sol`, independent of the implementing session).

## Scope

WI-6: the `BilingualViewModel` position-driven prefetch trigger + per-unit
single-flight + generation/cancellation guards. Changed files:

- `android/app/src/main/kotlin/com/vreader/app/bilingual/BilingualViewModel.kt`
  (extended: delegates the position path to a controller; `generation` bump on
  disable/language now also invalidates the controller)
- `android/app/src/main/kotlin/com/vreader/app/bilingual/BilingualPrefetching.kt`
  (NEW: `interface BilingualPrefetching` seam + `ChapterTranslationPrefetcherAdapter`
  + `NoTranslationUnitsProvider` + `BilingualPrefetchController` — the position/
  single-flight/generation/cancellation orchestration)
- `android/app/src/test/kotlin/com/vreader/app/bilingual/BilingualViewModelPrefetchTest.kt` (NEW — behavioral suite)
- `android/app/src/test/kotlin/com/vreader/app/bilingual/BilingualViewModelPrefetchConcurrencyTest.kt` (NEW — concurrency-decisive suite)
- `android/app/src/test/kotlin/com/vreader/app/bilingual/BilingualPrefetchControllerTest.kt` (NEW — launch-lifecycle regression suite)
- `android/app/src/test/kotlin/com/vreader/app/bilingual/BilingualPrefetchFakes.kt` (NEW — shared test fakes)

## Round 1 (thread 019f552f)

- **High** — a joined lookahead-turned-current would discard its own result via a stale `positionSeq`.
- **High** — a stale success left the unit permanently in `inFlightUnits` (stuck spinner).
- **Medium** — cleanup not registry-entry-specific (a replacement could be clobbered by the old job's `finally`).
- **Medium** — main-thread confinement asserted but not documented on the entry points.
- **Medium** — tests missed the decisive concurrency cases.
- **Low** — test file 431 lines.

Fixes: success now commits under a GENERATION-only guard (a translation is a durable
cache entry); `positionSeq` gates only the FAILURE path; every terminal path clears
`inFlightUnits`; cleanup made entry-specific via job identity (`===`); main-thread
contract documented; missing tests added; test file split into two suites + shared fakes.

## Round 2 (thread 019f5536)

- **High** — `lateinit self` before-init race under `Dispatchers.Main.immediate` on a non-suspending seam return.
- **High** — a joined lookahead-turned-current FAILURE was still discarded as stale (the current unit stuck, un-retryable).
- **Medium** — an unexpected (non-typed) throwable left the unit in `inFlightUnits`.
- **Low** — stale header comments; the `invalidateThenReplace` test was a no-op ordering.

Fixes: launch `CoroutineStart.LAZY` → register → `start()` (race-free);
`isFailureStale(unit, launchGen, seq)` returns stale only when generation changed
OR (superseded AND `unit != currentUnit`) so a still-current unit's failure always
surfaces; a `catch (Throwable)` maps unexpected errors via `ChapterTranslationError.from`;
comments updated; tests added (`lookaheadBecomesCurrent_thenFails_surfacesErrorUnit`,
`unexpectedThrowable_surfacesErrorUnit_noStuckSpinner`) + the replace test reframed.

## Round 3 (thread 019f553d) + confirmation (thread 019f5541)

- All **High** cleared (LAZY ordering, `isFailureStale`, retry null-seq semantics confirmed correct).
- **Medium** — a dispatch after `viewModelScope` is cancelled leaves a never-started lazy job in the registry + `inFlightUnits` (`start()` returns false → catch/finally never fire).
- **Low** — no eager-dispatcher regression test; test file marginally >300.

Fixes: `if (!self.start()) { entry-specific-remove; clear inFlight }`; added
`BilingualPrefetchControllerTest` (`eagerDispatcher_nonSuspendingResult_noLateinitCrash`
+ `dispatchAfterScopeCancelled_noLeak`); concurrency test trimmed to 302 lines.

Confirmation pass verdict: **clean** — no Critical/High/Medium remaining.

## Final verdict: ship-as-is

Zero open Critical/High/Medium. The one remaining note is cosmetic (the
concurrency test file sits at ~302 lines, marginally over the ~300 soft guideline
for a TEST file; both production files are 271 and 265). Test gate (JVM, no
emulator): `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — 34 tests across
`BilingualViewModelTest` (12), `BilingualViewModelPrefetchTest` (10),
`BilingualViewModelPrefetchConcurrencyTest` (10), `BilingualPrefetchControllerTest` (2).
