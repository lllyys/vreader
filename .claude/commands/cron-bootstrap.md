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
     - verify cron — `23 * * * *` — `.claude/cron-prompts/verify.md`
     - bugfix cron — `47 */2 * * *` — `.claude/cron-prompts/bugfix.md`
     - watchdog cron — `49 4 * * *` — `.claude/cron-prompts/watchdog.md`
     - feature cron — `31 */3 * * *` — `.claude/cron-prompts/feature.md`
   - Call `CronCreate` with `cron`, `recurring: true`, and the
     prompt loaded verbatim from the file.

4. Confirm with `CronList` again. Report the 4 IDs to the user.

5. **Do NOT pass `durable: true`** — this runtime doesn't honor it
   (it silently treats every job as session-only). Documenting it
   here so future iterations don't waste a round trip.

## Why off-minute schedules

Each cron's minute is staggered (`:23`, `:31`, `:47`, `:49`) to keep
fleet-wide load distributed and to avoid hot-minute coordination
pile-ups (every user who asks "every hour" hits :00 by default; we
deliberately don't). When editing a schedule, keep the off-minute
property — don't snap to `:00` or `:30`.

## Output

A short confirmation:

```
Re-bootstrapped 4 crons:
  <id-1> — verify, every hour at :23
  <id-2> — bugfix, every 2h at :47
  <id-3> — watchdog, daily at 04:49
  <id-4> — feature, every 3h at :31
```

If any cron was already present and skipped, say so explicitly.
