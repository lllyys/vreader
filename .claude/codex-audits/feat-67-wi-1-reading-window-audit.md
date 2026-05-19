# Codex Audit — feat/67-wi-1-reading-window

Feature #67 (Settings profile-header card + grouped-row restyle), WI-1 —
"Reading-window persistence reads + month boundary + formatter". Gate 4
(implementation audit loop) per `.claude/rules/47-feature-workflow.md`.

- **Auditor**: Codex MCP (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox.
- **Thread**: `019e4146-6251-7f03-9ccb-7fc6d8620756`
- **Date**: 2026-05-20
- **Rounds**: 1 (clean — no Critical/High/Medium).

## Scope audited

Production:
- `vreader/Utils/MonthBoundary.swift` (new) — pure calendar-month `DateInterval` helper.
- `vreader/Services/LibraryStatsReading.swift` (new) — read-only persistence boundary protocol.
- `vreader/Services/PersistenceActor+ReadingWindow.swift` (new) — `sumReadingSeconds(in:)` +
  `countLibraryBooks()`; `extension PersistenceActor: LibraryStatsReading`.
- `vreader/Utils/ReadingTimeFormatter.swift` (modified) — added `formatCompactHours(totalSeconds:)`.

Tests:
- `vreaderTests/Utils/MonthBoundaryTests.swift` (new)
- `vreaderTests/Services/PersistenceActorReadingWindowTests.swift` (new)
- `vreaderTests/Utils/ReadingTimeFormatterTests.swift` (modified) — `formatCompactHours` cases.

## Round 1 — findings

- **Critical**: none.
- **High**: none.
- **Medium**: none.
- **Low (1)**: the WI-1 Surface-area row in the plan still named a
  "negative durations clamped" test case for `PersistenceActorReadingWindowTests`,
  but Gate-2 fix Medium #7 had already dropped that case (the negative
  `durationSeconds` path is not constructible — `ReadingSession.init` and
  `updateDuration(_:)` both clamp `>= 0`). The Surface-area row was simply not
  normalized to the Test-catalogue's decision; the implementation is not
  affected.

## Resolution

The Low finding is a stale plan claim, not a code defect — resolved by the
auditor's offered fix "update the plan to remove that named case and state
that clamping is guaranteed at `ReadingSession` creation". The plan's
Surface-area row for `PersistenceActorReadingWindowTests.swift` was corrected
to match the Test-catalogue WI-1 § (Gate-2 Medium #7): no negative-duration
case, with the rationale inline. The `Int64`-accumulation defensiveness in
`sumReadingSeconds` stays implemented (cheap, matches `ReadingStats.recompute`)
but is intentionally not exercised via an unreachable corruption path.

No production code change was warranted.

## Auditor confirmations (carried forward)

- Half-open month/window semantics (`[start, end)`) implemented correctly.
- DST / leap-year / year-boundary behavior covered at the pure-helper layer.
- `LibraryStatsReading: Sendable` + the `PersistenceActor` conformance are
  Swift 6 strict-concurrency safe.
- The `#Predicate` on `ReadingSession.startedAt` is valid and store-side;
  `ModelContext.fetchCount(_:)` usage matches existing repo patterns.
- No dead code; all files under the ~300-line guideline.

## Verdict

final_verdict: follow-up-recommended

The single Low finding was a documentation inconsistency, resolved in this
branch by correcting the plan. No follow-up issue is required — the item is
closed. WI-1 ships.
