---
branch: feat/131-wiaip-ai-providers-sheet
threadId: run-codex.sh (rule 53) — scripts/run-codex.sh -e high, 2 rounds
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 audit — feature #131 WI-AIP (in-bilingual Variant-A AI Providers sheet + save-result seam)

Independent Codex audit (`scripts/run-codex.sh -e high`, rule 53) of the WI-AIP changed files:

- `android/app/src/main/kotlin/com/vreader/app/bilingual/ReaderAiProvidersSheet.kt`
- `android/app/src/main/kotlin/com/vreader/app/bilingual/ReaderAiProvidersList.kt`
- `android/app/src/main/kotlin/com/vreader/app/ai/AiSettingsViewModel.kt`
- `android/app/src/androidTest/kotlin/com/vreader/app/bilingual/ReaderAiProvidersSheetUiTest.kt`
- `android/app/src/test/kotlin/com/vreader/app/ai/AiSettingsViewModelTest.kt`

Full transcripts: `.reports/wiaip-audit.txt` (round 1), `.reports/wiaip-audit-r2.txt` (round 2).

## Round 1 — 2 High + 2 Medium (all addressed)

- **High-1** — `ReaderAiProvidersSheet` popped (`onDone`) immediately after firing `vm.setActive(savedId)` as a fire-and-forget `viewModelScope` job, so the pop could race ahead of the DataStore activation commit (violating the brief's "activate then pop, no race").
  **Fix:** added `suspend fun setActiveAndAwait(id)` on the VM; the `saveResult` collector `setActiveAndAwait(savedId)` then `onDone()`, so the pop is strictly after activation commits.
- **High-2** — `save()` had no single-flight guard: a double-tap minted two UUIDs, persisted two providers, and emitted two `saveResult` → double-pop.
  **Fix:** synchronous `saving` guard set before the launch, cleared in a `finally` — a double-tap now persists one profile + emits one result.
- **Medium-1** — the connected "no race" test started from an empty store, so the store's first-provider-active default masked a missing `setActive`.
  **Fix:** the test now seeds an existing active provider and asserts the newly-saved id is active AT the `onDone` callback time (proving activate-before-pop).
- **Medium-2** — the list did not reproduce the design's `NavSheet` frame (scrim + bottom-aligned top-rounded sheet + grabber), context-strip border, or empty-state gradient/shadow.
  **Fix:** added the NavSheet frame chrome, the context-strip accent border, and the empty-state gradient sparkle disc + accent shadow.

## Round 2 — round-1 all RESOLVED; 1 new Medium + 1 Low (both addressed)

- **Medium (new)** — `setActiveAndAwait` used `launch { store.setActive(id) }.join()`, which waits but does NOT propagate the launched coroutine's exception: an activation failure would return normally (pop without activation) and could surface as an uncaught `viewModelScope` failure.
  **Fix:** call `store.setActive(id)` DIRECTLY in the suspend function so a failure propagates to the collector and the pop is skipped.
- **Low** — the top-rounded sheet lacked the design's upward sheet shadow.
  **Fix:** added a `shadow` to the sheet frame Column.

## Confirmed-clean aspects (both rounds)

- `AiProviderEditSheet` is reused VERBATIM (not forked); provider rows use `row.active` + tap-to-SELECT (not tap-to-edit) — does NOT reuse `AiProviderListScreen`'s NavScreen/AiEmptyState/tap-edit (rule 51).
- `saveResult` is emitted only after `store.upsert()` returns; `save()` stays a Unit API so existing #118 callers are unaffected; `SharedFlow(replay=0, extraBufferCapacity=1)` prevents late-subscriber replay/double-pop.
- `LaunchedEffect(Unit)` single collector + `rememberUpdatedState(onDone)` is the correct Compose/UDF pattern; editor/list `BackHandler` semantics match the nav model.
- All production files < 300 lines.

## Result

- **Critical: 0, High: 0, Medium: 0, Low: 0 open.** All findings fixed.
- Tests after fixes: JVM `AiSettingsViewModelTest` 8/8 green (5 new: save-result seam ×3, rapid-double-save guard, setActiveAndAwait ordering); connected `ReaderAiProvidersSheetUiTest` 6/6 green.

**Final verdict: ship-as-is.**
