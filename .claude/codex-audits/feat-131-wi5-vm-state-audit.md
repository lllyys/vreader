---
branch: feat/131-wi5-vm-state
threadId: 019f54fc-847e-7fd3-a84b-76f5bc415f4b
rounds: 3
final_verdict: ship-as-is
---

# Gate-4 Codex audit — feature #131 WI-5 (PerBookBilingualStore + BilingualViewModel state core)

Model: gpt-5.6-sol (read-only sandbox), via `scripts/run-codex.sh` (rule 53).
Author/auditor separation preserved (rule 48): implemented by Claude, audited by Codex.

Files audited (WI-5 write-set only):
- `android/app/src/main/kotlin/com/vreader/app/bilingual/PerBookBilingualStore.kt`
- `android/app/src/main/kotlin/com/vreader/app/bilingual/BilingualUiState.kt`
- `android/app/src/main/kotlin/com/vreader/app/bilingual/BilingualViewModel.kt`
- `android/app/src/test/kotlin/com/vreader/app/bilingual/PerBookBilingualStoreTest.kt`
- `android/app/src/test/kotlin/com/vreader/app/bilingual/BilingualViewModelTest.kt`

## Round 1 (session 019f54fc-847e-7fd3-a84b-76f5bc415f4b) — verdict: follow-up-recommended

Findings:
- **Medium** — asynchronous hydration could clobber a racing setter: a setter firing
  before `store.read()` completed would be overwritten by hydration; the first-enable
  transition was computed from the unhydrated default.
- **Medium** — separate `persistCurrent()` launches could reach `DataStore.edit` out of
  order on a multi-worker dispatcher, so an older config could win the last write.
- **Low** — `generation++` inside the disable `StateFlow.update` lambda could run more than
  once under a CAS retry (the language path already incremented outside).
- **Low** — `reEnablePersistedEnabled_doesNotRaiseSheet` only tested hydration, not an
  explicit post-hydration re-enable; add a raw-on-disk `sentence` decode test.

Confirmed correct in r1: first-enable-only-once sheet (`wasEnabled` captured before the
update), aiConfigured via `BilingualAiReadiness.resolve` (cipher failure → false), no
`style` field anywhere, granularity pinned `paragraph` on write AND read, prefetcher held
but never invoked, `viewModelScope` + injected dispatcher + no `GlobalScope`, all files
<300 lines.

Fix applied: introduced a `mutationMutex` + a one-shot `hydration` job that every setter
awaits (`hydration.join()`) before mutating + persisting under the lock; moved `generation++`
out of the update lambda; added the two test-hardening cases + a hydration-race test + a
rapid-setter persist-order test.

## Round 2 (session 019f54ff-697f-7900-9ebd-ed2cc09e07ac) — verdict: block-recommended

Confirmed the r1 fixes correct (hydration clobber fixed, deadlock-free, `generation++`
exactly once, all behavior preserved). Raised ONE new:
- **Medium** — setter API-call order still not guaranteed: `viewModelScope.launch` start
  order is not contractual and a Mutex only orders contenders already at the lock, so a
  later setter's coroutine could reach `withLock` before an earlier one.

Fix applied: replaced the launch+mutex model with a synchronous `Channel(UNLIMITED)` —
config-mutating setters `trySend` a sealed `Command` at the call site (enqueue order ==
API-call order) and a SINGLE consumer coroutine drains it serially after hydrating first.

## Round 3 (session 019f5501-7b8c-7290-8528-a7921b2e9d77) — verdict: ship-as-is

**Critical 0 · High 0 · Medium 0 · Low 1 (optional).** Confirmed:
`API-call order == enqueue order == state-mutation order == store.write order`; hydration
runs before command drain (earlier commands buffer, none dropped); `generation++` exactly
once per drained disable/language command outside any retriable lambda; no deadlock, the
consumer's collect is cancelled with `viewModelScope`; no regression to first-enable sheet /
aiConfigured / no-style / granularity-pinned-paragraph / held-uninvoked prefetcher.

- **Low (optional)** — the unlimited channel is not closed, so a post-`onCleared()` setter
  could buffer a never-consumed command on an abnormally-retained ViewModel.
  Fix applied: `onCleared()` now `commands.close()` (fail-fast on a stray post-clear send).

Post-fix targeted re-test: `RUN-ANDROID-TESTS RESULT: SUCCEEDED`
(PerBookBilingualStoreTest 7/0, BilingualViewModelTest 12/0).

## Verdict

**ship-as-is** — zero open Critical/High/Medium after 3 rounds; the sole Low was applied.
