---
branch: fix/issue-1586-foliate-bilingual-inject
threadId: 019eab61-31d2-78c0-9039-d49cf474ef66
rounds: 1
final_verdict: ship-as-is
date: 2026-06-09
---

# Codex Audit — Bug #334 / GH #1586 (Foliate AZW3 bilingual translation never injects)

## Root cause

`foliate-host.js bilingualSectionText` returned the whole section
`body.textContent` (no paragraph boundaries). Swift `ChapterSegmenter.paragraphs`
splits on blank lines, so the section collapsed to ~1 segment while
`bilingualEnumerate` counted N leaf blocks → `FoliateBilingualPipeline.translationsByBid`
(pairs ONLY when `blocks.count == segments.count`) returned an empty map →
`buildInjectJS` returned nil → no inject → the loading shimmer stayed stuck.

## Fix

A shared module-scope `bilingualLeafBlockElements(doc)` + `bilingualNormalizeBlockText(el)`
in `foliate-host.js`, used by BOTH `bilingualEnumerate` (bid stamping) and
`bilingualSectionText` (now joins leaf-block texts with `\n\n`). `paragraphs == blocks`
holds → 1:1 pairing succeeds → translations inject. The change is mirrored into
`foliate-bundle.js` (the esbuild IIFE the app loads) by surgical patch — the build
toolchain (`npx esbuild … --external:./{comic-book,fb2,pdf}.js`) regenerates
unrelated regions due to esbuild-version drift + missing format-stub sources, so a
full rebuild was rejected in favor of a minimal, logic-identical hand-patch
(verified `node --check`).

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| FoliateBilingualContainerView.swift:639 (`injectIfCached`) | Medium | The JS fix removes the KNOWN mismatch, but if cached translations exist and `buildInjectJS` returns nil from any FUTURE residual count divergence (e.g. live `getContents()` vs fresh `createDocument()`), nothing clears the loading decoration → the original stuck-shimmer symptom could recur. | **Fixed** — `injectIfCached` now adds an `else` that calls `clearLoadingJS(sectionIndex:)` when translations exist but the pairing yields no inject map, so the shimmer fails safe to source-only and can never get stuck. Belt-and-suspenders; the shared selector makes the mismatch unreachable today. |

Codex confirmed (no JS findings):
- `bilingualLeafBlockElements` exactly preserves the prior enumerate semantics
  (tag set `p/li/blockquote/pre/dd/dt`, decoration skip, non-leaf `querySelector`
  skip, empty-after-normalize skip, document order).
- `foliate-host.js` and `foliate-bundle.js` are logically identical in the touched
  paths.
- The `texts.length == 0 → body.textContent` fallback is safe (worst case is wasted
  translation work, never a wrong injection).
- Regression risk to the working enumerate path is low (straight extraction).

## Test seam note (manual-fallback rationale for the JS portion)

`foliate-host.js` / `foliate-bundle.js` have no Swift/JSContext unit-test seam in
this repo (per the codebase's established treatment — the bilingual host DOM logic
is device-verified, not unit-tested). The RED→GREEN proof is the deterministic
CU-free device repro via the Feature #77 `bilingual` DebugBridge harness:

- **Before fix**: Foliate section → `loading:9, mock:0` (stuck) after `inFlight` cleared.
- **After fix**: multi-block section → DURING `loading:4, mock:0` → POST `loading:0, mock:4`
  (4 blocks → 4 injected translations; 1:1). Visual: interlinear `[MOCK译] …` rows
  rendered inline. Evidence: `dev-docs/verification/bug-334-20260609.md`.

The Swift pairing logic (`FoliateBilingualPipelineTests`) is unchanged and green.

## Verdict

ship-as-is — the one Medium fixed; JS clean; device-verified end-to-end.
