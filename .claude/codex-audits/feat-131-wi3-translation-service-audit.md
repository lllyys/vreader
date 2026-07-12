---
branch: feat/131-wi3-translation-service
threadId: 019f54de-00b1-7102-ba29-c9d445d734ab
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 audit — feature #131 WI-3 (ChapterTranslationService)

Auditor: Codex (`gpt-5.6-sol`, read-only sandbox) via `scripts/run-codex.sh`.
Session `019f54de-00b1-7102-ba29-c9d445d734ab`. Full transcript: `.reports/audit-r1.txt`.

## Files audited

- `android/app/src/main/kotlin/com/vreader/app/bilingual/ChapterTranslationService.kt` (code under audit)
- `android/app/src/test/kotlin/com/vreader/app/bilingual/ChapterTranslationServiceTest.kt`
- `android/app/src/test/kotlin/com/vreader/app/bilingual/FakeAiClient.kt`

Read-only consumed seams (WI-1/WI-2/#118): `ChapterTranslationStore.kt`, `ChapterSegmenter.kt`,
`TranslationChunker.kt`, `TranslationChunkContract.kt`, `ChapterTranslationError.kt`,
`TranslationUnitId.kt`, `TranslationGranularity.kt`, `ai/AiClient.kt`, `ai/AiTypes.kt`,
`ai/AiProviderStore.kt`, `ai/AiProviderKind.kt`, `ai/AiProviderFactory.kt`.

## Round 1 — findings and resolution

### Medium — cache-write cancellation swallowed by `runCatching` (FIXED)

`writeCache()` (and the stale-row delete in `translate()`) wrapped the suspending
`store.upsert()` / `store.delete()` in a bare `runCatching { … }`, which catches
`CancellationException`. A cancellation observed while the Room upsert/delete suspends —
after the pre-write `ensureActive()` — would be swallowed, letting `translate()` /
`translatePreSegmented()` return normally from a cancelled coroutine.

Resolution: both sites replaced `runCatching` with cancellation-transparent handling —
`catch (e: CancellationException) { throw e }` first, then `catch (_: Throwable) {}` for
the genuinely non-fatal store failure. Two regression tests added:
`translate_cancellationInsideUpsert_propagates_notSwallowed` (a DAO whose `upsert` throws
`CancellationException` → propagates, no row) and
`translate_upsertFailure_isNonFatal_translationStillReturned` (a `RuntimeException` from
`upsert` → the translation is still returned, no row cached).

### Confirmed correct by the auditor (no change)

- Native `CancellationException` AND typed `ChapterTranslationException(Cancelled)` from a
  chunk are re-raised as `Cancelled` BEFORE the generic per-chunk degrade; `send()`
  re-throws native `CancellationException` (cooperative) rather than mapping it to
  `ProviderFailed`.
- A partially-degraded result is never cached; an all-chunks failure surfaces the error
  (not an all-source-only result).
- Both public paths call `ensureActive()` immediately before `writeCache()`.
- Chunk-index recombination places every segment exactly once in source order; the
  oversized-single-segment sub-split rejoins into the one slot.
- `translatePreSegmented` full success caches under the enumerate's count
  (`segments.size`); a partial degrade caches nothing.
- `AiError` mapping matches the taxonomy (Offline→Offline, Timeout→TimedOut,
  cancellation→Cancelled, everything else→ProviderFailed) via `ChapterTranslationError.from`.
- No defect in `FakeAiClient`; empty input, decode fallback, multi-chunk ordering, and the
  zero-provider cache restore are covered.

## Verdict

The auditor's round-1 verdict was **follow-up-recommended**, with the single Medium being
the cache-write cancellation swallow. That finding is now **fixed in-lane** with regression
tests, so the shipped state is **ship-as-is** — zero open Critical/High/Medium. Test gate:
`RUN-ANDROID-TESTS RESULT: SUCCEEDED` (28/0, `ChapterTranslationServiceTest`).
