---
branch: feat/feature-71-wi-6b-iii-restore-safearea
threadId: 019e6861-f070-7e21-a752-e3d730a4a095
rounds: 2
final_verdict: ship-as-is
date: 2026-05-27
---

# Codex Audit — Feature #71 WI-6b-iii (position restore)

Gate-4 audit of `git diff main`. Author = implementing Claude session; auditor =
Codex MCP (separate process). 2 rounds, terminal **ship-as-is**. Flag-gated dark.

## Scope (this slice = position restore only)

`EPUBContinuousScrollCoordinator` gains `restoreFraction: Double?` (set at build
from `viewModel.currentPosition?.progression`); after `materializeInitialWindow()`
seeds the anchor + extends ±1, it scrolls the anchor section to that fraction via
`scrollToSpineFractionJS` (best-effort, gen-guarded, `fraction > 0`). 3 tests.

## Investigated + deferred (not silently dropped)

- **Inner-scroll-root safe-area (re-audit finding 4)**: device-verified the
  inherited Bug-#163 `webView.scrollView` inset ALREADY positions continuous
  content below the notch (`eval firstSectionTopY: 76`, screenshot not clipped).
  An initial `margin-top` bootstrap inset was non-functional (`safeAreaTopInset=0`
  at bootstrap-load time) AND a double-inset risk → reverted. Bottom-clip edge
  (root `height:100vh` while the webView is inset → last ~inset px off-screen) is
  a noted follow-up.
- **Live mode-switch rebuild (finding 2 full)**: finding-2 SAFETY (no stale eval)
  is met by 6b-i's `coordinator.invalidate()` + config-release on the one-way
  hard-block. Full live rebuild deferred.

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBContinuousScrollCoordinator.swift (materializeInitialWindow) | **High** | Stale-generation gap BETWEEN the two initial-window extends: a mode-switch/reopen during the forward extend's await aborts it internally, but the backward extend would then capture the NEW generation and stitch stale-window work. | **FIXED.** Added `guard gen == generation else { return }` between the forward and backward extends. |
| EPUBContinuousScrollCoordinatorTests.swift | Low | File at 319 lines (> ~300 guideline). | **Accepted with rationale**: test-only, marginal (+19), and the restore tests are cohesive with the sibling `materializeInitialWindow` tests (shared helpers); splitting would duplicate helpers + fragment closely-related coordinator behavior. |

Round 1 confirmed: restore placement (after both extends, gen-guarded) is correct; nil/0/>1 fraction handled (JS clamps); deferrals defensible.

## Round 2

"Clean. No remaining Critical/High/Medium findings." Gen-guard fix closes the gap; Low acceptance reasonable.

## Verification

- Unit: 3 coordinator tests (restore scrolls anchor to fraction; nil + 0 → no scroll). Full suite 7287 green.
- Device: `scrollToSpineFraction` primitive moves the live `#vreader-scroll-root` (eval `moved: true`, clamped to the short fixture's content max — root at body-top so `offsetTop` is effectively root-relative). Safe-area: `firstSectionTopY: 76` + screenshot (content below notch, not clipped).

## Verdict

**ship-as-is.** Zero open Critical/High/Medium; one Low accepted with rationale.
