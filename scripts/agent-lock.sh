#!/usr/bin/env bash
# agent-lock.sh — named mutex CLI over scripts/lib/lock.sh (feature #130 WI-3).
#
# The lock-order participants (rule 55): `dispatch` (global orchestrator/
# integration lock — acquired by the /dispatch skill itself, NEVER
# pre-acquired by cron prompts), `tracker-write` (short shared-surface edit
# lock), `cron-<kind>` (per-cron reentry locks). Staleness semantics live in
# lib/lock.sh (steal only on dead pid / PID reuse; live matching owners never
# stolen; sweep-ghosts.sh is the single reaper for dead steal mutexes).
#
# Usage:
#   agent-lock.sh acquire <name>   -> 0 ACQUIRED | 2 BLOCKED
#   agent-lock.sh release <name>   -> 0 RELEASED | 3 NOT-OWNER
#   agent-lock.sh status           -> one "held:" line per held lock
# Env: AGENT_LOCK_ROOT (default <repo>/.claude/locks), LOCK_OWNER_PID.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/lock.sh
source "$HERE/lib/lock.sh"
ROOT="$(cd "$HERE/.." && pwd)"
LOCK_ROOT="${AGENT_LOCK_ROOT:-$ROOT/.claude/locks}"

# The recorded owner defaults to our GRANDPARENT: this CLI's own pid dies
# with the call, and even $PPID is a transient per-call shell in the
# orchestrator (claude-session → zsh-per-call → CLI). The grandparent is the
# long-lived session process, so the lock survives across the session's tool
# calls and goes stale when the session dies — exactly the intent. Callers
# needing a different owner (a lane's child process) pass LOCK_OWNER_PID.
_gp="$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ' || true)"
if [ -z "${_gp:-}" ] || [ "${_gp:-0}" -le 1 ]; then _gp="$PPID"; fi
export LOCK_OWNER_PID="${LOCK_OWNER_PID:-$_gp}"

cmd="${1:-}"
name="${2:-}"

valid_name() {
    printf '%s' "$1" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$'
}

case "$cmd" in
    acquire)
        valid_name "$name" || { echo "agent-lock: invalid lock name '$name'" >&2; exit 64; }
        mkdir -p "$LOCK_ROOT"
        if lock_acquire "$LOCK_ROOT/$name.lock.d"; then
            echo "AGENT-LOCK RESULT: ACQUIRED $name"
            exit 0
        fi
        echo "AGENT-LOCK RESULT: BLOCKED $name (held by a live owner)"
        exit 2
        ;;
    release)
        valid_name "$name" || { echo "agent-lock: invalid lock name '$name'" >&2; exit 64; }
        if lock_release "$LOCK_ROOT/$name.lock.d"; then
            echo "AGENT-LOCK RESULT: RELEASED $name"
            exit 0
        fi
        echo "AGENT-LOCK RESULT: NOT-OWNER $name (lock left intact)" >&2
        exit 3
        ;;
    status)
        found=0
        for d in "$LOCK_ROOT"/*.lock.d; do
            [ -e "$d" ] || continue
            found=1
            n="$(basename "$d" .lock.d)"
            pid="$(sed -n 's/^pid=//p' "$d/owner" 2>/dev/null || true)"
            echo "held: $n pid=${pid:-unknown}"
        done
        [ "$found" -eq 0 ] && echo "AGENT-LOCK STATUS: clean"
        exit 0
        ;;
    *)
        echo "usage: agent-lock.sh {acquire|release} <name> | status" >&2
        exit 64
        ;;
esac
