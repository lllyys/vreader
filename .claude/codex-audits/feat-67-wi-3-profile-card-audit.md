# Codex Audit — feat/67-wi-3-profile-card

Feature #67 (Settings profile-header card + grouped-row restyle), WI-3 —
"`SettingsHeaderViewModel` + `SettingsProfileCard` component". Gate 4
(implementation audit loop) per `.claude/rules/47-feature-workflow.md`.

- **Auditor**: Codex MCP (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox.
- **Thread**: `019e415f-9dd6-7941-ba18-d7ff057438b3`
- **Date**: 2026-05-20
- **Rounds**: 2 (round 1 — 1 High + 1 Medium; round 2 — clean, ship-as-is).

## Scope audited

Production:
- `vreader/ViewModels/SettingsHeaderViewModel.swift` (new) — `@MainActor @Observable`
  view model fetching the library book count + this-month reading seconds via
  the optional `LibraryStatsReading` boundary; nil/error → zeros; idempotent
  (last-write-wins via a monotonic `latestRequestID`).
- `vreader/Views/Settings/SettingsProfileCard.swift` (new) — the design's
  `ProfileCardLibrary` (library-identity card, #862 Option A): 48pt three-book-
  spine glyph tile, "Your library" serif-italic header, "N books · Nh read this
  month" subline, pill Stats button.

Tests:
- `vreaderTests/ViewModels/SettingsHeaderViewModelTests.swift` (new)
- `vreaderTests/Views/Settings/SettingsProfileCardTests.swift` (new)

## Round 1 — findings (1 High + 1 Medium)

- **High — surface-fill fidelity** (`SettingsProfileCard.swift`): the card
  background / glyph tile / Stats pill were filled with substituted repo theme
  tokens (`paperColor`, `inkColor`-opacity). The committed `ProfileCardLibrary`
  design specifies explicit fills (`#fff` / `rgba(255,255,255,0.04)` card,
  `rgba(0,0,0,0.04)` / `rgba(255,255,255,0.06)` glyph tile, `rgba(60,40,20,0.08)`
  / `rgba(255,255,255,0.08)` pill) — a rule-51 issue: the card would render
  flatter and lower-contrast than the handoff.
- **Medium — `latestRequestID` race untested** (`SettingsHeaderViewModelTests.swift`):
  `loadCalledTwiceIsStable` ran two sequential identical loads — it only proved
  "double load doesn't accumulate", not last-write-wins across an `await`
  suspension point, which is the regression `latestRequestID` exists to prevent.

## Round 1 → fixes applied

1. **High**: added `enum SettingsProfileCardColors` mirroring the JSX formulas
   verbatim — `cardBackground` / `glyphTileFill` / `statsPillFill`, each
   `isDark`-branched. The card body, glyph tile, and Stats pill consume these
   helpers. File-header "Key decisions" gained a bullet. New tests
   `cardBackgroundMatchesDesignLightAndDark` / `glyphTileFillMatchesDesignLightAndDark`
   / `statsPillFillMatchesDesignLightAndDark` pin the exact RGBA components.
2. **Medium**: added a real overlap test `slowEarlierLoadDoesNotOverwriteANewerLoad`
   — a `GatedStats` actor double whose `countLibraryBooks` parks on a gate and
   exposes `waitUntilEntered()`. The test starts load #1 (claims
   `latestRequestID=1`, parks), deterministically waits until it has entered the
   boundary, runs load #2 to completion (claims `latestRequestID=2`, applies 222),
   then releases load #1 — asserting the stale value (111) never overwrites 222.
   Not flaky — no `Task.yield()` ordering trick. `loadCalledTwiceIsStable` kept
   as the simpler happy-path case.

## Round 2 — re-audit

Both round-1 findings verified genuinely resolved. The auditor explicitly
confirmed the race test "is a real overlap test ... proves the stale request
finishes after the newer one and still cannot overwrite it ... not dependent
on a flaky `Task.yield()` ordering trick". No new Critical/High/Medium.

## Verdict

final_verdict: ship-as-is

Gate 4 clean in 2 rounds (rule-47 maximum is 3). WI-3 ships. The visible mount
of `SettingsProfileCard` into `SettingsView` is WI-4 — WI-3 delivers the view
model + the component only (foundational tier).
