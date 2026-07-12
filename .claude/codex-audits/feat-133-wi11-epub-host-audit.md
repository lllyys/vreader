---
branch: feat/133-wi11-epub-host
threadId: 019f53be-c364-7e12-bce5-00462c747918
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 Codex audit — feature #133 WI-11 (EPUB in-book search host wiring)

Independent Codex audit (rule 53, `scripts/run-codex.sh`) of the WI-11 diff:

- `android/app/src/main/kotlin/com/vreader/app/reader/ReaderActivity.kt` — EPUB host wiring
- `android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt` — `EpubTopBand.onSearch` slot
- `android/app/src/main/kotlin/com/vreader/app/VReaderApp.kt` — `epubInBookSearchViewModel` factory
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/EpubFindInBookTest.kt` — connected test

## Round 1

**Verdict: No production-code defects found. Critical: 0, High: 0, Medium: 0, Low: 3 (all in the test file).**

Codex-verified clean (production):
- The EPUB factory uses `EpubInBookSearchEngine(publication)` over the live `Publication` — no duplicate publication adapter introduced (deliberately reuses WI-5's `RealPublicationSearchSource` behind the production constructor).
- EPUB bypasses `IndexStateGate` before subscribing to `flowOf(null)` / invoking `hasOccurrence`; all FTS deps are fail-fast guards.
- Dismiss calls `VM.onDismiss()`; destruction calls `VM.onCleared()` BEFORE `publication.close()` (correct order — the iterator is a view over the publication).
- Null / blank / malformed / semantically-invalid locator JSON all fail safely; `navigator.go` exceptions and a `false` return both map to `JumpResult.Failed` (no crash, no invented error surface).
- Exactly one VM is constructed in the successful async publication-open path; rotation starts fresh via `super.onCreate(null)`.
- The search layer returns before rendering while closed — fragment touch-through preserved.
- `EpubTopBand.onSearch` is additive, forwarded to `ReaderTopChrome`; `hidesSearchEntry` removes the icon.
- The existing TXT/MD factory is unchanged; VM state collection uses `lifecycleScope` (no state-read race).
- No invented UI or error surface added.

### Low findings + resolution

1. **`return@repeat` did not break the polling loops** (test lines 84/142/177/196) — `return@repeat` only exits the current `repeat` iteration, so every successful poll waited the full timeout. **FIXED**: rewrote the polling helpers + inline loops as `for (i in 0 until N) { …; if (…) break; … }`.
2. **Cursor-disposal count not directly asserted** — the connected test asserts the VM survives dismiss + returns to Idle, not a `closeAllEpubCursors` invocation count. **ACCEPTED with rationale (fix in-comment)**: this connected test runs against the REAL Readium publication (its purpose); a spy repository would replace the live `SearchService` with a fake and defeat the slice. The `closeAllEpubCursors` invocation on dismiss/onCleared is unit-verified at the WI-8 VM layer (`InBookSearchViewModelTest`) + the WI-6 repository layer; here it is exercised end-to-end (dismiss → Idle, re-open works, no leak/crash) and the onDestroy path runs through `ActivityScenario.use{}`'s close. The test-class KDoc now states this explicitly.
3. **One-VM-per-session not directly asserted** — the test only proved a VM state exists. **FIXED**: added an `inBookSearchVmBuildCountForTest()` seam (increments on each construction) + an assertion that exactly one VM is built per reader open.

Re-ran the test gate after the audit fixes: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` (androidTest set compiles green + JVM unit suite green).

## Notes

- Per the M-SHAKEDOWN lane finding, custom agents get no Skill tool; the audit ran through `scripts/run-codex.sh` (rule 53), the PRIMARY rung.
- The connected `EpubFindInBookTest` + the real-CJK-EPUB acceptance slice run on the emulator at WI-12 (the #132/#134/#135 precedent — this lane's gate is compile-green + JVM-green).
