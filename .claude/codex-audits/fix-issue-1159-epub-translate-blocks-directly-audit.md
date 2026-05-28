---
branch: fix/issue-1159-epub-translate-blocks-directly
threadId: 019e6434-1b5a-7d12-a3b2-523d8e0f5e94
rounds: 1
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex Audit — Bug #268 sub-part (1): EPUB translate-block-text-directly

Sub-part (1) of Bug #268 / GH #1159: when the EPUB bilingual plain-text prefetch's
segment count diverges from the DOM leaf-enumerate's block count (nested
`<pre>`-blank-lines / mixed-content `<blockquote>`), translate the enumerate's OWN
block `text[]` directly so blocks↔segments are 1:1 by construction — eliminating
the residual whole-chapter source-only fallback. (Sub-part (2), the Foliate-host
leaf-fix, shipped in v3.39.32 / PR #1183.)

## Change

- `ChapterTranslationService.translatePreSegmented(segments:...)` — chunk + translate
  + recombine, NO disk cache, returns `count == input`.
- `ChapterPrefetching.translatedSegmentsDirect(...)` — protocol method + a default
  extension that throws `.providerFailed` (non-overriding conformers stay source-only).
- `ChapterTranslationPrefetcher.translatedSegmentsDirect` — snapshot active profile +
  resolve config + `translatePreSegmented`.
- `BilingualReadingViewModel.translateBlocksDirectly(_:for:)` — guards
  isEnabled/prefetcher/non-empty; skips if a matching-count translation exists;
  stores + `postDidChange`; swallows errors → source-only.
- `EPUBReaderContainerView+Bilingual.injectBilingualIfCached` — divergence detection
  (`segments.count != currentBlocks.count`) routes to `translateBlocksDirectly`.

## Round 1 — No findings. Ship as-is.

Codex confirmed:
- **1:1 correctness**: `translatePreSegmented` preallocates to `segments.count` and
  fills by original index; `translateChunk` returns a count-matched decode OR a
  per-segment fallback (raw-text trim as last resort) → `result.count == input.count`.
- **De-risk holds**: the common matched-count inject path is unchanged; the mismatch
  branch can only produce a matching-count array or no change — never a wrong pairing.
- **No infinite loop**: store-then-`postDidChange` re-injects; the next inject sees
  equal counts; the "skip if matching-count exists" guard prevents re-translate.
- **Concurrency sound**: VM + orchestrator `@MainActor`; `ProviderProfileStore` +
  `ChapterTranslationService` actors; the inject Task awaits the provider hop then
  calls back into the main actor cleanly.
- **Cache-skip** is a contained perf tradeoff (re-translate on divergent-chapter
  reopen), not a correctness risk; avoids poisoning the plain-text cache key.
- **Default protocol throw** is safely swallowed → source-only.
- Edge cases (segments nil, coincidental equal count across chapters keyed by
  `TranslationUnitID`, provider switch mid-fallback) all sound.

**Test-gap noted + closed**: Codex flagged that the tests didn't cover
`translatePreSegmented` on malformed-decode → per-segment fallback. Added
`translatePreSegmented_malformedChunkDecode_fallsBackPerSegment_stays1to1`.

## Verdict

**ship-as-is** — the divergence-fallback is correct, additive, low-risk, and the
1:1-by-construction guarantee eliminates the residual EPUB source-only fallback that
leaf-enumerate alone could not.
