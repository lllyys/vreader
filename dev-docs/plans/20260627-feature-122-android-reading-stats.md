# Feature #122 — Android reading-stats

**Status:** Gate 1 (plan), v2 (Gate-2 audit round 1 applied). Part of the #110 Android Phase-3
capability-parity driver. Implements the reading-stats design
(`dev-docs/designs/vreader-fidelity-v1/project/vreader-stats-android.jsx`, needs-design #1800 closed):
an in-reader session-time surface + a stats dashboard.

## Problem

iOS shows cumulative + per-session reading time and per-book stats (#101). Android tracks nothing.
This adds a reading-time tracking layer (Room) + the two designed surfaces, TXT reader first.

## Surface area (new, under `android/app/.../stats/` + a Room table + DI + a TxtReader hook)

- **`data/Entities.kt` — `DailyReadingEntity`** (`@Entity tableName="daily_reading"`, PK
  `(date, bookKey)`, **`@Index("bookKey")`**): `date: String` (`yyyy-MM-dd`, LOCAL), `bookKey: String`,
  `minutes: Int`. **No `ForeignKey`** — stats for a since-deleted book are PRESERVED as orphans (they
  still count toward window totals; the per-book table joins live titles and simply omits orphans). +
  a Room **migration 2→3** (additive `CREATE TABLE daily_reading(date TEXT, bookKey TEXT, minutes
  INTEGER NOT NULL, PRIMARY KEY(date, bookKey))` + the bookKey index). Bump `@Database version = 3`,
  add `DailyReadingEntity` to `entities`, add `readingStatsDao()`, append `MIGRATION_2_3` to
  `ALL_MIGRATIONS`.
- **`data/Daos.kt` — `ReadingStatsDao`** (WI-1, primitives only — NO aggregate policy): a **portable,
  minSdk-26-safe** increment (NOT SQLite UPSERT, which isn't reliable on API 26/27, and `@Upsert`
  can't increment): a `@Transaction addMinutes(date, bookKey, delta)` = `INSERT OR IGNORE` a zero row
  then `UPDATE daily_reading SET minutes = minutes + :delta WHERE date=:date AND bookKey=:bookKey`.
  Read primitives: `observeRowsSince(date): Flow<List<DailyReadingEntity>>`, `rowsSince(date)`,
  `allRows()`, `activeDatesSince(date): List<String>` (DISTINCT dates, descending). The aggregate
  POLICY (window totals, per-day chart, per-book totals, streak) lives in the repository (WI-2), not
  the DAO.
- **`stats/clock/` — dual clock seam** (WI-1): `interface ElapsedClock { fun nowMillis(): Long }`
  (production = `SystemClock.elapsedRealtime` — MONOTONIC, immune to wall-clock jumps; used ONLY for
  durations) and `interface DateClock { fun today(): String; fun nowEpochMillis(): Long;
  fun localDate(epochMillis): String; fun splitByLocalDate(startInclusiveMs, endExclusiveMs):
  List<DateSegment> }` where `DateSegment(date: String, startMs: Long, endMs: Long)` is half-open and
  computed from the zone's local start-of-day via `ZoneRules` (so a DST-shortened/lengthened day and an
  exact-midnight boundary allocate correctly). Production = `Clock.systemDefaultZone()` +
  `ZoneId.systemDefault()`, `yyyy-MM-dd`. Injected so tests drive 23:59→00:02, DST, and zone cases
  deterministically. **`nowEpochMillis()` is the wall seam `start()`/`flush()` use to stamp the
  accounted window** (paired with the monotonic delta — see the tracker).
- **`stats/ReadingStatsRepository.kt`** (WI-2 — aggregate policy) — over the DAO + `LibraryRepository`:
  `recordMinutes(bookKey, date, delta)`; `dashboard(window: StatsWindow): Flow<DashboardData>` where
  `DashboardData(windowMinutes, streakDays, dailyAvgMinutes, daily14: List<DayMinutes>,
  perBook: List<BookStat>)`. **Streak is WINDOW-INDEPENDENT** = a real consecutive-local-day count
  ending today (or yesterday if today is 0), computed over **ALL active dates** (`activeDatesSince` with
  a far-past floor, or a dedicated all-dates query) — selecting the 7-day window must NOT cap a 30-day
  streak at 7. Only `windowMinutes`/`daily14`/`perBook` are window-scoped. `dailyAvgMinutes` = windowMinutes ÷
  active-or-elapsed days. `perBook` joins live library titles (orphans excluded from the table). The
  hero's third design stat ("Finished") is **OMITTED in v1** — Android has no completion contract
  (`BookEntity` has no finished flag; inferring from positions is false across formats). The hero
  shows Streak + Daily-avg; a "Finished" count is a #110 follow-on (needs a completion schema). The
  `Hl`/`Nt` per-book columns render as designed but show `0` until #1801 (annotations).
- **`stats/ReadingTimeTracker.kt`** (WI-2 — **idempotent state machine**, process-singleton in the
  container) — accumulates IN-READER reading time:
  - `start(bookKey)`: if a different book is active, flush it first; sets `activeBook=bookKey`,
    `lastAccountedElapsed = elapsed.nowMillis()`, `lastAccountedWall = dateClock.nowEpochMillis()`,
    `sessionStartElapsed = lastAccountedElapsed`, `carryMillis = 0`. Idempotent for the same book (no-op).
  - `flush()` / `stop()`: `delta = elapsed.nowMillis() - lastAccountedElapsed` (monotonic). If
    `delta > maxIdleMillis` (a backgrounded/idle gap) **bank 0** for the gap. Otherwise the accounted
    wall window is `[lastAccountedWall, lastAccountedWall + delta)`; **carry sub-minute remainder so no
    time is ever dropped**: `total = carryMillis + delta`, `wholeMinutes = total / 60000`,
    `carryMillis = total % 60000`. Allocate `wholeMinutes` across local dates via
    `dateClock.splitByLocalDate(window)` PROPORTIONALLY to each segment's share of the window (a
    midnight crossing splits its whole-minutes between the two days). Then ALWAYS advance
    `lastAccountedElapsed = elapsed.nowMillis()` and `lastAccountedWall += delta` (idle-clamped to 0)
    so a restart/repeat can NEVER replay; the un-banked remainder lives in `carryMillis`, carried to the
    next flush (handles `59s+2s`, jittered periodic flushes, `23:59:30→00:00:30`). `stop()` flushes then
    clears `activeBook` (idempotent — a second stop is a no-op). A periodic `flush()` runs every
    `flushIntervalMillis` while open.
  - `sessionSeconds: StateFlow<Long>` = `(elapsed.nowMillis() - sessionStartElapsed)/1000`, ticked for
    the live pill (not persisted).
- **`stats/StatsViewModel.kt`** (WI-2) — (a) in-reader: `sessionSeconds` (from the tracker) +
  `bookTotalMinutes` + a `timeLeftMinutes` from a TXT progress fraction × estimated total + a wpm pace;
  (b) dashboard: `StateFlow<DashboardUiState>` for the selected `StatsWindow`, switchable.
- **`reader/TxtProgress.kt`** (WI-2 helper, pure) — TXT has chunks not chapters, and no progress model:
  `fraction(firstVisibleChunkOffset, textLength): Float` = `offset / textLength`. The detail card shows
  **"Left in book"** only (no "Left in chapter" for TXT — no chapter index). Tested for empty/one-chunk/
  huge-CJK/EOF.
- **UI (Compose, WI-3, per the design):**
  - `stats/InReaderTimePill.kt` — the glassy auto-fading session pill + the time **detail card**
    (session · total · left-in-book · pace). `VReaderColors`/`VReaderFonts`.
  - `stats/StatsDashboard.kt` — `TimeWindowBar` + the hour **hero** (Streak + Daily-avg, or the no-data
    nudge) + the 14-day `DailyChart` (today tinted) + the `PerBookTable` (Time + Hl/Nt[=0] with a
    per-row time hairline). Backup `AppSheet`/`SettingsCard`/`BackupTokens`. **No-data keeps every
    module's frame.**
- **DI (`VReaderApp.kt`/`AppContainer`)** — `readingStatsDao` accessor on the DB; a process-singleton
  `ReadingStatsRepository` + `ReadingTimeTracker` in the container (the tracker survives the reader VM,
  so rotation doesn't reset a session).
- **`reader/TxtReaderActivity.kt` hook (WI-4)** — `tracker.start(bookKey)` when the reader is RESUMED,
  `tracker.stop()` on PAUSED but **gated by `!isChangingConfigurations`** (rotation keeps the session,
  the #121 precedent); the session pill overlays top-right (auto-fades), the detail card from the
  progress area. `start`/`stop` are idempotent so a rotation/dispose can't double-flush.

### Files OUT of scope

- **"Finished" hero stat** — no Android completion contract; v1 shows Streak + Daily-avg (a #110
  follow-on adds a completion schema). **Highlight/Note per-book counts** — `0` until #1801.
  **EPUB/PDF/MD session tracking** — the tracker is format-agnostic; only TXT is hooked. **A Library/
  Settings dashboard entry point** — no Settings hub exists (as with backup/AI/OPDS/TTS); the dashboard
  is verified via instrumented tests + a DEBUG-reachable hook. **Per-second precision** — whole-minute
  per-day/book buckets. **"Left in chapter" for TXT** — no chapter index.

## Prior art / precedent

- iOS `#101`. Android Room (`VReaderDatabase` v2 + the verified `Migration` append pattern — confirmed),
  `LibraryRepository.observeLibrary()` (titles — confirmed), backup form vocab + `BackupTokens` +
  `VReaderColors`/`VReaderFonts` (confirmed), the #121 lifecycle-hook + `!isChangingConfigurations`
  precedent. **Rejected**: SQLite UPSERT (not minSdk-26 safe), per-second tracking, FK-cascade on stats
  (orphans preserved), inferring "finished" from positions.

## Work items

| WI | Scope | Tier | PR size |
| --- | --- | --- | --- |
| WI-1 | `DailyReadingEntity` + migration 2→3 (+ index) + `ReadingStatsDao` (portable txn increment + read primitives) + the dual `ElapsedClock`/`DateClock` seam. Robolectric in-memory-Room DAO tests + a 2→3 AND 1→3 migration test. | foundational | medium |
| WI-2 | `ReadingStatsRepository` (window totals / per-day / per-book / **real streak** / daily-avg, title join, orphan handling) + `ReadingTimeTracker` (idempotent monotonic state machine, idle-cap, midnight-split, flush) + `TxtProgress` + `StatsViewModel`. JVM/Robolectric tests w/ injected clocks + fake repo/DAO. | behavioral | medium |
| WI-3 | `InReaderTimePill` + `StatsDashboard` (window bar/hero/chart/table, populated + no-data). Instrumented Compose tests. | behavioral | medium |
| WI-4 | DI wiring + TxtReader hook (start/stop the tracker gated by `!isChangingConfigurations` + the pill) + connected acceptance (record minutes across days/books → the dashboard reflects them via real Room) → VERIFIED. | behavioral (final) | medium |

## Test catalogue

- `ReadingStatsDaoTest` (Robolectric, in-memory Room): `addMinutes` INSERT-then-increment (UPSERT-free),
  concurrent increments under transaction, `rowsSince`/`activeDatesSince`, empty.
- `VReaderDatabaseMigration2to3Test` + `Migration1to3Test` (Robolectric): `daily_reading` created +
  usable through `ALL_MIGRATIONS`; seeded books/positions survive 1→3.
- `ReadingTimeTrackerTest` (JVM, injected ElapsedClock + DateClock): accumulate → minutes, **idle gap
  banks 0**, **midnight split** (23:59→00:02 → two days), flush on stop + interval, **no replay** on
  restart, book-switch flushes the old book, idempotent double-stop, the live `sessionSeconds`,
  monotonic clock immune to a wall-clock jump.
- `ReadingStatsRepositoryTest` (Robolectric): window-since math, per-day chart, per-book join (+ orphan
  excluded), **streak** (consecutive, today-zero-yesterday-active, gap, all-empty, window boundary),
  daily-avg.
- `StatsViewModelTest` (Robolectric + fake repo): dashboard per window + switch, no-data, in-reader
  session/total/left/pace; `TxtProgressTest` (empty/one-chunk/huge-CJK/EOF).
- Compose: `InReaderTimePillTest`, `StatsDashboardTest` (populated + no-data).
- `ReadingStatsConnectedTest` (androidTest, real Room): record minutes for two books across two days →
  `DashboardData` reflects totals/per-book/daily-chart/streak.

## Risks + mitigations

- **minSdk-26 SQLite** → portable `INSERT OR IGNORE` + `UPDATE +delta` in a `@Transaction`; tested on
  Robolectric (covers the API-26 SQLite era).
- **Idle/background banking** → monotonic-clock delta, per-tick idle clamp, flush + clear on PAUSE
  (gated by `!isChangingConfigurations`).
- **Wall-clock jumps / midnight / zones** → MONOTONIC `ElapsedClock` for durations, separate `DateClock`
  for local-date buckets, explicit day-boundary split; deterministic via injection.
- **Double-flush on rotation/dispose** → idempotent `start`/`stop` keyed on `activeBook` +
  `lastAccountedElapsed`; the tracker is a container singleton (survives the VM); rotation gated out.
- **Migration** → additive `CREATE TABLE` + index, no transform; 2→3 AND 1→3 tests.

## Backward compat

Additive: a new `daily_reading` table (migration 2→3, no transform, index on bookKey), a new `stats/`
package + container singletons, a new in-reader pill in the TXT reader. No effect on existing books/
positions/readers. Pre-existing installs get the empty table → the designed no-data dashboard.

## Audit history (Gate 2)

- **Round 1** (Codex, v1 → v2): 1 Critical + 9 High + 6 Medium + 2 Low. Fixed: portable txn
  increment (not minSdk-26-unsafe UPSERT); dropped the unbacked "Finished" hero stat (no completion
  contract) + `Hl`/`Nt`=0 until #1801; idempotent monotonic-clock tracker state machine (no
  double-count/replay); midnight-split across local dates; separate MONOTONIC `ElapsedClock` +
  calendar `DateClock`; a REAL consecutive-day streak (not active-days); DI wiring (DAO accessor +
  container singletons); `@Index("bookKey")` + orphan-preserving (no FK cascade); 2→3 AND 1→3 migration
  tests; a `TxtProgress` provider + "Left in book" only (no TXT chapter); WI-1 limited to DAO/schema
  primitives with aggregate policy moved to WI-2. Confirmed assumptions: DB v2 + ALL_MIGRATIONS,
  Entities, LibraryRepository titles, backup vocab + tokens all exist.
- **Round 2** (Codex, v2 → v3): 2 High + 2 Medium. Fixed: added `DateClock.nowEpochMillis()` (the wall
  seam `start`/`flush` need); **carry a sub-minute `carryMillis` remainder** so no time is dropped on
  flush (handles `59s+2s`, jitter, `23:59:30→00:00:30`); replaced the under-specified day-boundary API
  with a precise half-open `splitByLocalDate(startIncl,endExcl) → List<DateSegment>` from `ZoneRules`
  local start-of-day (DST + exact-midnight correct); **streak is window-independent** (all active dates,
  not `activeDatesSince(window)`). Tests added: `59s+2s` carry, jittered flush, `23:59:30→00:00:30`
  split, DST day, streak-30-while-7-day-window. Confirmed: `SystemClock.elapsedRealtime`
  monotonic+includes-sleep, Room `@Transaction` concrete-method, `@Index`, additive migrations.
