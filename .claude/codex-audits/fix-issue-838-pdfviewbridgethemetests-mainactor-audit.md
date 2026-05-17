---
branch: fix/issue-838-pdfviewbridgethemetests-mainactor
threadId: 019e3741-02b7-7520-bc36-986a75522452
rounds: 1
final_verdict: ship-as-is
date: 2026-05-18
---

# Codex audit — Bug #216 / GH #838

`PDFViewBridgeThemeTests` not `@MainActor` — off-main `PDFView` access
trips UIKit's main-thread layer guard and crashes the parallel
`xcodebuild test` runner.

## Changed files

- `vreaderTests/Views/Reader/PDFViewBridgeThemeTests.swift` — test-only.
  Added `@MainActor` to the `@Suite` struct; removed the now-redundant
  per-test `@MainActor` on `applyThemeIfChanged_drivesProductionGuard`;
  added a header comment explaining the isolation requirement.

No product code changed.

## Round 1

| file:line | severity | issue | fix |
|---|---|---|---|
| — | — | No findings | — |

Codex verified:

- Suite-level `@MainActor` isolates all 8 test methods, including the
  six `PDFView()`-constructing tests and `applyThemeIfChanged_drivesProductionGuard`.
- Over-isolating the logically-pure `darkThemeBackground_isNotEqualToPaper`
  is harmless and consistent with the suite's UIKit-facing purpose.
- Removing the per-test `@MainActor` is safe — the enclosing `@MainActor`
  type already isolates that synchronous `@Test` method; the method-level
  annotation was redundant, not additive.
- No compile hazard. `@Suite(...)` then `@MainActor` on the struct
  matches existing usage (`NativeTextPagedIntegrationTests.swift`) and
  the repo convention in `.claude/rules/50-codebase-conventions.md` §1.
- Change is confined to one file under `vreaderTests`; no product-code
  risk.
- No second suite in the file; no test should remain non-`@MainActor`.

## Empirical verification

- **RED** — pre-fix run of `vreaderTests/PDFViewBridgeThemeTests` under
  the parallel scheduler logged **72**
  `_raiseExceptionForBackgroundThreadLayerPropertyModification`
  backtraces (off-main UIKit layer mutations across the 6 PDFView tests).
- **GREEN** — post-fix run of the same suite logged **0** backtraces;
  all 8 tests pass; per-test time dropped from ~0.44–0.55 s (Main Thread
  Checker capturing backtraces) to ~0.003–0.010 s.

## Verdict

**ship-as-is.** Zero findings in one round. The fix is minimal, correct,
matches codebase convention, and is confined to the test target. RED→GREEN
is measurable and clean (72 → 0 off-main backtraces).
