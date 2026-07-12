---
branch: feat/133-wi13-test-hardening
threadId: 019f53f3-83c2-7e53-b8f5-2afe10f0e8a8
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 Codex audit — feature #133 WI-13 (test-hardening)

TEST-ONLY change: harden async synchronization in the two connected in-book-search
instrumentation suites. NO product (`main/`) code changed.

- `android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtFindInBookTest.kt`
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubFindInBookTest.kt`

## Defect fixed

`InBookSearchViewModel` runs `_query -> debounce(250ms) -> flatMapLatest -> search`.
The tests inject `Dispatchers.Main.immediate` (no virtual `TestScope`), so
`compose.waitForIdle()` does NOT await the 250 ms wall-clock `debounce()` nor the
index-state gate recompute. The suites did `performTextInput -> waitForIdle ->
immediate assert`, firing the assert before results/state landed → node-not-found.

Fix: each `waitForIdle`-then-immediate-assert replaced with a bounded
`compose.waitUntil(5_000){ ... }` poll on the AWAITED node (result row /
no-results body / gate-driven icon removal), mirroring the EPUB `awaitFirstHit`
polling helper. `unsupportedGate_hidesSearchIcon` now types a query (the gate is
consulted only for a non-empty query) so it actually recomputes to Unsupported.
The EPUB `dismissSearch_disposesCursors_vmSurvives` false `Idle` assertion (the VM
keeps the query on `onDismiss` and does NOT reset content to Idle — confirmed by
the JVM unit test `dismiss_closesEpubCursors`, which asserts only the cursor
dispose) was replaced with the real vmSurvives contract: build-count stability
(not rebuilt) + a live queryable state Flow after the dispose path ran without
crashing; cursor disposal remains unit-verified.

## Round 1 — thread 019f53f3-83c2-7e53-b8f5-2afe10f0e8a8 — FOLLOW-UP-RECOMMENDED

Three comment/message-accuracy findings (no correctness/regression-detection issue):

1. EpubFindInBookTest.kt class doc (~lines 35-41) still said dismiss "returns to
   Idle" — stale vs the corrected test + the VM contract.
2. Assert message "SAME instance" overstates build-count equality (proves "not
   rebuilt", not literal object identity).
3. Assert message overclaimed "no leak"/cursor-dispose — the connected assertion
   proves only no-crash + still-queryable; dispose is covered by the JVM test.

Everything else checked out: TXT polls await concrete non-trivial signals; all
waits bounded at 5 s; tests still fail on a real regression; typing a query in
`unsupportedGate` is correct; no `main/` code changed; `assertCountEquals`
correctly removed; no unused import / dead helper.

## Round 2 — thread 019f53f6-a492-7532-a3f0-faf4b985e2a1 — SHIP-AS-IS

All three round-1 accuracy findings resolved. Comments/messages now correctly
limit the connected assertion to build-count stability, VM survival, and queryable
state, attributing cursor disposal to unit coverage. Diff from origin/main touches
only the two `androidTest` files; polls remain bounded (5-10 s) and await the
correct observable conditions; real regressions still fail; no new issue from the
wording-only edits.

**Final verdict: SHIP-AS-IS** — the test-only changes are accurate, bounded, and
retain meaningful regression detection.

## Test evidence

- CONNECTED gate (emulator-5554), `scripts/run-android-tests.sh`:
  `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — 14/0 (TxtFindInBookTest 6/0,
  EpubFindInBookTest 6/0, SearchHiddenOnPdfAzw3Test 2/0).
- JVM unit suite (`:app:testDebugUnitTest`): `RUN-ANDROID-TESTS RESULT: SUCCEEDED`.
