#!/usr/bin/env bash
# Purpose: detect — and with --kill, reap — "ghost" background processes
# left behind by agent sessions. A ghost is a process from a known leak
# class sitting at ~0% CPU past an age threshold: it produces nothing,
# never exits, and survives the session that spawned it.
#
# Known ghost classes (each has a rule + origin incident):
#   - `tail -f <file>`            rule 49/52 — detached output-file waiters
#                                  (origin: a 31-day tail found 2026-06-13)
#   - `log stream`                rule 49 — detached side-channel captures
#                                  (origin: ~3h simctl log stream, 2026-06-11)
#   - `codex` / `codex exec`      rule 53 — stdin-wedge (origin: 4h20m ghost,
#                                  2026-06-01)
#   - `xcodebuild test|build`     rule 52 — sim contention / wedged daemon
#                                  (recurring; watchdogged by run-tests.sh)
#
# NOT flagged: SWBBuildService (Xcode's resident build daemon — alive and
# idle between builds by design), idb_companion (persistent sim bridge),
# and anything younger than the threshold or actually using CPU.
#
# Usage:
#   scripts/sweep-ghosts.sh           # report only
#   scripts/sweep-ghosts.sh --kill    # report + TERM the ghosts
#   THRESHOLD_MIN=30 scripts/sweep-ghosts.sh
#
# Exit codes: 0 = clean (or killed), 1 = ghosts found (report-only mode).
# Final line is always one of:
#   SWEEP-GHOSTS RESULT: CLEAN
#   SWEEP-GHOSTS RESULT: FOUND <n>
#   SWEEP-GHOSTS RESULT: KILLED <n>

set -euo pipefail

THRESHOLD_MIN="${THRESHOLD_MIN:-120}"
KILL=0
[[ "${1:-}" == "--kill" ]] && KILL=1

# pid | etime | %cpu | command  for the ghost classes, older than the
# threshold and idle (<1% CPU). etime formats: MM:SS, HH:MM:SS, DD-HH:MM:SS.
#
# Classes flagged (all excluding the sweeper's own ps/ugrep pipeline and the
# resident SWBBuildService/idb_companion daemons):
#   - tail -f / log stream / codex / xcodebuild (test|build) — excludes bare
#     grep/awk so the sweeper's diagnostic greps don't self-match.
#   - waiter loop `until/while … do sleep N; done` — the rule-49 anti-pattern
#     (a run_in_background shell polling a task-output file). These DO contain
#     grep -q/-c markers, so the grep exclusion must not apply to them.
#     Origin: a `do sleep 25` waiter looped 3d18h before the 2026-06-15 sweep.
ghosts=$(ps -Ao pid=,etime=,pcpu=,command= | awk -v thr="$THRESHOLD_MIN" '
    {
        cmd = ""
        for (i = 4; i <= NF; i++) cmd = cmd (i > 4 ? " " : "") $i
    }
    cmd ~ /(ps -Ao|ugrep|sweep-ghosts|idb_companion|SWBBuildService)/ { next }
    {
        otherClass = (cmd !~ /( grep | awk )/) && \
            (cmd ~ /tail -f/ || cmd ~ /log stream/ || \
             cmd ~ /(^|\/)codex( |$)/ || cmd ~ /xcodebuild (test|build)/)
        waiterClass = (cmd ~ /(until|while) .*do sleep [0-9]/)
    }
    otherClass || waiterClass {
        days = 0; hms = $2
        if (split($2, d, "-") == 2) { days = d[1]; hms = d[2] }
        n = split(hms, t, ":")
        mins = days * 1440
        if (n == 3)      mins += t[1] * 60 + t[2]
        else if (n == 2) mins += t[1]
        if (mins >= thr && $3 + 0 < 1.0)
            printf "%s\t%s\t%s%%\t%s\n", $1, $2, $3, cmd
    }')

if [[ -z "$ghosts" ]]; then
    echo "SWEEP-GHOSTS RESULT: CLEAN"
    exit 0
fi

echo "PID	ELAPSED	CPU	COMMAND"
echo "$ghosts"
count=$(printf '%s\n' "$ghosts" | wc -l | tr -d ' ')

if [[ "$KILL" -eq 1 ]]; then
    printf '%s\n' "$ghosts" | cut -f1 | xargs kill 2>/dev/null || true
    echo "SWEEP-GHOSTS RESULT: KILLED $count"
    exit 0
fi

echo "SWEEP-GHOSTS RESULT: FOUND $count (re-run with --kill to reap)"
exit 1
