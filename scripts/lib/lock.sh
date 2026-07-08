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
# Steal serialization (Gate-4 audit, thread 019f4237…, R1+R2 Highs): a naive
# check-then-`rm -rf` steal lets two contenders both classify the lock as
# stale — the slower one then deletes the winner's FRESH lock and mutual
# exclusion breaks (empirically reproduced: 2 winners in 4/5 race rounds).
# Constructions, in order of the invariant they protect:
#   1. NO non-holder ever removes anything. All lock-dir removal happens
#      under the steal mutex (<lock-dir>.steal.d); the steal mutex itself is
#      NEVER reaped inline (that would re-open the same race one level down —
#      R2 High 2). A stealer crashing inside its ~0.3s critical section
#      wedges that lock until the single sweep actor (sweep-ghosts.sh)
#      reaps the dead-owner .steal.d; acquire meanwhile fails fast (exit 2)
#      with a pointer.
#   2. The owner record is PUBLISHED ATOMICALLY (tmp + mv), so a present
#      `owner` file is always complete (R2 High 1: the pid= line used to
#      land before start= was computed, and that live-pid/no-start state
#      read as stealable). A MISSING owner file inside an existing lock dir
#      is a mid-publish acquirer → grace re-read before stale judgment.
#   3. A record with a live pid and NO start= line (hand-made/corrupt — the
#      lib can no longer produce it) is conservatively LIVE, never stolen;
#      only a PRESENT-but-mismatched start (PID reuse) is stealable.

_lock_pid_start() {
    ps -p "$1" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//'
}

# 0 iff the lock dir's owner must be treated as alive (never stolen):
# pid alive + matching start, or pid alive + no start recorded (construction 3).
_lock_owner_live_matching() {
    local rec_pid rec_start
    rec_pid="$(sed -n 's/^pid=//p' "$1/owner" 2>/dev/null)"
    [ -n "$rec_pid" ] || return 1
    kill -0 "$rec_pid" 2>/dev/null || return 1
    if ! grep -q '^start=' "$1/owner" 2>/dev/null; then
        return 0   # live pid, corrupt/partial record → conservative: live
    fi
    rec_start="$(sed -n 's/^start=//p' "$1/owner" 2>/dev/null)"
    [ "$(_lock_pid_start "$rec_pid")" = "$rec_start" ]
}

_lock_publish_owner() {  # $1=dir $2=pid — atomic: a present owner file is complete
    local tmp="$1/owner.tmp.$$"
    {
        echo "pid=$2"
        echo "start=$(_lock_pid_start "$2")"
        echo "host=$(hostname -s 2>/dev/null || echo unknown)"
        echo "created=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } > "$tmp" && mv -f "$tmp" "$1/owner"
}

lock_acquire() {
    local dir="$1"
    local pid="${LOCK_OWNER_PID:-$$}"
    local steal="$dir.steal.d"
    local tries=0
    while [ "$tries" -lt 20 ]; do
        tries=$((tries + 1))
        if mkdir "$dir" 2>/dev/null; then
            _lock_publish_owner "$dir" "$pid"
            return 0
        fi
        if _lock_owner_live_matching "$dir"; then
            return 2   # live matching owner — never stolen
        fi
        # Candidate-stale (dead pid / reused pid / missing record). Serialize
        # the steal: exactly one contender may remove the lock dir, and only
        # after RE-validating staleness while holding the steal mutex.
        if mkdir "$steal" 2>/dev/null; then
            _lock_publish_owner "$steal" "$$"
            if [ -d "$dir" ] && ! _lock_owner_live_matching "$dir"; then
                if [ ! -f "$dir/owner" ]; then
                    # Mid-publish acquirer (mkdir done, owner not yet moved
                    # into place). Grace re-read before judging.
                    sleep 0.2
                fi
                if [ -d "$dir" ] && ! _lock_owner_live_matching "$dir"; then
                    echo "[lock] stealing stale lock $dir (recorded pid=$(sed -n 's/^pid=//p' "$dir/owner" 2>/dev/null || echo none))" >&2
                    rm -rf "$dir"
                fi
            fi
            rm -rf "$steal"
        else
            # Another stealer holds the mutex. NEVER reap it here (R2 High 2)
            # — if its holder crashed, sweep-ghosts.sh is the single reaper.
            local spid
            spid="$(sed -n 's/^pid=//p' "$steal/owner" 2>/dev/null)"
            if [ -n "$spid" ] && ! kill -0 "$spid" 2>/dev/null; then
                echo "[lock] $steal held by dead pid $spid — blocked until sweep-ghosts reaps it" >&2
                return 2
            fi
            sleep 0.05
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
