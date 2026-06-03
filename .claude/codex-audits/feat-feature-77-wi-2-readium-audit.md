---
branch: feat/feature-77-wi-2-readium
threadId: 019e8e74-f056-7a33-ab69-1955cdd422cc
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex Audit — Feature #77 WI-2 (Readium loading-shimmer wiring)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48).

## Scope

Behavioral WI-2 — wire the WI-1 loading-shimmer seams into the **Readium EPUB
engine (the DEFAULT engine; the primary user surface)**:

- `EPUBBilingualJS.bilingualClearLoadingJS()` — loading-only clear (removes
  `.vreader-bilingual-loading[data-vreader-decoration]`, leaving translations).
- `ReadiumBilingualEvalAdapter.loadingJS(bids:spineIndex:)` + `clearLoadingJS()`.
- `ReadiumBilingualCommander.injectLoading(_:spineIndex:)` + `clearLoading()`.
- `ReadiumEPUBHost+BilingualLoading.swift` (new) — `handleBilingualPrefetchChange(inFlightUnits:)` + `bilingualStyleCSS()` (combined block + shimmer CSS).
- `ReadiumEPUBHost+BilingualDriver.swift` — stale-shimmer `clearLoading()` on spine (re)entry; combined-CSS `setStyle`.
- `ReadiumEPUBHost+Bilingual.swift` — `.readerBilingualPrefetchDidChange` observer; theme-change combined CSS.

## Round 1 — findings (threadId 019e8e74-f056-7a33-ab69-1955cdd422cc)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| ReadiumEPUBHost+BilingualDriver.swift:273 | **Medium** | Both WI-2 handlers settle against `currentVReaderLocator(from: nil)`, not the unit/spine that changed. In scroll mode, a shimmer on chapter A that lands/fails after the user scrolls to B is no longer targeted, so A's loading node can persist until revisit. | **Fixed → reduced to Low.** `runBilingualEnumerate` now calls `await bilingualCommander.clearLoading()` on spine (re)entry (after the post-enumerate `isEnabled` recheck, before `updateBlocks`), so a re-entered spine never shows a stale shimmer. The Readium eval channel only reaches the visible spine, so an off-current spine cannot be targeted directly; the residual (a partially-visible windowed adjacent spine) self-heals on its next enumerate. |
| ReadiumEPUBHost+BilingualDriver.swift:1 | Low | Driver at 354 lines, over the ~300 budget, mixing enumerate/inject flow with WI-2 loading lifecycle. | **Fixed.** `handleBilingualPrefetchChange` + `bilingualStyleCSS` extracted to `ReadiumEPUBHost+BilingualLoading.swift` (82 lines); driver now 315. |

### Round-1 "no finding" confirmations
- **Landed-vs-failed `translations(for:) == nil` is correct.** `finishPrefetch` removes the unit from `inFlightUnits` BEFORE caching the translation, but the Readium observer does its check inside an async `Task` that runs AFTER `finishPrefetch` completes synchronously — so a successful unit's translation is already stored when the branch runs, and it is NOT cleared (the inject path replaces the shimmer in place). No flicker.
- Loading inject/clear JS is idempotent; the clear selector is correctly limited to loading nodes only (landed translations survive).

## Round 2 — verification (threadId 019e8e8b-9978-73d1-9ce0-68e5ff085fe7)

- **Medium → reduced to Low.** The spine-(re)entry `clearLoading()` is safe (the fresh shimmer for a visit is injected LATER via the prefetch-change, so any shimmer present at enumerate is stale), runs on the visible spine, is loading-only, and the landed inject removes the loading class in place. Closes the main off-current/re-entry case; residual is the windowed partial-visibility edge (self-healing).
- **Low (driver size) → improved.** Cross-file `bilingualStyleCSS()` access is structurally fine (same `extension ReadiumEPUBHost`, file in target). Driver 354 → 315.
- **NEW Critical/High/Medium: none.**

## Accepted Low findings (rationale)

1. **Windowed partial-visibility stale shimmer.** A failed prefetch whose spine
   is a partially-visible windowed adjacent spine (only in a multi-spine-DOM
   scroll model) shows a stale shimmer until that spine becomes current and
   re-enumerates. Readium's typical model renders one spine at a time (per the
   surface map), so the off-current DOM is gone in the common case; the residual
   self-heals. The fully-robust per-spine shimmer ownership requires a
   spine-targeted eval channel Readium does not expose — a larger redesign out of
   WI-2's scope. Documented in `ReadiumEPUBHost+BilingualLoading.swift`'s header.
2. **Driver still 315 lines (> ~300).** Improved from 354 by extracting the WI-2
   loading code. The residual is the pre-existing enumerate/prefetch/inject flow
   (already ~306 before WI-2); further splitting #42/#71 code is out of WI-2 scope.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2; both residual Lows
accepted with rationale. All WI-2 suites green (`ReadiumBilingualEvalAdapterTests`,
`ReadiumBilingualCommanderTests`, `EPUBBilingualJSLoadingTests`) + full app compile.
