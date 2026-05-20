---
branch: feat/67-wi-4-mount-card-restyle-core
threadId: 019e457e-5215-70e2-bf59-1d0f4932e305
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 audit — feature #67 WI-4 (mount profile card + restyle core groups + Stats hand-off)

## Round 1 — findings

| Sev    | File:line                                                       | Finding                                                                                                                                                                                                                                                                                                                                                                                            | Resolution                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ------ | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| High   | `vreader/Views/Settings/SettingsView+StatsSheet.swift:43` (orig) | `presentStatsDashboard()` only allocated the dashboard VM when nil and never cleared it on dismiss. Reopen reused the prior window / sort / custom-range state → broke the design's "fresh entry-state per open" semantics.                                                                                                                                                                       | Fixed in commit `5580c3b`. Extracted state into `@MainActor @Observable` `SettingsStatsPresenter`: `present(build:)` always invokes the builder after a `dismiss()`, `dismiss()` clears both `isShowing` and `dashboardViewModel`, `handleSheetOnDismiss()` covers the swipe-down path bypassed by the dashboard's Done button. The View's `.sheet(..., onDismiss:)` routes swipe-dismiss through `handleSheetOnDismiss()`. |
| Medium | `vreaderTests/Views/Settings/SettingsViewStatsHandoffTests.swift:22` (orig) | Tests only proved the wired action posts the notification. WI-4 now owns the observer/presenter loop too, but there was no test for "first notification opens stats", "second notification while showing is a no-op", "dismiss then reopen builds a fresh presenter", or the swipe-dismiss path. The stale-VM bug passed the suite unchanged. | Fixed in commit `5580c3b`. New `vreaderTests/Views/Settings/SettingsStatsPresenterTests.swift` (7 cases) pins: initial state, first open, duplicate-open no-op, explicit dismiss, reopen identity change (`===`/`!==`), swipe-dismiss cleanup, rapid triple-fire-only-builds-once. The presenter is testable without a `@State` install or a SwiftData ModelContainer — the test substitutes a stub aggregator.                                                                                                                          |

Round 1 verdict: `block-recommended` (1 High + 1 Medium).

## Round 2 — verification

Re-audit of the round-1 fixes ran against commit `5580c3b`. The auditor verified:

- The round-1 High is genuinely fixed. `present(build:)` allocates exactly once per real open and guards duplicate fires (`SettingsView+StatsSheet.swift:52`). `dismiss()` clears both `isShowing` and `dashboardViewModel`. The View's `.sheet(..., onDismiss:)` routes swipe-down through `handleSheetOnDismiss()` so reopen gets a fresh VM on BOTH dismissal paths (`SettingsView.swift:151`).
- The round-1 Medium is also resolved. The new presenter tests cover initial state, first open, duplicate-open no-op, explicit dismiss, reopen identity change, swipe-dismiss cleanup, and rapid repeated `present` calls (`SettingsStatsPresenterTests.swift:53`).
- The extraction itself is sound: `@MainActor @Observable` is the right isolation for sheet-binding state, `@State` holding the presenter reference is the standard ownership pattern, the non-escaping `build` closure is correct because `present(build:)` invokes it synchronously, and the stub-aggregator test path is appropriate because these tests pin presenter state transitions, not dashboard loading behavior.
- `makeProductionStatsViewModel()` reads `modelContext.container` at open time — after the view is installed in the hierarchy, which is the right point for that dependency (`SettingsView+StatsSheet.swift:96`).

Round 2 verdict: **`ship-as-is`**. Zero open Critical / High / Medium findings across both rounds.

## Summary

- 2 rounds run (rule-47 maximum is 3).
- 1 High + 1 Medium round-1 — all fixed.
- 0 open findings at round 2.
- Author/auditor separation held: implementation by Claude Code, audit by Codex MCP (read-only sandbox) in a separate process.
- Final verdict: **`ship-as-is`**.
