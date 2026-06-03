---
branch: feat/feature-77-wi-5-legacy-continuous
threadId: 019e8ee2-7f2b-7c63-be61-5029648df237
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex Audit — Feature #77 WI-5 (legacy EPUB continuous loading-shimmer; FINAL WI)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48).

## Scope

Behavioral WI-5 (the **final WI → DONE**) — wire the loading shimmer into the
legacy EPUB **continuous-scroll** path (override-off). The stitched DOM holds
MULTIPLE `<section data-vreader-spine-index="N">` blocks, each with its own unit;
several can be in flight at once, so the shimmer is reconciled PER materialized
section through the live evaluator:

- `EPUBBilingualJS.bilingualClearLoadingJS(spineIndex:)` — section-scoped loading clear (nil branch byte-identical to WI-2's global form; non-nil scopes to the spine-index root).
- `EPUBBilingualOrchestrator.clearLoadingJS(spineIndex:)` — forwards.
- `EPUBReaderContainerView+Bilingual.swift` — `handleBilingualPrefetchChange` branches to the continuous handler in continuous mode.
- `EPUBReaderContainerView+ContinuousBilingualLoading.swift` (new) — `handleBilingualPrefetchChangeContinuous` (per-section reconcile, deferred into a Task).
- `EPUBReaderContainerView+ContinuousBilingual.swift` — `handleSectionBilingualBlocks` paints a late-materializing section's shimmer.

## Round 1 — findings (threadId 019e8ee2-7f2b-7c63-be61-5029648df237)

The continuous handler was authored synchronous; the **focus-#4 prompt** caught the
risk and the fix was applied BEFORE Codex's read, so Codex audited the deferred
version (it explicitly confirmed the landed-vs-failed race is "not present").

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| EPUBReaderContainerView+ContinuousBilingual.swift (`handleSectionBilingualBlocks`) | **Medium** | A section that materializes AFTER its unit already entered the in-flight set never gets a shimmer: the earlier `.readerBilingualPrefetchDidChange` replay skipped the not-yet-materialized section, `prefetchUnitIfNeeded` is a no-op for an in-flight unit, and `injectBilingualSection` no-ops without a cached translation. | **Fixed.** After `prefetchUnitIfNeeded` + `injectBilingualSection`, if `translations(for:unit)==nil && inFlightUnits.contains(unit)` → `evaluateBilingualLive(buildLoadingJS(forSection:))`. Idempotent (the loading-inject skips already-decorated blocks); a landed translation is skipped by the `translations==nil` guard. |
| EPUBReaderContainerView+ContinuousBilingual.swift:1 | Low | File at 380 lines, over the ~300 budget (and contrary to the header's claim). | **Partially fixed.** `handleBilingualPrefetchChangeContinuous` extracted to `EPUBReaderContainerView+ContinuousBilingualLoading.swift` (65 lines); the file dropped to 351. The residual is the pre-existing #71 modifier + section-hook surface. **Accepted** — further splitting re-cuts #71's stable surface, out of WI-5's scope (same disposition as the WI-2 driver-size Low). |

### Round-1 "no finding" confirmations
- **Section-scoped clear is correct.** `scopedClearLoadingJS` roots at `[data-vreader-spine-index="N"]`, removes only `.vreader-bilingual-loading[data-vreader-decoration]` within — cannot touch another section's nodes or a landed translation.
- **The synchronous-vs-deferred race (focus #4) is NOT present** — the handler defers into a `Task { @MainActor }`, so `finishPrefetch` caches a success before the `translations(for:)` check runs (a landed unit is skipped, not spuriously cleared).
- Per-section `evaluateBilingualLive` loop consistent with the existing continuous precedent (live evaluator, not the single-slot seam).

## Round 2 — verification (threadId 019e8ef5-c75c-7e10-8be6-d512992fb3aa)

- **Fix 1 (Medium): RESOLVED.** Late-materializing section shimmer is correct + idempotent; `inFlightUnits` readable via `private(set)`; landed translations skipped.
- **Fix 2 (Low): PARTIALLY** — extraction correct (cross-file method intact, called from `+Bilingual.swift:262`, deferred-Task fix intact, registered in pbxproj); file 351 (> ~300, accepted).
- **NEW Critical/High/Medium: none.**

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2; the residual file-size
Low accepted with rationale (pre-existing #71 surface). All loading suites green
(`EPUBBilingualJSLoadingTests`, `EPUBBilingualOrchestratorLoadingTests`) + full app
compile. **This is the final WI — the feature row moves to `DONE`.** Gate-5b
acceptance (transient shimmer on a CJK book across all four engines, Readium-OFF
device check) flips it to `VERIFIED`.
