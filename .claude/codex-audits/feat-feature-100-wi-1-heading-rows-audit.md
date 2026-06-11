---
branch: feat/feature-100-wi-1-heading-rows
threadId: 019eb4ee-8033-7250-b1e0-688947af5e1d
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Codex Gate-4 audit — feature #100 WI-1 (heading echo rows, both EPUB engines)

Runner: `scripts/run-codex.sh` (codex exec, gpt-5.4, read-only sandbox).
Sessions: r1 `019eb4e8-e347-7140-a201-ef43791ad1b6`, r2
`019eb4ee-8033-7250-b1e0-688947af5e1d`.

## Round 1 — needs-fixes

| Finding | Severity | Resolution |
|---|---|---|
| `EPUBReaderContainerView+Bilingual.swift:271` + `+ContinuousBilingualLoading.swift:44` — the legacy paged + continuous loading-shimmer handlers never synced `bilingualOrchestrator.targetIsCJK` before `buildLoadingJS`, so a heading's FIRST shimmer (before any inject) missed the `--cjk` modifier | Medium | FIXED (640ce869): both sites sync from `vm.targetLanguage` exactly like the inject paths |
| builder-level-only test coverage let the above slip through | Low | FIXED (640ce869): orchestrator-level test pins the flag flowing into `buildLoadingJS` AND `buildInjectJS` |

Round 1 verified clean: the #266 leaf-block rule with headings, the #268
`translateBlocksDirectly` fallback (heading texts included — enumerate-
sourced), idempotent reinject, the Readium commander/adapter threading,
Swift multiline JS regex escaping, the #68 drop-cap selector and the #336
justify interplay.

## Round 2 — clean

Both findings confirmed resolved at the right seams; "I do not see any
new regression in the patch." VERDICT: clean.

## Summary

2 rounds, 2 findings (1 Medium, 1 Low), fixed. Suites green:
`EPUBBilingualJSTests` (+4), `ReadiumBilingualEvalAdapterTests` (+2),
`BilingualCSSInjectionTests` (+3), `EPUBBilingualOrchestratorTests` (+1),
plus the regression sweep (`EPUBBilingualPipelineTests`,
`BilingualCSSRenderIntegrationTests`, `ReadiumBilingualCommanderTests`).
Gate-5a slice: the centered, border-less, CJK-tracked heading echo row
renders live under the fixture's h1 on the Readium engine
(`feature-100-wi1-slice-heading-echo-row-20260611.png`). Ship as-is.
