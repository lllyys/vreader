#!/usr/bin/env bash
# Feature #130 WI-3 — sweep-ghosts.sh lock-reaping contract (the single
# reaper, rule 55): stale locks reaped via the lock helper's own serialized
# steal (revalidate-at-removal — never a snapshot rm), live locks and live
# steal mutexes untouched, dead steal mutexes cleared.
#
# Run: bash scripts/__tests__/sweep-locks.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWEEP="$HERE/../sweep-ghosts.sh"
fails=0
TMP="$(mktemp -d)" || { echo "FATAL: mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"; kill "$HOLDER" 2>/dev/null' EXIT
HOLDER=""

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

LOCKS="$TMP/locks"; mkdir -p "$LOCKS"

# stale lock (dead pid)
mkdir "$LOCKS/stale.lock.d"
printf 'pid=99999999\nstart=Wed Jan  1 00:00:00 2020\n' > "$LOCKS/stale.lock.d/owner"
# live lock (a real holder)
sleep 60 & HOLDER=$!
mkdir "$LOCKS/live.lock.d"
{ echo "pid=$HOLDER"; echo "start=$(ps -p "$HOLDER" -o lstart= | sed 's/^ *//;s/ *$//')"; echo "created=2026-01-01T00:00:00Z"; } > "$LOCKS/live.lock.d/owner"
# dead steal mutex + live steal mutex
mkdir "$LOCKS/x.lock.d.steal.d"
printf 'pid=99999998\nstart=Wed Jan  1 00:00:00 2020\n' > "$LOCKS/x.lock.d.steal.d/owner"
mkdir "$LOCKS/y.lock.d.steal.d"
{ echo "pid=$HOLDER"; echo "start=$(ps -p "$HOLDER" -o lstart= | sed 's/^ *//;s/ *$//')"; } > "$LOCKS/y.lock.d.steal.d/owner"

echo "== sweep-ghosts.sh lock reaping =="

OUT="$(env AGENT_LOCK_ROOT="$LOCKS" THRESHOLD_MIN=99999 bash "$SWEEP" 2>&1)"; RC=$?
if [ "$RC" -eq 1 ] && grep -q "STALE LOCKS" <<<"$OUT"; then ok "report mode flags stale locks (exit 1)"; else fail "report (rc=$RC): $OUT"; fi
if [ -d "$LOCKS/stale.lock.d" ]; then ok "report mode reaps nothing"; else fail "report mode removed a lock"; fi

OUT="$(env AGENT_LOCK_ROOT="$LOCKS" THRESHOLD_MIN=99999 bash "$SWEEP" --kill 2>&1)"; RC=$?
if [ ! -d "$LOCKS/stale.lock.d" ]; then ok "--kill reaps the dead-owner lock"; else fail "stale lock survived --kill"; fi
if [ -d "$LOCKS/live.lock.d" ]; then ok "live lock untouched"; else fail "live lock reaped"; fi
if [ ! -d "$LOCKS/x.lock.d.steal.d" ]; then ok "dead steal mutex reaped"; else fail "dead steal mutex survived"; fi
if [ -d "$LOCKS/y.lock.d.steal.d" ]; then ok "live steal mutex untouched"; else fail "live steal mutex reaped"; fi

# long-held LIVE lock is reported, never reaped, even at threshold 0
OUT="$(env AGENT_LOCK_ROOT="$LOCKS" THRESHOLD_MIN=0 bash "$SWEEP" 2>&1)"
if grep -q "LONG-HELD" <<<"$OUT" && [ -d "$LOCKS/live.lock.d" ]; then ok "long-held live lock: reported only"; else fail "long-held handling: $OUT"; fi

kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null; HOLDER=""

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
