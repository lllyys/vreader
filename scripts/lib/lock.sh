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
#   lock_release <lock-dir>   -> 0 released | 3 not the owner / not provably yours
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
#
# Steal serialization (Gate-4 audit, thread 019f4237…, High): a naive
# check-then-`rm -rf` steal lets two contenders both classify the lock as
# stale — the slower one then deletes the winner's FRESH lock and mutual
# exclusion breaks (empirically reproduced: 2 winners in 4/5 race rounds).
# All removal therefore happens under a dedicated steal mutex
# (<lock-dir>.steal.d) with the staleness verdict RE-validated while holding
# it; a fresh-but-torn owner record (mkdir done, owner file not yet written)
# gets a grace re-read before it may be judged stale.

_lock_pid_start() {
    ps -p "$1" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//'
}

# 0 iff the lock dir has an owner record whose pid is alive AND whose
# start-time matches (i.e. the one case that must never be stolen).
_lock_owner_live_matching() {
    local rec_pid rec_start
    rec_pid="$(sed -n 's/^pid=//p' "$1/owner" 2>/dev/null)"
    rec_start="$(sed -n 's/^start=//p' "$1/owner" 2>/dev/null)"
    [ -n "$rec_pid" ] || return 1
    kill -0 "$rec_pid" 2>/dev/null || return 1
    [ "$(_lock_pid_start "$rec_pid")" = "$rec_start" ]
}

lock_acquire() {
    local dir="$1"
    local pid="${LOCK_OWNER_PID:-$$}"
    local steal="$dir.steal.d"
    local tries=0
    while [ "$tries" -lt 20 ]; do
        tries=$((tries + 1))
        if mkdir "$dir" 2>/dev/null; then
            {
                echo "pid=$pid"
                echo "start=$(_lock_pid_start "$pid")"
                echo "host=$(hostname -s 2>/dev/null || echo unknown)"
                echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            } > "$dir/owner"
            return 0
        fi
        if _lock_owner_live_matching "$dir"; then
            return 2   # live matching owner — never stolen
        fi
        # Candidate-stale (dead pid / reused pid / torn record). Serialize the
        # steal: exactly one contender may remove the dir, and only after
        # RE-validating staleness while holding the steal mutex.
        if mkdir "$steal" 2>/dev/null; then
            echo "pid=$$" > "$steal/owner"
            if [ -d "$dir" ] && ! _lock_owner_live_matching "$dir"; then
                if [ ! -s "$dir/owner" ]; then
                    # Torn record: a legitimate acquirer may be between its
                    # mkdir and its owner-write. Grace re-read before judging.
                    sleep 0.2
                fi
                if [ -d "$dir" ] && ! _lock_owner_live_matching "$dir"; then
                    echo "[lock] stealing stale lock $dir (recorded pid=$(sed -n 's/^pid=//p' "$dir/owner" 2>/dev/null || echo none))" >&2
                    rm -rf "$dir"
                fi
            fi
            rm -rf "$steal"
        else
            # Another stealer holds the mutex. Clear it only if ITS holder is
            # dead (crashed mid-steal); otherwise give it a moment.
            local spid
            spid="$(sed -n 's/^pid=//p' "$steal/owner" 2>/dev/null)"
            if [ -n "$spid" ] && ! kill -0 "$spid" 2>/dev/null; then
                rm -rf "$steal"
            else
                sleep 0.05
            fi
        fi
    done
    return 2
}

lock_release() {
    local dir="$1"
    local pid="${LOCK_OWNER_PID:-$$}"
    local rec_pid rec_start
    rec_pid="$(sed -n 's/^pid=//p' "$dir/owner" 2>/dev/null)"
    rec_start="$(sed -n 's/^start=//p' "$dir/owner" 2>/dev/null)"
    if [ "$rec_pid" != "$pid" ]; then
        return 3
    fi
    # PID match alone is not proof (Gate-4 Medium: PID reuse). If the pid is
    # alive its start-time must match the record; a DEAD recorded pid is
    # releasable (the owner is gone — this is how a parent reaps a lock it
    # recorded for an exited child via LOCK_OWNER_PID).
    if kill -0 "$rec_pid" 2>/dev/null && [ "$(_lock_pid_start "$rec_pid")" != "$rec_start" ]; then
        return 3
    fi
    rm -rf "$dir"
}
