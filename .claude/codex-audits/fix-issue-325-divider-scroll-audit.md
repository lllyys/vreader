---
branch: fix/issue-325-divider-scroll
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-06-06
---

# Audit — Bug #325 sub-viewport-divider windowed-scroll fix

Manual-fallback (Codex wedges on this codebase, rule 53).

## Manual audit evidence
- **Files read**: `paginator.js` + `foliate-bundle.js` `#ensureWindow` (+ new
  `#mountedSectionHeight`); `TestSeeder.seedDividerAZW3`; `VReaderApp` flag/seed
  wiring; `DebugFixtureCatalog`; `LaunchHelper`; `Bug325DividerScrollVerificationTests`.
- **Correctness**: the fix extends the mounted window forward ONLY while the
  bottom-of-window section is already mounted AND measures shorter than the
  viewport (`#mountedSectionHeight(hi) < this.size`). It does NOT mutate
  `#index`, so the relocate fraction (`#windowedResolve` → `#promoteCurrentView`)
  and Bug #265 position restore are untouched. For tall sections the offset
  reaches their range normally (`#index` advances), so the new `while` never
  iterates → #73/#76 path byte-for-byte unchanged. Verified empirically:
  `FoliateVerticalWindowBundleTests` 13/13 green; `Bug325DividerScrollVerificationTests`
  RED (pre-fix, Content Two unreachable) → GREEN (post-fix).
- **Termination**: the `while` is bounded by `hi + 1 < this.sections.length`
  and advances `hi` each iteration — terminates in ≤ remaining-sections steps.
  Unmeasured sections return `Infinity` (not `< size`), so it never pre-extends
  speculatively into unmounted sections (one section per measured-short cycle).
- **Eviction parity**: `#evictOutsideWindow(lo, hi)` uses the extended `hi`, so
  the pre-mounted section is NOT immediately evicted (no mount/evict thrash).
- **Source/bundle parity**: the same fix is applied to BOTH `paginator.js`
  (source) and `foliate-bundle.js` (the loaded bundle), matching the bundle's
  esbuild var-naming (`i3`/`v3`/`x3`).
- **Test infra**: `seedDividerAZW3` mirrors `seedMiniAZW3` (distinct hash,
  bypasses the importer → native `.azw3` → Foliate); `--disable-kindle-convert`
  / `--seed-divider-azw3` are DEBUG launch args; the synthetic AZW3 is
  public-domain (hand-authored). No production behavior change outside the fix.
- **Risks accepted**: `this.size` is the viewport extent on the active scroll
  axis; for vertical-scroll horizontal-writing books (the AZW3 case + the common
  case) it is correct. Vertical-writing (vertical-rl) uses the same axis-aware
  `#elementAxisSize`; the comparison remains valid.

**Verdict: ship-as-is.**
