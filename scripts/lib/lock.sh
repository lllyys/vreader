#!/usr/bin/env bash
# lib/lock.sh — the ONE mkdir-atomic lock helper (feature #130 WI-1).
#
# Purpose: every #130 lock/lease primitive (reserve-id.sh, agent-lock.sh,
# sim-lease.sh) builds on this file so the repo has exactly one staleness
# implementation. macOS ships no flock(1); an atomic `mkdir` is the one
# portable mutual-exclusion primitive, so a lock IS a directory.
#
# API (source this file):
#   lock_acquire <lock-dir>   -> 0 acquired | 2 held by a live matching owner
#   lock_release <lock-dir>   -> 0 released | 3 not the owner
#
# Owner record (<lock-dir>/owner): pid=, start=, host=, created=.
# LOCK_OWNER_PID overrides the recorded pid (callers recording a child
# process as the holder; tests).
#
# Staleness contract (plan v5 "Lock model", binding):
#   steal ONLY when the recorded pid is dead OR its current start-time
#   mismatches the record (PID reuse). A live matching owner is NEVER
#   stolen, regardless of the record's age — no heartbeat-TTL stealing.
#   Long-held locks are sweep-ghosts.sh's to REPORT, never this file's to
#   break.

_lock_pid_start() {
    ps -p "$1" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//'
}

lock_acquire() {
    local dir="$1"
    local pid="${LOCK_OWNER_PID:-$$}"
    local tries=0
    while [ "$tries" -lt 3 ]; do
        if mkdir "$dir" 2>/dev/null; then
            {
                echo "pid=$pid"
                echo "start=$(_lock_pid_start "$pid")"
                echo "host=$(hostname -s 2>/dev/null || echo unknown)"
                echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            } > "$dir/owner"
            return 0
        fi
        local rec_pid rec_start
        rec_pid="$(sed -n 's/^pid=//p' "$dir/owner" 2>/dev/null)"
        rec_start="$(sed -n 's/^start=//p' "$dir/owner" 2>/dev/null)"
        if [ -n "$rec_pid" ] && kill -0 "$rec_pid" 2>/dev/null; then
            if [ "$(_lock_pid_start "$rec_pid")" = "$rec_start" ]; then
                return 2   # live matching owner — never stolen
            fi
        fi
        # Dead pid, reused pid, or torn owner record → stale. Steal and retry;
        # a concurrent stealer may win the re-mkdir, hence the loop.
        echo "[lock] stealing stale lock $dir (recorded pid=${rec_pid:-none})" >&2
        rm -rf "$dir"
        tries=$((tries + 1))
    done
    return 2
}

lock_release() {
    local dir="$1"
    local pid="${LOCK_OWNER_PID:-$$}"
    local rec_pid
    rec_pid="$(sed -n 's/^pid=//p' "$dir/owner" 2>/dev/null)"
    if [ "$rec_pid" != "$pid" ]; then
        return 3
    fi
    rm -rf "$dir"
}
