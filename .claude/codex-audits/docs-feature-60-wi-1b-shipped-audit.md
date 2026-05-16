---
branch: docs/feature-60-wi-1b-shipped
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-16
---

## Scope

Updates the feature #60 plan to reflect WI-1b shipped (PR #778, v3.24.5). Touches `dev-docs/plans/20260515-feature-60-visual-identity-v2.md` (WI-1b table row + revision-history v9 entry) + `project.yml` / `project.pbxproj` (version bump 3.24.5/400 → 3.24.6/401).

**No Swift source files changed.** The audit-gate hook fires on `project.pbxproj` in the diff — false positive of the Swift-file heuristic. Manual mini-audit.

## Manual audit evidence

### What changed and why

- WI-1b table row: `Foundational — DEFERRED (manual-ops)` → `Behavioral — SHIPPED v3.24.5`. The reclassification Foundational → Behavioral is correct: when the plan first deferred WI-1b the `ReaderTypography` registry was dormant, but WI-4/5/7 have since merged and consume the registry + `cssFontStack` (verified earlier this session via `grep -rn "ReaderTypography\."` — hits in `ReaderSettingsStore`, `SelectionPopoverView`, `ReaderThemeV2+EPUBCSS`). Bundling the binaries therefore flips real rendering for users who select Source Serif 4 / Inter → behavioral.
- Revision-history v9 entry records: the shipped state, the interactive-session discharge of the deferral, the OFL/RFN handling, the Gate-4 Codex rounds, the Gate-5a slice, and the downstream-gate lift (WI-5 typography device-verify no longer blocked).
- Version-history numbering: the last numbered entry was `v8`; this adds `v9`. Monotonic. (The plan still carries the pre-existing duplicate-`v5` drift from parallel agents — out of scope here, flagged previously in PR #771's heads-up; not re-fixed as a drive-by.)

### Correctness checks

1. Facts in the new row/entry cross-checked against PR #778 (merged) and the WI-1b audit log `.claude/codex-audits/feat-feature-60-wi-1b-bundle-fonts-audit.md`: 7 faces, Source Serif 4.005 + Inter 4.1, both SIL OFL 1.1, Codex threads `019e2ed0`/`019e2ed5`, 2 rounds, ship-as-is — all consistent.
2. The "~2.9 MB" font-binary size replaces the earlier "~180–320 KB" estimate (the deferred row's guess); 2.9 MB matches the actual staged size (`ls -la vreader/Resources/Fonts/`).
3. Downstream-gate lift is accurate: with the binaries bundled, `ReaderTypography` resolves the real faces, so WI-5's typography device-verify can now confirm "Source Serif 4 renders".
4. Version bump 3.24.6 / build 401; xcodegen regen confirmed.

### Risks accepted

None. Plan-doc + version-bump only.

## Verdict

ship-as-is — plan revision + version bump. No Swift logic. Manual fallback used because there is nothing to send to Codex.
