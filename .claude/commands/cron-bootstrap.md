---
description: "Recreate the 4 session-only crons (verify, bugfix, watchdog, feature) from `.claude/cron-prompts/`. Use after a Claude Code restart since the `durable` flag isn't honored by this runtime."
---

# /cron-bootstrap

Re-bootstrap the verification + bug-fix + watchdog + feature-implementation crons from the
checked-in prompt files. Idempotent: if a cron is already present
with the same prompt + schedule, it stays.

## Steps

1. Run `CronList` to see what's currently scheduled.

2. For each of the 4 expected crons, check whether it's present.
   If a cron with the same schedule + same first-line of prompt
   exists, skip it. Otherwise, recreate.

3. Recreation pattern — for each missing cron:
   - Read the prompt from the corresponding file:
     - verify cron — `9 * * * *` — `.claude/cron-prompts/verify.md`
     - bugfix cron — `39 * * * *` — `.claude/cron-prompts/bugfix.md`
     - watchdog cron — `54 4 * * *` — `.claude/cron-prompts/watchdog.md`
     - feature cron — `24 */2 * * *` — `.claude/cron-prompts/feature.md`
   - Call `CronCreate` with `cron`, `recurring: true`, and the
     prompt loaded verbatim from the file.

4. Confirm with `CronList` again. Report the 4 IDs to the user.

5. **Do NOT pass `durable: true`** — this runtime doesn't honor it
   (it silently treats every job as session-only). Documenting it
   here so future iterations don't waste a round trip.

## Why these schedules

Each cron's minute is evenly staggered across the hour at ~15-minute
intervals (`:09`, `:24`, `:39`, `:54`), keeping fleet-wide load
distributed and avoiding hot-minute coordination pile-ups (every user
who asks "every hour" hits :00 by default; we deliberately don't).

**Cadences** (2026-05-12 bump — verify + bugfix are hourly, feature
every 2h, watchdog daily). Verify and bugfix run hourly because both
are productive cadences (verify ticks ship evidence files; bugfix
ticks at least file/skip-note on the queue, and pick up real fixes
whenever the queue refreshes). Feature runs every 2h because each
tick can run a full 6-gate cycle that takes meaningful time. Watchdog
runs daily — it's renewal + ghost-shell sweep, not productive work.

When editing a schedule:
- Keep the ~15-minute spacing — don't bunch into adjacent minutes.
- Avoid `:00` and `:30` (fleet hot minutes).
- Put the most frequent crons (verify, bugfix — both hourly) on the
  even-15min slots so the gap between any two firings stays ≤ 30 min.

## Output

A short confirmation:

```
Re-bootstrapped 4 crons:
  <id-1> — verify, every hour at :09
  <id-2> — feature, every 2h at :24
  <id-3> — bugfix, every hour at :39
  <id-4> — watchdog, daily at 04:54
```

If any cron was already present and skipped, say so explicitly.
