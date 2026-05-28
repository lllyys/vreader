---
branch: feat/feature-71-wi-7-bilingual-section-scoping
threadId: 019e6939-6b09-7232-b5e3-a5cbefc3c52e
rounds: 3
final_verdict: follow-up-recommended
date: 2026-05-27
---

# Codex Audit — Feature #71 WI-7 (bilingual section-scoping for continuous EPUB scroll)

Gate-4 implementation audit. Ports the FoliateBilingualOrchestrator per-`sectionIndex`
pattern to the EPUB bilingual path so continuous-scroll mode (one stitched document,
multiple `[data-vreader-spine-index="N"]` sections) injects translations **per
stitched section with no cross-section `bid` bleed** (GH #1200 / plan WI-7 / round-1 H5).

Surface: `EPUBBilingualJS` (`spineIndex:` param — section-scoped DOM walk, namespaced
bids `s{N}b{seq}`, `{sectionIndex, blocks}` envelope; nil-path byte-identical to main),
`EPUBBilingualPipeline` (`parseEnumeratePayload` dual bare-array/envelope),
`EPUBBilingualOrchestrator` (`blocksBySection` + per-section `updateBlocks`/`clearBlocks`/
`buildInjectJS`/`buildInjectJS(translationsBySection:)`), `BilingualReadingViewModel.prefetchUnitIfNeeded`,
`EPUBReaderContainerView+ContinuousBilingual.swift` (per-section enumerate/inject driven
from `.readerBilingualSectionMaterialized`, reinject-all on `.readerBilingualDidChange`,
`.readerBilingualSectionEvicted` → `clearBlocks`), live-evaluator routing via
`EPUBContinuousScrollConfig.evaluateBilingual`.

## Round 1 — 2 High + 2 Medium + 4 Low

| file:line | sev | issue | resolution |
|---|---|---|---|
| +Bilingual:190 | High | `injectBilingualIfCached` injected against the flattened multi-section `currentBlocks` → cross-section translation bleed once 2 sections cached | Fixed — per-section inject (`buildInjectJS(...forSection:)` / `translationsBySection:`) against `blocksBySection[spineIndex]` |
| +Bilingual:146 | High | prefetch/inject keyed to `makeCurrentLocator()`, but `sectionMaterialized` fires for off-screen sections | Fixed — `handleSectionBilingualBlocks` resolves the payload's spineIndex→href→unit + prefetches that section's unit |
| +Bilingual:333 | Medium | per-section enumerate funneled through single `pendingHighlightJS` slot (rapid overwrite) | Fixed — routed through the live `EPUBWebViewEvaluatorHandle` (`evaluateBilingual`) |
| Coordinator:351 | Medium | eviction didn't clear `blocksBySection` (stale buckets) | Fixed — `onSectionEvicted` → `.readerBilingualSectionEvicted` → `clearBlocks(forSection:)` |
| (4 Low) | Low | nil-path byte-identity, stale comment, 2 file-size | nil-path restored byte-identical; comment fixed; file split (+ContinuousBilingual extracted); JS size noted (byte-identity duplication) |

## Round 2 — 2 High + 3 Medium

| file:line | sev | issue | resolution |
|---|---|---|---|
| Container:785 | High | bootstrap `didFinish` ran global enumerate in continuous mode → clobbers section buckets | Fixed — gated global enumerate to paged mode only |
| +Bilingual:213,256,308 | High | enable/confirm/disable used `pendingHighlightJS` (continuous `updateUIView` returns before consuming it) → no-op enable / stuck disable | Fixed — continuous routes through the live evaluator (enumerate materialized sections / global clear) |
| +Bilingual:156 | Medium | empty scoped enumerate `[]` lost section identity → global clear of all buckets | Fixed — `{sectionIndex, blocks}` envelope; empty scoped → `clearBlocks(forSection:)` |
| +ContinuousBilingual:114 | Medium | dropped Bug #268 direct-translation fallback per-section | Fixed — per-section `translateBlocksDirectly` on count mismatch |
| Coordinator:371 | Medium | `onSectionEvicted` fired before re-checking `gen == generation` | Fixed — gen-guard after remove eval (RED-verified test) |

## Round 3 — 1 Medium (accepted)

| file:line | sev | issue | resolution |
|---|---|---|---|
| +ContinuousBilingual:131 | Medium | per-section direct-translation fallback has no in-flight guard → duplicate provider calls / localized request storm when multiple section completions re-trigger the same mismatched section. **Codex: "does not reintroduce cross-section bleed."** | **ACCEPTED** as a follow-up (see below). |

Round-3 verification confirmed clean for everything else: "Envelope vs bare-array parsing
is unambiguous and preserves paged behavior. Continuous bootstrap now avoids global
enumerate correctly. Enable/confirm/disable continuous routing uses the live evaluator…
Per-section reinject/fallback pairs against `blocksBySection[spineIndex]`, so the
cross-section bid bleed path remains closed. `evaluateBilingual` uses a weak web view
handle and does not create a retain/lifecycle issue. Eviction callback is now success-only
and generation-guarded."

## Accepted finding (rule-47 round-3 escalation = accept)

The single open Medium (in-flight guard for the per-section direct-translation fallback)
is **accepted with rationale**, not fixed in a 4th round:

- It is **not a correctness bug** — Codex explicitly confirmed it does NOT reintroduce
  cross-section bleed. The WI's purpose (no cross-section `bid` bleed) is achieved + verified.
- It is a **dedup/efficiency** concern (possible duplicate AI-provider calls) in a
  count-mismatch FALLBACK path that only fires when a section's cached segment count ≠ its
  DOM leaf-block count.
- It only affects users who enable BOTH the dark `epubContinuousScroll` flag AND bilingual
  — a niche combination of a feature that is flag-gated dark and CU-blocked from shipping
  default (see #71 terminal-gate finding). Near-zero current exposure.
- Findings converged across the 3 rounds (8 → 5 → 1), satisfying rule 47's intent (no
  endless grind).

**Follow-up filed**: an in-flight guard keyed by `TranslationUnitID` + block-count/hash
around the continuous direct-translation fallback, to land before `epubContinuousScroll`
flips default (tracked on GH #1200, the WI-7 issue, alongside the live CU verification).

## Verdict

**follow-up-recommended.** Zero open Critical/High; zero correctness Medium. One accepted
non-correctness efficiency Medium with a tracked follow-up. Full `vreaderTests` suite passes
(7333 tests). Core (per-section caching, JS scoping, inject pairing, envelope parsing,
eviction gen-guard) unit-verified. Live continuous-mode bilingual rendering (enable→render→
disable) is CU-gated — not unit-constructible; deferred to device/CU verification (consistent
with #71's other slices + the rAF/virtual-display CU block).
