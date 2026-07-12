---
branch: feat/133-wi10-txt-host
threadId: 019f53aa-db30-7950-aa2f-39de63b7354d
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 audit — feature #133 WI-10 (TXT/MD in-book-search host wiring)

Independent Codex audit (`scripts/run-codex.sh`, rule 53) of the WI-10 changed files:

- `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt` — the host: the
  per-session `InBookSearchViewModel` + Search-slot + `InBookSearchSheet` wiring, and the extended
  `TxtReaderChrome` composable (new `onOpenSearch` / `searchSheet` params).
- `android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt` — the additive
  `AppContainer.inBookSearchViewModel(...)` factory (TXT/MD track; EPUB-seam null-safe).
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtFindInBookTest.kt` — the connected test.

## Round 1 (session `019f53a0-45b8-7d60-aa7e-5e116c874976`) — 1 Medium, 2 Low

- **Medium — jump reports Succeeded before the async scroll completes.** `onJump` launched
  `scrollToItem(...)` on `ttsScope` and returned `JumpResult.Succeeded` immediately, so a scroll
  cancelled during teardown / that threw could still dismiss the sheet.
  **Resolved:** the WI-9 sheet's `onJump: (InBookHit) -> JumpResult` is NON-suspend (the result must
  return synchronously), so — exactly like the two sibling jump seams in the same file
  (`onJumpBookmark`, `onJumpToAnnotation`) — the range is validated UP FRONT
  (`txtBookmarkScrollTarget` → null → `Failed`, sheet stays open) and a valid target returns
  `Succeeded` optimistically. The async `scrollToItem` is now wrapped in `runCatching` so a
  teardown-cancelled scroll can't crash; `commitSearch()` runs only on a valid result-open (the VM's
  documented contract). Making the callback suspend would require editing the WI-9 sheet (out of
  write-set / forbidden), so the optimistic-Succeeded-after-validation is the correct, consistent
  host contract.
- **Low — the connected test bypassed the production jump seam.** The harness reimplemented the
  resolution. **Resolved:** the test now drives the PRODUCTION helper — `txtBookmarkScrollTarget`
  over a real `TxtDocument` + `chunkForOffset` on a real `LazyListState` — and adds an
  out-of-range → `Failed` (sheet stays open) case.
- **Low — lifecycle / unsupported untested + leaked test scope.** **Resolved:** the harness now uses
  `rememberCoroutineScope()` + `DisposableEffect(vm) { onDispose { vm.onCleared() } }` (no leaked
  scope) and adds an `Unsupported`-gate-hides-Search-icon case.

## Round 2 (session `019f53aa-db30-7950-aa2f-39de63b7354d`) — CLEAN at blocking severities

**No Critical, High, or Medium findings.** The round-1 Medium is confirmed acceptably resolved (the
optimistic-Succeeded matches the non-suspend sheet contract + the sibling seams; `commitSearch` on
valid result-open; async scroll `runCatching`-guarded). The `VReaderApp.kt` edit is confirmed
additive + isolated (one import + one factory method — no unrelated container restructuring, so
WI-11's EPUB-host edit rebases cleanly). Two residual **Low** items are test-strength debt only, NOT
WI-10 blockers:

- the success tests assert the synchronously-resolved target but do not independently prove
  `scrollToItem` landed on the chunk (that lands in WI-12's emulator acceptance);
- the harness cleans up via `DisposableEffect` but does not assert `closeCursorsCalls` / VM identity
  across recomposition.

Both are covered end-to-end at WI-12 (the connected `TxtFindInBookTest` + the real-book slice run on
the emulator; this lane's gate is androidTest-compiles + JVM-green, per the dispatch precedent).

## Verdict

`ship-as-is` — zero open Critical/High/Medium after round 2; the two Low items are accepted
test-strength debt discharged by the WI-12 acceptance pass. Test gate:
`RUN-ANDROID-TESTS RESULT: SUCCEEDED` (`:app:compileDebugAndroidTestKotlin :app:testDebugUnitTest`).
