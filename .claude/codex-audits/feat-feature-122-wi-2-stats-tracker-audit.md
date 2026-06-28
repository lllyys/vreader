---
branch: feat/feature-122-wi-2-stats-tracker
threadId: 019f0405-f122wi2
rounds: 2
final_verdict: ship-as-is
date: 2026-06-28
---

# Feature #122 WI-2 — Codex audit (reading-stats repository + tracker + VM)

Files: `stats/ReadingStatsRepository.kt`, `stats/ReadingTimeTracker.kt`, `reader/TxtProgress.kt`,
`stats/StatsViewModel.kt`, `stats/StatsUiState.kt`; tests `ReadingTimeTrackerTest` (7),
`ReadingStatsRepositoryTest` (7), `StatsViewModelTest` (3), `TxtProgressTest` (5).

## Round 1 — 1 High, 4 Medium, 1 Low (all fixed)

| severity | issue | resolution |
|---|---|---|
| High | scalar `carryMillis` lost its wall-date → a pre-midnight fragment could bank to the wrong day across flushes | FIXED — redesigned to a per-LOCAL-DATE carry map; `flushLocked` splits the window into date segments and banks whole minutes per date, keeping each date's remainder. Removed the largest-remainder allocation (no longer needed). Regression `carryCrossingMidnightAcrossTwoFlushes_banksToCorrectDay` |
| Medium | negative delta moved the accounted marks backward → replay on clock recovery | FIXED — `delta <= 0` returns BEFORE advancing (high-water preserved) |
| Medium | idle dropped carry vs the "no time dropped" claim | FIXED — documented: idle gap + new session/book clear the sub-minute carry (negligible, explicit) |
| Medium | window aggregates had no upper bound (future-dated rows counted) | FIXED — repo filters `date <= today` on all rows before aggregating |
| Medium | daily-avg divided by active days, not window days | FIXED — bounded windows divide by `window.days`; all-time by active days |
| Low | zero-duration segment could leave a remainder unrecorded | MOOT after the per-date-carry redesign (each segment banks its own floor; `splitByLocalDate` yields only positive segments) |

## Round 2 — 1 Medium (fixed)

| severity | issue | resolution |
|---|---|---|
| Medium | `bookTotalMinutes` (in-reader path) lacked the `date <= today` future bound the dashboard now has | FIXED — same `date <= today` filter |

Round 2 confirmed: per-date carry preserves midnight provenance across flushes; `delta <= 0` preserves
the high-water mark without replay; idle/new-session carry drops are explicit; bounded daily averages
use the intended denominators; the future-row filter keeps legitimate today rows.

## Summary

1 High + 4 Medium + 1 Low (R1) + 1 Medium (R2), all fixed. 22 JVM/Robolectric tests green. **Verdict: ship-as-is.**
