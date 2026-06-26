---
branch: feat/feature-122-wi-1-stats-schema
threadId: 019f0405-f122wi1
rounds: 1
final_verdict: ship-as-is
date: 2026-06-27
---

# Feature #122 WI-1 — Codex audit (reading-stats schema + DAO + clocks)

Files: `data/Entities.kt` (`DailyReadingEntity`), `data/Daos.kt` (`ReadingStatsDao`),
`data/VReaderDatabase.kt` (v3 + `MIGRATION_2_3`), `stats/clock/Clocks.kt`; tests `ReadingStatsDaoTest`
(6), `VReaderDatabaseMigrationTest` (1→3 chain + updated 1→2 step), `DateClockTest` (9).

## Round 1 — clean (no blocking issues), 1 Low (fixed)

Codex verified (against the generated `VReaderDatabase_Impl`):
- **Migration DDL is byte-exact** to Room's generated v3 schema for `daily_reading` (column order
  `date,bookKey,minutes`; `TEXT/TEXT/INTEGER`; all `NOT NULL`; composite PK; index name
  `index_daily_reading_bookKey`) — structural validation will pass on a real device upgrade.
- **DAO transaction shape is valid** Room usage (abstract `@Dao` + `@Transaction` open method wrapped in
  `performInTransactionSuspending`); `INSERT OR IGNORE` + `UPDATE += ?` is minSdk-26-safe (no SQLite UPSERT).
- **Orphan-preserving** (no FK to `books`) + the `bookKey` index are correct.
- **Clock seam** cleanly separates monotonic elapsed time from wall/calendar bucketing;
  `splitByLocalDate` uses `atStartOfDay(zone)` — correct for DST-sized days + half-open contiguity.

| file | severity | issue | resolution |
|---|---|---|---|
| DateClockTest | Low | thinner than the plan's adversarial set (no DST fall-back, >2-day window, exact-midnight boundaries) | FIXED — added `dstFallBack_splitsAtLocalDayBoundary`, `multiDayWindow_contiguousSegmentsPerDay`, `exactMidnightBoundaries_noZeroLengthTrailingSegment` (now 9 clock tests) |

## Summary

No Critical/High/Medium. 1 Low fixed. 6 DAO + 2 migration + 9 clock tests green. **Verdict: ship-as-is.**
