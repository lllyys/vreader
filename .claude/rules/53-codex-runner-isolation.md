# 53 — Codex Runner Isolation (no more stdin-wedge ghosts)

## The failure

`codex exec "<prompt>"` passes the prompt as an argument but **also reads
stdin**. In a non-tty shell — every `run_in_background` Bash, every cron-driven
agent session — stdin never reaches EOF, so Codex prints

```
Reading additional input from stdin...
```

and **blocks forever at 0% CPU**. The process is a ghost: alive in `ps`, no
output, no completion, no failure. Observed 2026-06-01: one such ghost lingered
**4h20m**, and a freshly-launched audit wedged the same way the moment it ran in
a backgrounded shell.

This is the same class as:
- **Rule 52** — the wedged `xcodebuild test` (0% CPU, lingers for hours).
- **Rule 49** — the `pgrep -f` waiter that watches a class of work, not an
  instance.

A long-runner with no liveness signal and no timeout.

## Aggravator (what made it invisible)

Redirecting the backgrounded Codex's stdout to a side `/tmp` file
(`codex exec … > /tmp/audit.txt`) instead of letting it flow to the task-output
file. The task-output file then looked empty/dead, so the harness's own
liveness display and completion notification had nothing to show — the wedge was
invisible until someone ran `ps`.

## Hard rules

1. **Never call raw `codex exec` inside a backgrounded Bash.** Use
   **`scripts/run-codex.sh`** (closes stdin, enforces a wall-clock watchdog on
   the exact pid, prints one unambiguous `RUN-CODEX RESULT:` line) **or**
   cc-suite's own `--background` runner (it has job tracking + a completion
   signal). Both isolate stdin; a hand-rolled `codex exec` does not.
2. **If you must call `codex exec` directly, close stdin: `< /dev/null`.** With
   immediate EOF, Codex runs normally — it does not need stdin when the prompt
   is an argument. This is the single load-bearing fix.
3. **Do not redirect a backgrounded long-runner's stdout to a side file.** Let
   it land in the task-output file so the harness's liveness + completion
   notification work and a wedge is visible.
4. **Diagnose "is it hung?" by PROCESS, not the output file** (rule 52's lesson,
   applied to Codex):

   ```bash
   ps -Ao pid=,%cpu=,etime=,comm= | grep -i '[c]odex'
   ```

   A `codex` binary at **0% CPU with growing elapsed and no output growth** =
   wedged. Kill it and re-run through the wrapper:

   ```bash
   pkill -9 -f "openai/codex.*/codex"
   ```

5. **Before ending a turn, confirm no live Codex ghost:** `pgrep -x codex`
   (NOT `pgrep -f codex` — `-f` matches your own grep line). Zero = clean.

## Quick reference

```bash
# Bounded, stdin-isolated Codex audit (default gpt-5.4 / medium / 300s):
scripts/run-codex.sh -o /tmp/audit.txt "Audit these files: …"

# Longer budget for a big review:
CODEX_TIMEOUT_SECS=600 scripts/run-codex.sh -m gpt-5.5 -e high "…"
```

## Relationship to other rules

- **Rule 49 (background shells):** the wrapper's watchdog waits on the exact pid
  and is cancelled when Codex finishes first — it never re-arms on a future run.
- **Rule 52 (test/sim isolation):** same ghost-class; same process-not-output
  diagnosis. `run-codex.sh` is to `codex exec` what `run-tests.sh` is to
  `xcodebuild test` — the watchdog that turns an indefinite hang into a bounded,
  self-terminating run with one unambiguous result line.
