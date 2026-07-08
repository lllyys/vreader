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
#   - `am instrument`             rule 52 Cause D — wedged Android instrumentation
#   - `adb … logcat`              rule 49 — detached logcat side-channel capture
#                                  (recurring; watchdogged by run-tests.sh)
#   - `python … http.server`      rule 49 — detached verification HTTP server left
#                                  by a round-trip harness (origin: two
#                                  run-opds-roundtrip.sh servers orphaned ~10h via
#                                  a subshell-pid trap, found 2026-06-23). No one
#                                  runs a persistent http.server here, so any past
#                                  the threshold is a leak.
#
# NOT flagged: SWBBuildService (Xcode's resident build daemon — alive and
# idle between builds by design), the Gradle daemon + a booted Android
# emulator (resident-by-design, rule 52 Cause D), idb_companion (persistent
# sim bridge),
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
    # Resident-by-design daemons are NEVER ghosts: Xcode SWBBuildService, the sim
    # bridge idb_companion, the Gradle daemon (alive + idle between builds — rule
    # 52 Cause D), and a booted Android emulator (qemu/emulator — like a booted
    # simulator). The sweep ps/ugrep pipeline is excluded too.
    cmd ~ /(ps -Ao|ugrep|sweep-ghosts|idb_companion|SWBBuildService|GradleDaemon|org\.gradle\.launcher\.daemon|qemu-system|emulator64|\/emulator |Codex\.app)/ { next }
    {
        otherClass = (cmd !~ /( grep | awk )/) && \
            (cmd ~ /tail -f/ || cmd ~ /log stream/ || \
             cmd ~ /(^|\/)codex( |$)/ || cmd ~ /xcodebuild (test|build)/ || \
             cmd ~ /am instrument/ || cmd ~ /adb .*logcat/ || \
             cmd ~ /http\.server/)
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

# ---- Feature #130 WI-3: stale locks/leases + orphaned lane worktrees ----
# This sweeper is THE single reaper for lock-state (rule 55): lock_acquire
# never removes a foreign steal mutex (that race broke mutual exclusion —
# Gate-4 finding), so a stealer that crashed mid-steal wedges its lock until
# this runs. Staleness = lib/lock.sh semantics (dead pid / PID-reuse); a
# LIVE matching owner is never reaped — long-held (>threshold) live locks
# are REPORTED for the operator only.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_ROOT="${AGENT_LOCK_ROOT:-$ROOT/.claude/locks}"
WT_ROOT="$ROOT/.claude/worktrees"
lock_stale=""
lock_longheld=""
if [[ -d "$LOCK_ROOT" ]] && source "$ROOT/scripts/lib/lock.sh" 2>/dev/null; then
    for d in "$LOCK_ROOT"/*.d; do
        [[ -e "$d" ]] || continue
        if _lock_owner_live_matching "$d"; then
            created="$(sed -n 's/^created=//p' "$d/owner" 2>/dev/null)"
            age_min="$(python3 -c "
import sys, datetime
try:
    t = datetime.datetime.strptime(sys.argv[1], '%Y-%m-%dT%H:%M:%SZ')
    print(int((datetime.datetime.utcnow() - t).total_seconds() // 60))
except Exception:
    print(0)" "$created" 2>/dev/null || echo 0)"
            if [[ "$age_min" -ge "$THRESHOLD_MIN" ]]; then
                lock_longheld+="$d (live owner, held ${age_min}m — REPORT ONLY, never auto-reaped)"$'\n'
            fi
        else
            lock_stale+="$d"$'\n'
        fi
    done
fi
wt_orphans=""
if [[ -d "$WT_ROOT" ]]; then
    now="$(date +%s)"
    for w in "$WT_ROOT"/*; do
        [[ -d "$w" ]] || continue
        mtime="$(stat -f %m "$w" 2>/dev/null || echo "$now")"
        age_min=$(( (now - mtime) / 60 ))
        if [[ "$age_min" -ge "$THRESHOLD_MIN" ]]; then
            wt_orphans+="$w (${age_min}m old)"$'\n'
        fi
    done
fi

lock_count=$(printf '%s' "$lock_stale" | grep -c . || true)
wt_count=$(printf '%s' "$wt_orphans" | grep -c . || true)
proc_count=0
[[ -n "$ghosts" ]] && proc_count=$(printf '%s\n' "$ghosts" | wc -l | tr -d ' ')

if [[ -n "$lock_longheld" ]]; then
    echo "LONG-HELD LOCKS (live owners — informational):"
    printf '%s' "$lock_longheld"
fi

if [[ "$proc_count" -eq 0 && "$lock_count" -eq 0 && "$wt_count" -eq 0 ]]; then
    echo "SWEEP-GHOSTS RESULT: CLEAN"
    exit 0
fi

if [[ "$proc_count" -gt 0 ]]; then
    echo "PID	ELAPSED	CPU	COMMAND"
    echo "$ghosts"
fi
if [[ "$lock_count" -gt 0 ]]; then
    echo "STALE LOCKS (dead/reused owner):"
    printf '%s' "$lock_stale"
fi
if [[ "$wt_count" -gt 0 ]]; then
    echo "ORPHANED LANE WORKTREES (>${THRESHOLD_MIN}m):"
    printf '%s' "$wt_orphans"
fi
count=$((proc_count + lock_count + wt_count))

if [[ "$KILL" -eq 1 ]]; then
    if [[ "$proc_count" -gt 0 ]]; then
        printf '%s\n' "$ghosts" | cut -f1 | xargs kill 2>/dev/null || true
    fi
    if [[ "$lock_count" -gt 0 ]]; then
        printf '%s' "$lock_stale" | while IFS= read -r d; do
            [[ -n "$d" ]] && rm -rf "$d"
        done
    fi
    if [[ "$wt_count" -gt 0 ]]; then
        printf '%s' "$wt_orphans" | while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            w="${line%% *}"
            bash "$ROOT/scripts/worktree-teardown.sh" "$(basename "$w")" --force 2>/dev/null \
                || echo "[sweep] worktree $w teardown failed — remove manually"
        done
    fi
    echo "SWEEP-GHOSTS RESULT: KILLED $count"
    exit 0
fi

echo "SWEEP-GHOSTS RESULT: FOUND $count (re-run with --kill to reap)"
exit 1
