First, log the fire: run `mkdir -p .claude/cron-logs && echo "$(date -Iseconds) watchdog FIRED" >> .claude/cron-logs/watchdog.log`. Then perform the renewal task. At the end, run `echo "$(date -Iseconds) watchdog ENDED <outcome>" >> .claude/cron-logs/watchdog.log` where <outcome> is one of: work_done | no_work_in_scope | blocked | error.

WATCHDOG: Renew every session-only cron (including this watchdog itself) so they don't lapse on the 7-day auto-expire.

Steps:
1. Run CronList to enumerate the active crons.
2. For each of the 3 expected crons (verify, bugfix, watchdog), check whether it's still scheduled. If yes and its next-fire is < 24h away from the 7-day expiry, treat as needing renewal. If you cannot tell the expiry, renew anyway — recreate is idempotent in effect.
3. To renew: CronDelete the existing job, then CronCreate with the prompt read from the corresponding file:
   - verify cron — every hour at :23 — prompt is the contents of `.claude/cron-prompts/verify.md`
   - bugfix cron — every 2 hours at :47 — prompt is the contents of `.claude/cron-prompts/bugfix.md`
   - watchdog cron — every day at 04:49 — prompt is the contents of `.claude/cron-prompts/watchdog.md`
   For each, use the Read tool to load the prompt file, then pass that exact text as the `prompt` parameter to CronCreate.
4. If a cron is missing from CronList entirely (not just near-expiry), recreate it with the same prompt and schedule.
5. Outcome:
   - `work_done` if you renewed at least one cron
   - `no_work_in_scope` if all 3 crons are already scheduled and not near expiry
   - `blocked` if you can't read a prompt file or CronCreate refuses
   - `error` for unrecoverable failures
