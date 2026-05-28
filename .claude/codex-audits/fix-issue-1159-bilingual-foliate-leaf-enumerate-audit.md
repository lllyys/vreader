---
branch: fix/issue-1159-bilingual-foliate-leaf-enumerate
threadId: 019e6421-71b9-7450-b376-3672d79f9a95
rounds: 1
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex Audit — Bug #268 sub-part (2): Foliate-host leaf-enumerate

This PR delivers sub-part (2) of Bug #268 / GH #1159: leaf-fix the Foliate/AZW3
`bilingualEnumerate` so it counts the same LEAF-block unit model the EPUB
enumerate already uses (Bug #266). The Foliate host previously walked
`getElementsByTagName('*')` and kept every `BLOCK_TAGS` element, double-counting
a `<blockquote><p>` / `<li><p>` (container AND child). The shared
`BilingualPairing` made that fail-safe (source-only on count mismatch), but the
double-count forced the source-only fallback unnecessarily.

## Change

`vreader/Services/Foliate/JS/foliate-host.js` — added
`BLOCK_SELECTOR = Object.keys(BLOCK_TAGS).join(',')` and a leaf skip
`if (el.querySelector && el.querySelector(BLOCK_SELECTOR)) continue` in the
enumerate loop, identical to the EPUB fix in `EPUBBilingualJS.swift`. Rebuilt
`foliate-bundle.js` via `npm ci` + `build-bundle.sh` (esbuild 0.28.0).

## Findings

**Round 1 — No findings. Ship as-is.** Codex confirmed:
- The leaf test matches the EPUB fix exactly (same `BLOCK_TAGS`, `BLOCK_SELECTOR`,
  `querySelector` skip, decoration-skip ordering).
- Foliate's per-section walk over `contents` changes only scope, not leaf
  semantics; the block/leaf decision inside each section doc is identical.
- Edge cases correct: inline-only leaf blocks still enumerate; injected
  decoration nodes are siblings (not block descendants) so they don't affect
  leaf detection; deep nests reduce to the innermost leaf.
- No `bid`/`seq` breakage: skipped containers never enter `out`; `seq` advances
  only for kept leaves; per-section caches replaced/cleared on re-enumerate.
- Common AZW3/MOBI happy path (plain non-nested `<p>`) unaffected.

## Scope note

This is sub-part (2) of #268 only. Sub-part (1) — translate the enumerated block
`text[]` directly to make blocks↔segments 1:1 *by construction* (eliminating the
RESIDUAL EPUB `<pre>`-blank-lines + mixed-content-`<blockquote>` divergence) — is
a feature-workflow-class refactor of shipped feature #56 (rewires the EPUB
translation input across `ChapterTranslationService` / `ChapterTranslationPrefetcher`
/ `BilingualReadingViewModel` / EPUB inject) with AI-dependent device verification,
and is left for a dedicated pass. Both residual cases are rare + fail-safe today.

## Verdict

**ship-as-is** — sub-part (2) is a clean, low-risk improvement mirroring the
proven #266 EPUB leaf-fix.
