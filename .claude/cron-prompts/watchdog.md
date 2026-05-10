First, log the fire: run `mkdir -p .claude/cron-logs && echo "$(date -Iseconds) watchdog FIRED" >> .claude/cron-logs/watchdog.log`. Then perform the renewal + sweep tasks. At the end, run `echo "$(date -Iseconds) watchdog ENDED <outcome>" >> .claude/cron-logs/watchdog.log` where <outcome> is one of: work_done | no_work_in_scope | blocked | error.

WATCHDOG: keep every session-only cron alive past the 7-day auto-expire AND sweep for rule-49 ghost background shells.

## Part 1 — Cron renewal

1. Run `CronList` to enumerate the active crons.

2. For each of the 4 expected crons (verify, bugfix, watchdog, feature), check whether it's still scheduled. If yes and its next-fire is < 24h away from the 7-day expiry, treat as needing renewal. If you cannot tell the expiry, renew anyway — recreate is idempotent in effect.

3. To renew: `CronDelete` the existing job, then `CronCreate` with the prompt read from the corresponding file:
   - verify cron — `23 * * * *` — `.claude/cron-prompts/verify.md`
   - bugfix cron — `47 */2 * * *` — `.claude/cron-prompts/bugfix.md`
   - watchdog cron — `49 4 * * *` — `.claude/cron-prompts/watchdog.md`
   - feature cron — `31 */3 * * *` — `.claude/cron-prompts/feature.md`
   For each, use the `Read` tool to load the prompt file, then pass that exact text as the `prompt` parameter to `CronCreate`.

4. If a cron is missing from `CronList` entirely (not just near-expiry), recreate it with the same prompt and schedule.

## Part 2 — Rule-49 ghost-shell sweep

`.claude/rules/49-background-shells.md` codifies the anti-patterns that produced the 2026-05-10 3-hour ghost-shell incident: `pgrep -f "<toolname>"` polling loops keyed on a class of work get re-armed by unrelated later invocations. The watchdog is the right place to sweep for these post-hoc.

5. Scan for orphan ghost-poll patterns:

   ```bash
   ps -eo pid,etime,command | grep -E "pgrep -f .xcodebuild|pgrep -f .simctl|while .*pgrep|until .*pgrep|until [^;]*sleep [0-9]+; *done|while [^;]*sleep [0-9]+; *done" | grep -v grep
   ```

   For each match capture: PID, ETIME (process age), full command.

6. Decision per match (use ETIME as the gate; format is `[[DD-]HH:]MM:SS`):
   - **ETIME < 10 minutes**: likely a legitimate in-flight wait. Skip silently.
   - **ETIME 10 minutes – 1 hour**: log as `suspicious` in `.claude/cron-logs/watchdog.log` (PID, command, age). Do NOT kill — the operator may be running a long test on purpose.
   - **ETIME > 1 hour**: log as `ghost` AND kill with `kill <pid>` (TERM, not KILL-9). If still alive after 5 s, escalate to `kill -9 <pid>`. Print every kill action to stdout so it surfaces in cron telemetry.

7. Also scan for stale `xcodebuild test` or `xcrun simctl` processes that have been running > 30 min — these can also become orphaned across sessions:

   ```bash
   ps -eo pid,etime,command | grep -E "xcodebuild test|xcrun simctl" | grep -v grep
   ```

   Same decision matrix as step 6 (skip < 10 min, suspicious 10–60 min, ghost > 1h).

## Part 3 — Outcome

8. Outcome:
   - `work_done` if you renewed at least one cron OR killed at least one ghost shell
   - `no_work_in_scope` if all 4 crons are scheduled, not near expiry, and no ghost shells were found
   - `blocked` if you can't read a prompt file or `CronCreate` refuses
   - `error` for unrecoverable failures (e.g., the sweep `ps` itself failed)

   In any case, log to `.claude/cron-logs/watchdog.log` the counts: `crons_renewed=N ghost_shells_killed=M suspicious_shells_logged=K`.
