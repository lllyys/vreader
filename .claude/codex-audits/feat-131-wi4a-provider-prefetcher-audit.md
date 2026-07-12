---
branch: feat/131-wi4a-provider-prefetcher
threadId: 019f54ee-a53f-7340-bc77-e396f1c41a5d
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 audit — feature #131 WI-4a (ChapterTextProvider + ChapterTranslationPrefetcher + BilingualAiReadiness)

Independent Codex audit (rule 53, `scripts/run-codex.sh`, read-only sandbox) of the
four new foundational Kotlin files for the Android bilingual pipeline + their three
test classes.

## Scope

Production:
- `android/app/src/main/kotlin/com/vreader/app/bilingual/ChapterTextProvider.kt`
- `android/app/src/main/kotlin/com/vreader/app/bilingual/TxtChapterTextProvider.kt`
- `android/app/src/main/kotlin/com/vreader/app/bilingual/ChapterTranslationPrefetcher.kt`
- `android/app/src/main/kotlin/com/vreader/app/bilingual/BilingualAiReadiness.kt`

Tests:
- `android/app/src/test/kotlin/com/vreader/app/bilingual/TxtChapterTextProviderTest.kt`
- `android/app/src/test/kotlin/com/vreader/app/bilingual/ChapterTranslationPrefetcherTest.kt`
- `android/app/src/test/kotlin/com/vreader/app/bilingual/BilingualAiReadinessTest.kt`

## Round 1 (session 019f54ec-2731-7bd1-ab5c-e0cf758f318d) — verdict: follow-up-recommended

Confirmed correct: H1 span sourcing (paragraphRanges half-open spans, never
`offsetForChunk(last+1)` clamp-collapse), EOF/past-EOF/leading-blank clamping, the
largest-start-≤-offset binary search, contiguous window slicing, snapshot-consistent
profile+key, the M3 blank/whitespace model → `kind.defaultModel` fallback (asserted on
the emitted `AiRequest`), the #306 no-provider cache-hit + miss→ProviderFailed contract,
`cachedDirect` zero-provider restore (sentinel unreachable), and cancellation rethrow in
the prefetcher's decrypt/factory catches. No file >300 lines; no dead code.

Findings:

- **Medium** — `prefetch`/`prefetchDirect` resolved+built the provider (snapshot +
  cipher decrypt + client factory) BEFORE consulting the cache when an active provider
  existed, so a valid cache hit could fail on a broken cipher and incurred needless
  provider work — contradicting the cache-first contract.
  **Fix applied:** both methods now do the cache-only lookup FIRST; `resolveProvider()`
  runs only on a cache miss; `translate(..., bypassCacheRead = true)` avoids a redundant
  second read while still cache-writing on success. Added two regression tests
  (`prefetch_cacheHitWithActiveProvider_neverBuildsClient`,
  `prefetchDirect_cacheHitWithActiveProvider_neverBuildsClient`) that seed a hit, break
  the cipher, and assert the factory is never called and no throw occurs.

- **Low** — `TxtChapterTextProvider.windowCount` ceiling division `(size + windowSize - 1)`
  could overflow `Int` for a huge injected `windowSize`, yielding 0 units for non-empty
  content.
  **Fix applied:** `((segmentSpans.size - 1) / windowSize) + 1`, with an
  `Int.MAX_VALUE` regression test (`hugeWindowSize_doesNotOverflowToZeroUnits`).

- **Low** — `BilingualAiReadiness.resolve` used a bare `runCatching` that would swallow
  a `CancellationException` as "not ready".
  **Fix applied:** explicit `try/catch` rethrowing `CancellationException`, other
  cipher/keystore failures → `false`.

## Round 2 (session 019f54ee-a53f-7340-bc77-e396f1c41a5d) — verdict: ship-as-is

No findings (Critical/High/Medium/Low all None). Confirmed all three round-1 findings
are resolved and that the cache-first restructure introduced no new issue:
`bypassCacheRead=true` still cache-writes fully-successful results; the #306 no-provider
hit + miss→ProviderFailed contract holds; exactly one cache read precedes provider
resolution (no double-read cost).

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `TxtChapterTextProviderTest` (19),
`ChapterTranslationPrefetcherTest` (15), `BilingualAiReadinessTest` (6) = 40 tests,
0 failures, 0 skips.
