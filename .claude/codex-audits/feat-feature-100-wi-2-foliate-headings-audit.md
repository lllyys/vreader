---
branch: feat/feature-100-wi-2-foliate-headings
threadId: 019eb50c-007c-75f1-bf52-db634442ccfb
rounds: 3
final_verdict: ship-as-is
date: 2026-06-11
---

# Codex Gate-4 audit — feature #100 WI-2 (Foliate heading echo rows)

Sessions: r1 `019eb4f9-4e7f-7810-97ef-152f6f6f4f2b`, r2
`019eb509-4287-73e2-8b7b-a22fa8f118ff`, r3
`019eb50c-007c-75f1-bf52-db634442ccfb`.

## Round 1 — needs-fixes

| Finding | Severity | Resolution |
|---|---|---|
| `FoliateSpikeView.swift:342` — the runtime loads `foliate-bundle.js`; the checked-in bundle was NOT rebuilt, so WI-2 was absent at runtime | High | FIXED (19a4c83d): bundle rebuilt via `build-bundle.sh` (lockfile-pinned esbuild 0.28.0); the resource test now pins the BUILT artifact too |
| `foliate-host.js:653` — the replace path only ADDED modifiers; a CJK→Latin switch left stale `--cjk` tracking on reused nodes | Medium | FIXED (19a4c83d): both engines NORMALIZE on replace (`classList.toggle(--cjk, TARGET_CJK)`, remove both on non-headings) — incl. the same hole in WI-1's merged EPUB path |
| resource test read only the source via `Bundle.main` | Low | FIXED: Bundle fallback helper + pins on source AND bundle + a normalization pin |

## Round 2 — needs-fixes

All round-1 findings confirmed closed; one new Medium: the rebuilt bundle
carried deltas beyond the heading feature (a relocated paginator comment
block).

## Round 3 — clean

The extra deltas are esbuild OUTPUT-FORM drift (const→var, loop renames,
comment relocation) from the previous bundle having been built with a
non-pinned esbuild — exactly the determinism gap `build-bundle.sh`'s
local pin exists to close; the repo's parity gate
`FoliatePaginatorScrollBoundaryTests` passes (15/15). "The determinism
explanation is coherent and matches the diff shape." VERDICT: clean.

## Summary

3 rounds, 4 findings (1 High, 2 Medium, 1 Low), all fixed. Suites green:
`FoliateBilingualJSTests` (+3 incl. built-bundle pins),
`FoliateBilingualOrchestratorTests` (+1), `EPUBBilingualJSTests`
(normalization pin), `FoliateBilingualPipelineTests`,
`FoliatePaginatorScrollBoundaryTests`. Gate-5a: bilingual rows render
live on the AZW3 engine (artifact); the real-heading AZW3 visual is
fixture-blocked (no AZW3 with h-elements available — the Masque book's
"headings" are styled `<p>`s, probe-confirmed; same accepted class as
feature #68's AZW3 spot-check). Ship as-is.
