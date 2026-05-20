---
branch: feat/58-wi-6b-custom-range-picker
threadId: 019e4560-c813-7c72-922e-4fffa3899099
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 Audit Log — feature #58 WI-6b (Custom range picker)

Branch: `feat/58-wi-6b-custom-range-picker`
Worktree: `/Users/ll/workspace/vreader/.claude/worktrees/agent-a18d173a21fa0a0d4`
Plan: `dev-docs/plans/20260519-feature-58-reading-dashboard.md` v4
Design bundle: `dev-docs/designs/vreader-fidelity-v1/project/stats-followups-artboards.jsx`

## Round 1 (thread 019e4555)

Verdict: `must-fix`. Two Medium findings.

| # | Sev | Finding | Fix label |
|---|---|---|---|
| 1 | Medium | `last365Days` still rolling 365d with `365d` label — plan said WI-6b is where this becomes calendar-YTD ("Year") | plan-alignment |
| 2 | Medium | Custom range stored as raw `Date` instants → timezone drift on reload | range-calendar-stability |

## Fixes (applied 2026-05-20)

### Fix 1 — `last365Days` → calendar-YTD ("Year")

- `ReadingStatsWindow.last365Days.label` `"365d"` → `"Year"` (case name retained for prefs stability).
- `dateInterval(now:calendar:)` for `.last365Days` now returns `startOfYear(now) ..< now`.
- Tests: removed `last365Days` from rolling-N-days parameterized arguments; added `yearWindowAnchorsAtJanuary1OfCurrentYear`, `yearWindowEndsBeforeStartForFirstDayOfYear`, `yearWindowExcludesSessionsBeforeJanuary1`; label assertion + `thousandSessionsAggregateCorrectly` rescoped.

### Fix 2 — Timezone-stable Custom range

- New `CalendarDay` value type (year/month/day triple, Equatable/Hashable/Codable/Comparable).
- `ReadingStatsCustomRange` now stores `startDay` + `endDay` as `CalendarDay`, NOT `Date`.
- `init(start: Date, end: Date, calendar: Calendar = .current)` captures day triples.
- `init(startDay:endDay:)` for direct day-triple construction.
- `startDate(calendar:)` / `endDate(calendar:)` for explicit-calendar materialization.
- `dateInterval(calendar:)` / `contains(_:calendar:)` / `dayCount(calendar:)` / `summaryLabel(calendar:)` all re-materialize from day triples — timezone-stable.
- `StatsCustomRangePickerState` materializes via `startDate(calendar:)` (was `range.start`).
- `StatsCustomRangePickerState.applyRange()` passes `calendar:` explicitly.
- `StatsCustomRangePicker.init` anchors via `startDate(calendar:)`.
- Tests: `range(y,m,d,...)` helper builds via day triples; new `rangePickedInUTCMeansSameDaysInTokyo` round-trip test; aggregator tests pass `calendar:` explicitly.

## Round 2 (thread 019e4560)

Verdict: **`ship-as-is`**.

- Both Medium findings RESOLVED.
- No new Critical/High/Medium issues.
- Coverage residual note (helper-test calendars still use `.current`) — not a blocker.

## Test status

All 115 WI-6b-related tests green:
- `ReadingStatsCustomRangeTests` (25)
- `StatsCustomRangePickerTests` (18)
- `StatsCustomRangeMonthGridTests` (2)
- `StatsTimeWindowBarTests` (14)
- `ReadingDashboardViewModelTests` (20)
- `ReadingDashboardViewTests` (10)
- `ReadingStatsAggregatorTests` (19)
- `ReadingStatsWindowIntervalTests` (10) — covers the new `last365Days` YTD semantic
