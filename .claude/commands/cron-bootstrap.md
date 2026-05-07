---
description: "Recreate the 3 session-only crons (verify, bugfix, watchdog) from `.claude/cron-prompts/`. Use after a Claude Code restart since the `durable` flag isn't honored by this runtime."
---

# /cron-bootstrap

Re-bootstrap the verification + bug-fix + watchdog crons from the
checked-in prompt files. Idempotent: if a cron is already present
with the same prompt + schedule, it stays.

## Steps

1. Run `CronList` to see what's currently scheduled.

2. For each of the 3 expected crons, check whether it's present.
   If a cron with the same schedule + same first-line of prompt
   exists, skip it. Otherwise, recreate.

3. Recreation pattern — for each missing cron:
   - Read the prompt from the corresponding file:
     - verify cron — `23 * * * *` — `.claude/cron-prompts/verify.md`
     - bugfix cron — `47 */2 * * *` — `.claude/cron-prompts/bugfix.md`
     - watchdog cron — `49 4 * * *` — `.claude/cron-prompts/watchdog.md`
   - Call `CronCreate` with `cron`, `recurring: true`, and the
     prompt loaded verbatim from the file.

4. Confirm with `CronList` again. Report the 3 IDs to the user.

5. **Do NOT pass `durable: true`** — this runtime doesn't honor it
   (it silently treats every job as session-only). Documenting it
   here so future iterations don't waste a round trip.

## Output

A short confirmation:

```
Re-bootstrapped 3 crons:
  <id-1> — verify, every hour at :23
  <id-2> — bugfix, every 2h at :47
  <id-3> — watchdog, daily at 04:49
```

If any cron was already present and skipped, say so explicitly.
