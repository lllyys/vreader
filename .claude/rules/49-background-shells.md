# 49 — Background Shells

Rules for launching and waiting on long-running shell commands inside cron-driven Claude Code sessions. Bad practice here produces "ghost" background shells that linger in the UI for hours, get re-armed by unrelated later commands, and confuse the cron operator.

## Origin incident

On 2026-05-10 a single session left two `run_in_background` poll loops alive for 3+ hours. The pattern:

```bash
# Launched as run_in_background after kicking off a long xcodebuild test:
until ! pgrep -f "xcodebuild test" >/dev/null 2>&1; do sleep 5; done

# And in another tab:
while pgrep -f "xcodebuild test" >/dev/null 2>&1; do sleep 10; done
echo "---done---"
tail -50 /private/tmp/.../<launch>.output
```

The waiters keyed on the predicate `pgrep -f "xcodebuild test"` — not on the specific test process. The original test finished cleanly at 19:39, but every subsequent `xcodebuild test` later in the session (a bug-fix test gate at 21:32, the device-verify build at 22:00) re-triggered the predicate. The loops never exited, and Claude's task UI showed them as "running" while OS-level `ps` showed nothing.

Codex thread `019e1243` post-mortem identified the primary fault as the broad predicate (waiter watched a class of work, not the instance), with redundancy as an enabling secondary fault.

## Hard rules

1. **Do not start a second background task to wait on a first background task.** `Bash(run_in_background: true)` already emits a completion notification (`<task-notification>`) when the launched command finishes. Add nothing on top.
2. **Never use `pgrep -f` against a generic command name as a gate.** `pgrep -f "xcodebuild test"` matches the class, not the instance. A later run of the same tool will resurrect the predicate.
3. **Wait on identity, not likeness.** If you must wait outside of the system's native completion channel, key the wait to an exact handle:
   - exact PID (`wait $!`, `kill -0 $PID`)
   - exact output-file sentinel (`grep -q "TEST SUCCEEDED" $LOG`)
   - exact done-marker file (`[ -f $TASK_DONE ]`)
   - exact tool-provided task id
4. **One async job = one owner = one completion channel.** If you launch a background test, do not also poll for it. Pick one.
5. **Avoid zero-output background waiters.** They are indistinguishable from hung jobs in the UI and produce no debugging trail. If you have nothing to write, you have nothing to launch.
6. **A waiter must be tied to one run only.** It must be impossible for a future invocation of the same tool to re-arm a previous waiter.

## When you genuinely need to wait

In priority order:

### Best — rely on the system's native completion event

```bash
# Launch with run_in_background: true. Do nothing else.
# Continue with other work in the conversation; you will be notified
# when the task finishes.
```

### If shell-based waiting is required, wait on the exact PID

```bash
xcodebuild test ... &
pid=$!
wait "$pid"
echo "---done---"
tail -50 "$LOG"
```

### If you only have a PID later, poll on identity

```bash
while kill -0 "$PID" 2>/dev/null; do sleep 5; done
echo "---done---"
```

### If you only have an output file, wait on a run-specific sentinel

```bash
until grep -q "TEST SUCCEEDED" "$LOG" 2>/dev/null; do sleep 5; done
# OR
until [ -f "$TASK_DONE" ]; do sleep 5; done
```

## Anti-patterns

| Anti-pattern | Why it's wrong | Right move |
|---|---|---|
| `until ! pgrep -f "xcodebuild test"; do sleep 5; done` | Matches a CLASS of work; future invocations re-arm the wait | `wait $!` or sentinel grep |
| `Bash(run_in_background: true)` + polling shell on top | Doubles the state to manage; native completion notification already covers it | Drop the polling shell entirely |
| Background shell with no stdout/stderr writes | Indistinguishable from hung; UI display ambiguity | Either don't launch or have it `echo` heartbeats |
| Polling on `ps aux \| grep <toolname>` | Same class-vs-instance problem as `pgrep -f` | Use exact PID via `kill -0` |
| Long-running shell from session A polled into session B's runtime | Crosses session boundaries; cron iterations get conflated | Each cron fire is a fresh session — don't persist waiters across them |

## Cron-specific implications

vreader's cron prompts (`.claude/cron-prompts/{verify,bugfix,watchdog}.md`) fire as fresh agent sessions. A background shell from a prior session can outlive that session's logical end (until the OS reaps it) and still appear in the operator's UI. To avoid this:

- A cron iteration must end with no `run_in_background` shells still tracked. Before the iteration's terminal `echo "$(date) <kind> ENDED <outcome>"`, ensure: any test gates have completed (the gate is foreground or its native notification arrived), no `run_in_background` shells were launched solely as waiters, no `pgrep`-based polling loops remain queued.
- If a long test gate IS in flight, prefer one of these closures:
  - `xcodebuild test ... 2>&1 | tail -25` foreground in the iteration's terminal step (slow but unambiguous), OR
  - `run_in_background: true` with a completion-notification-driven follow-up (the next user prompt or cron fire picks up the result), NOT a polling shell.

## Quick check before ending an iteration

Run mentally: "Did I launch any `run_in_background` shells in this iteration that aren't either (a) finished with a `<task-notification>` already received, or (b) explicitly intended to outlive the iteration?" If neither, the iteration's clean. If it's (b), document why in the cron log line so future operators don't assume it's a leak.
