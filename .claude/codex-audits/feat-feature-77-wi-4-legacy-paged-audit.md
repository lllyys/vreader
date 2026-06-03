---
branch: feat/feature-77-wi-4-legacy-paged
threadId: 019e8ecc-b59e-7122-a2e4-95b125999c27
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex Audit — Feature #77 WI-4 (legacy EPUB paged loading-shimmer wiring)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48).

## Scope

Behavioral WI-4 — wire the loading shimmer into the **legacy EPUB engine
(`EPUBWebViewBridge`, the override-off PAGED path)**. Readium is the default
engine, so this is the fallback path used when `readiumEPUBEngine` is OFF:

- `EPUBBilingualOrchestrator.clearLoadingJS()` — wraps `EPUBBilingualJS.bilingualClearLoadingJS()` (loading-only clear). `buildLoadingJS(forSection:)` already existed (WI-1).
- `EPUBReaderContainerView+Bilingual.swift` — `handleBilingualPrefetchChange(inFlightUnits:)` (paged handler, guards `!isBilingualContinuousMode` — continuous is WI-5) + wired `onPrefetchDidChange` into `bilingualSurfacesModifier`. Pushes via the bridge's single `pendingHighlightJS` seam.
- `EPUBReaderContainerView+ContinuousBilingual.swift` — `EPUBBilingualSurfacesModifier` gained an `onPrefetchDidChange` closure + a fingerprint-guarded `.readerBilingualPrefetchDidChange` observer.

## Round 1 — verdict (threadId 019e8ecc-b59e-7122-a2e4-95b125999c27)

**No findings. ship-as-is.**

Codex confirmed every correctness argument:

- **Landed-vs-failed `translations(for:)==nil` gate is sound.** `finishPrefetch` removes the unit from `inFlightUnits` + posts `.readerBilingualPrefetchDidChange`, THEN (success) writes `translationsByUnit` + posts `.readerBilingualDidChange`. Because the handler defers its work into a `Task`, the success case sees the cache populated and does NOT queue `clearLoadingJS`.
- **`pendingHighlightJS` single-slot is acceptable.** If inject overwrites loading before the bridge consumes it → skip the shimmer, paint the translation directly (no flicker). If loading lands first → the inject's `classList.remove('vreader-bilingual-loading')` replaces the shimmer in place.
- **No stale-chapter stuck-shimmer path in paged mode.** A chapter swap destroys the old DOM; a stale loading payload's old bids miss in the new document → no-op.
- `!isBilingualContinuousMode` guard correctly defers continuous to WI-5.
- No Swift 6 concurrency problem in the `.onReceive` / `Set<TranslationUnitID>` / `Task` path.
- No meaningful dead-code / duplication beyond intentional parity with the Readium/Foliate handlers.

## Verdict

**ship-as-is.** Zero findings. WI-4 suites green
(`EPUBBilingualOrchestratorLoadingTests`, `EPUBBilingualOrchestratorTests`) +
full app compile. Residual: device verification with the Readium override OFF
(planned; final-WI acceptance captures the transient visual).
