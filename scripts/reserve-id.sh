#!/usr/bin/env bash
# reserve-id.sh {bug|feature} — print the next tracker row ID, atomically.
#
# Feature #130 WI-1. Closes the documented cron ID race ("assign next
# available ID" was read-max-then-append with no reservation; two concurrent
# triage sessions minted the same row ID). ID = max(max ID in the tracker,
# persisted counter) + handout; the counter and lock live under docs/
# as LOCAL STATE (gitignored — a manually added row is reconciled because
# the tracker max always competes).
#
# Env overrides (tests): RESERVE_TRACKER_FILE, RESERVE_STATE_DIR,
# RESERVE_LOCK_DIR.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/lock.sh
source "$HERE/lib/lock.sh"

KIND="${1:-}"
case "$KIND" in
    bug)     DEF_TRACKER="docs/bugs.md" ;;
    feature) DEF_TRACKER="docs/features.md" ;;
    *) echo "usage: reserve-id.sh {bug|feature}" >&2; exit 64 ;;
esac

ROOT="$(cd "$HERE/.." && pwd)"
TRACKER="${RESERVE_TRACKER_FILE:-$ROOT/$DEF_TRACKER}"
STATE_DIR="${RESERVE_STATE_DIR:-$ROOT/docs/.id-counters}"
LOCK_BASE="${RESERVE_LOCK_DIR:-$ROOT/docs/.id-locks}"
mkdir -p "$STATE_DIR" "$LOCK_BASE"
LOCK="$LOCK_BASE/$KIND.lock.d"

# Bounded spin for the id-reserve leaf lock (held for milliseconds by design;
# per the #130 lock order it must never be requested while holding
# tracker-write, so contention here is only other reservations).
acquired=0
for _ in $(seq 1 100); do
    if lock_acquire "$LOCK" 2>/dev/null; then acquired=1; break; fi
    sleep 0.1
done
if [ "$acquired" -ne 1 ]; then
    echo "reserve-id: id lock busy after 10s ($LOCK)" >&2
    exit 2
fi
trap 'lock_release "$LOCK" 2>/dev/null || true' EXIT

COUNTER="$STATE_DIR/$KIND.next"
max_in_tracker="$(grep -oE '^\| *[0-9]+ *\|' "$TRACKER" 2>/dev/null | tr -d ' |' | sort -n | tail -1 || true)"
max_in_tracker="${max_in_tracker:-0}"
counter=0
if [ -f "$COUNTER" ]; then
    counter="$(cat "$COUNTER" 2>/dev/null || echo 0)"
    case "$counter" in (*[!0-9]*|'') counter=0 ;; esac
fi

next=$(( max_in_tracker + 1 ))
if [ "$counter" -gt "$next" ]; then next="$counter"; fi
echo $(( next + 1 )) > "$COUNTER"
echo "$next"
