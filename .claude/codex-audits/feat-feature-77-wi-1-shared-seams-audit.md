---
branch: feat/feature-77-wi-1-shared-seams
threadId: 019e8e41-8200-7420-9a43-14f2fbae8cf1
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex Audit — Feature #77 WI-1 (bilingual loading-shimmer shared seams)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48).

## Scope

Foundational WI-1 — the shared "loading shimmer" seams every bilingual engine
(Readium / legacy-EPUB / Foliate) will consume in later WIs:

- `vreader/Models/ReaderThemeV2+EPUBCSS.swift` — `bilingualLoadingCSSRule()` (theme-aware shimmer CSS).
- `vreader/Views/Reader/ReaderNotifications.swift` — `.readerBilingualPrefetchDidChange`.
- `vreader/ViewModels/BilingualReadingViewModel.swift` — `inFlightUnits` → `private(set)`; `setInFlight(_:)` funnel.
- `vreader/ViewModels/BilingualReadingViewModel+Prefetch.swift` — 4 mutation sites rerouted through the funnel.
- `vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift` — loading-inject builder + inject class-clear + CSS-selector hardening.
- `vreader/Views/Reader/Bilingual/EPUBBilingualOrchestrator.swift` — `buildLoadingJS(forSection:)`.
- Tests: `BilingualLoadingShimmerWI1Tests.swift` (new), `PDFBilingualPanelStateTests.swift` (funnel migration).

## Round 1 — findings (threadId 019e8e41-8200-7420-9a43-14f2fbae8cf1)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| EPUBBilingualJS.swift:474 | **Medium** | `bilingualInjectLoadingJS` (and the pre-existing `bilingualInjectJS`) escape bids only for the JS-string-literal context, then interpolate them into a CSS attribute selector `[data-vreader-bid="…"]`. EPUB enumerate PRESERVES a pre-existing `data-vreader-bid` from book HTML (`stamp()` returns the existing attr), so a crafted book could carry a `"`/`]` bid that breaks/redirects `querySelector`. Foliate already hardens this with `CSS.escape`; EPUB did not. | **Fixed.** Added shared `EPUBBilingualJS.bidSelectorEscapeJS` (`__vreaderBidEsc`) mirroring `foliate-host.js`' defensive `CSS.escape` (with the identical `/[^a-zA-Z0-9_-]/g` fallback), injected into BOTH inject IIFEs; each `findBlock` now routes the bid through `__vreaderBidEsc(bid)`. Added hostile-bid tests (`"`/`]`/`'`). |
| BilingualReadingViewModel.swift:229 | Low | `applyReTranslateResult` posted `.readerBilingualPrefetchDidChange` BEFORE `unavailableUnits.remove(unit)` — a future observer recomputing UI off the prefetch notification could see "translated, not in flight, still unavailable" for one synchronous turn. | **Fixed.** Reordered: `unavailableUnits.remove(unit)` now runs before `setInFlight(...)`. |
| ReaderThemeV2+EPUBCSS.swift:218 | Low | `@keyframes bShim` is document-global; an arbitrary book stylesheet using the same name could collide. | **Fixed.** Renamed `bShim` → `vreaderBilingualShim` in both the `@keyframes` block and the `animation:` declaration (+ comment + test pin). |

### Round-1 "other checks" (confirmed correct, no action)
- `finishPrefetch` funnel migration is exactly equivalent to the old remove-then-conditional-`isFetching` behavior.
- `applyReTranslateResult` `isFetching` semantics change is a correctness *improvement* (old code could leave `isFetching` stale).
- Loading-node update branch is style-consistent with the create branch; `textContent` intentionally clears the shimmer-bar children.
- `nextElementSibling` skip-guard is correct (text-node/last-child/null-parent safe; no duplicate, no downgrade).
- `Set<TranslationUnitID>` in `userInfo` is `Sendable`-safe in-process; `buildLoadingJS` is `@MainActor`-contained.
- New seams are dead-by-design for WI-1 (consumed by later WIs).

## Round 2 — verification (threadId 019e8e57-6ad6-7730-a3c5-d8aec8906fdd)

- **FIX 1 (Medium): RESOLVED** — escaper matches the Foliate precedent exactly; helper defined before use inside both IIFEs; fallback correct; `FoliateJSEscaper` still covers the JS-literal context. Medium fully closed.
- **FIX 2 (Low): RESOLVED** — unit state settles before the funnel post.
- **FIX 3 (Low): RESOLVED** — both executable CSS sites renamed; no orphaned live `bShim`.
- **NEW Critical/High/Medium: none.**

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2; all Low findings fixed.
All affected suites green (`EPUBBilingualJSLoadingTests`, `BilingualLoadingCSSRuleTests`,
`EPUBBilingualOrchestratorLoadingTests`, `BilingualSetInFlightFunnelTests`,
`EPUBBilingualJSTests`, `PDFBilingualPanelStateTests`).
