---
branch: feat/feature-77-wi-3-foliate
threadId: 019e8ea6-9991-7ac0-a975-fabeaf719a19
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex Audit — Feature #77 WI-3 (Foliate AZW3/MOBI loading-shimmer wiring)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48).

## Scope

Behavioral WI-3 — wire the loading shimmer into the **Foliate AZW3/MOBI engine**
(mirrors the shipped Readium WI-2):

- `foliate-host.js` — `readerAPI.bilingualInjectLoading(opts)` (shimmer node + 2 bars, skip-decorated guard, CSS.escape) + `readerAPI.bilingualClearLoading(targetSectionIndex)` (loading-only removal); `bilingualInject`'s update branch now drops the loading class before `textContent` (in-place replacement).
- `foliate-bundle.js` — regenerated via `build-bundle.sh` (esbuild); grep-confirmed in sync.
- `FoliateBilingualJS.swift` — `loadingClassName`/`shimmerBarClassName` consts + `bilingualInjectLoadingJS` + `bilingualClearLoadingJS`.
- `FoliateBilingualOrchestrator.swift` — `buildLoadingJS(sectionIndex:)` + `clearLoadingJS(sectionIndex:)`.
- `FoliateBilingualContainerView.swift` — `.readerBilingualPrefetchDidChange` observer + `handleBilingualPrefetchChange`; `handleRelocated` clears the LEFT section's shimmer on a section change.
- `FoliateSpikeView.swift` — `themeCSS` appends `bilingualLoadingCSSRule()`.

## Round 1 — findings (threadId 019e8ea6-9991-7ac0-a975-fabeaf719a19)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| FoliateBilingualContainerView.swift:657 | **Medium** | `handleBilingualPrefetchChange` captured `locator`/`scopedIndex` BEFORE the deferred `Task`. A relocate during the `await provider.unit(containing:)` could let the task inject a shimmer back into the just-left section after `handleRelocated` already cleared it — a stale off-current shimmer. | **Fixed.** The handler now resolves `makeCurrentLocator()`/`currentSectionIndex` LIVE inside the `Task`, captures `scopedIndex` at task start, and re-checks `guard currentSectionIndex == scopedIndex` AFTER the await before any `evalBilingualJS` — a relocate during the await makes the task bail. |

### Round-1 "no finding" confirmations
- `bilingualInjectLoading` skip-guard correct (no downgrade, no duplicate); shimmer structure matches the Swift emitter; CSS.escape fallback fine; section scoping + `getContents()`/`try` guards correct.
- `bilingualInject`'s `classList.remove('vreader-bilingual-loading')` is a safe no-op when absent; `textContent` wipes shimmer-bar children in place without harming plain reinjects.
- `bilingualClearLoading` targets only `.vreader-bilingual-loading[data-vreader-decoration]` — landed translations survive.
- `foliate-bundle.js` is in sync (grep-confirmed: both new methods + the class-clear).
- Landed-vs-failed branch matches the Readium WI-2 ordering argument (task-deferred → `translationsByUnit` updated before the nil check).
- `handleRelocated` clear-on-leave tradeoff acceptable (premature-clear of a paginated adjacent shimmer beats a stuck shimmer); `previousIndex == nextIndex` guarded.

## Round 2 — verification (threadId 019e8eb8-1798-72c3-86d2-dfc75b8a1588)

**RESOLVED. No new Critical/High/Medium.** The live-resolve + post-await section-stability guard closes the relocate-during-await race.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2. WI-3 suites green
(`FoliateBilingualJSTests`, `FoliateBilingualOrchestratorTests`) + full app compile;
bundle regenerated and in sync with `foliate-host.js`.
