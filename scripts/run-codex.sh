#!/usr/bin/env bash
# run-codex.sh — wrap `codex exec` with stdin isolation + a wall-clock watchdog
# so a wedged Codex self-terminates instead of lingering for hours at 0% CPU.
#
# THE GHOST THIS PREVENTS (2026-06-01): `codex exec "<prompt>"` passes the prompt
# as an arg but ALSO reads stdin. In a non-tty / `run_in_background` shell, stdin
# never reaches EOF, so Codex prints `Reading additional input from stdin...` and
# blocks FOREVER at 0% CPU — a ghost indistinguishable from a hang (one lingered
# 4h20m). Same class as the xcodebuild ghost (rule 52) and the `pgrep -f` waiter
# (rule 49): a long-runner with no liveness signal + no timeout.
#
# This wrapper:
#   1. Closes stdin (`< /dev/null`) so Codex never blocks on it.
#   2. Bounds the run with a watchdog on the EXACT pid (rule 49) — kills a wedge.
#   3. Prints ONE unambiguous final line: `RUN-CODEX RESULT: SUCCEEDED|FAILED|TIMEOUT`.
#
# Usage:
#   scripts/run-codex.sh [-m MODEL] [-e EFFORT] [-o OUTFILE] "<prompt>"
# Env:
#   CODEX_TIMEOUT_SECS  (default 300)
#
# Always invoke Codex through this wrapper (or cc-suite's own runner). Never call
# raw `codex exec` inside a backgrounded Bash — see rule 53.
set -uo pipefail

TIMEOUT_SECS="${CODEX_TIMEOUT_SECS:-300}"
MODEL="gpt-5.4"
EFFORT="medium"
OUT=""

while getopts "m:e:o:" opt; do
  case "$opt" in
    m) MODEL="$OPTARG" ;;
    e) EFFORT="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    *) echo "RUN-CODEX RESULT: FAILED (bad flag)"; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

PROMPT="${1:-}"
if [ -z "$PROMPT" ]; then
  echo "usage: run-codex.sh [-m MODEL] [-e EFFORT] [-o OUTFILE] \"<prompt>\"" >&2
  echo "RUN-CODEX RESULT: FAILED (no prompt)"
  exit 2
fi

OUT="${OUT:-$(mktemp -t run-codex.XXXXXX)}"

# Launch Codex with stdin CLOSED (the load-bearing fix) and output to $OUT.
codex exec --sandbox read-only -m "$MODEL" -c "model_reasoning_effort=$EFFORT" "$PROMPT" \
  < /dev/null > "$OUT" 2>&1 &
pid=$!

# Watchdog tied to THIS exact pid (rule 49 — identity, not likeness). If Codex
# is still alive after the budget, kill it and mark the wedge.
( sleep "$TIMEOUT_SECS"
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null
    echo "__RUN_CODEX_WATCHDOG_KILLED__" >> "$OUT"
  fi
) &
wd=$!

wait "$pid"
rc=$?
# Cancel the watchdog if Codex finished first (it never re-arms on a later run).
kill "$wd" 2>/dev/null
wait "$wd" 2>/dev/null

echo "----- codex output ($OUT) -----"
cat "$OUT"
echo "-------------------------------"

if grep -q "__RUN_CODEX_WATCHDOG_KILLED__" "$OUT"; then
  echo "RUN-CODEX RESULT: TIMEOUT (${TIMEOUT_SECS}s) — killed pid $pid"
  exit 124
elif [ "$rc" -eq 0 ]; then
  echo "RUN-CODEX RESULT: SUCCEEDED"
else
  echo "RUN-CODEX RESULT: FAILED (codex exit $rc)"
fi
exit "$rc"
