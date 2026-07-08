#!/usr/bin/env bash
# Feature #130 WI-1 — contract tests for scripts/lib/lock.sh, the ONE
# mkdir-atomic lock helper every #130 lock/lease primitive builds on.
# Staleness contract (plan v5 "Lock model"): steal ONLY on dead pid or
# pid-reuse (start-time mismatch); a live matching owner is NEVER stolen,
# regardless of age (no heartbeat-TTL stealing).
#
# Run: bash scripts/__tests__/lock.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../lib/lock.sh"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

if [ ! -f "$LIB" ]; then
    echo "FAIL — $LIB does not exist"
    echo "1 FAILURE(S)"; exit 1
fi
# shellcheck source=../lib/lock.sh
source "$LIB"

echo "== lib/lock.sh contract =="

# 1. basic acquire/release round-trip
D="$TMP/basic.lock.d"
if lock_acquire "$D"; then ok "acquire succeeds on a free lock"; else fail "acquire on free lock"; fi
if [ -f "$D/owner" ] && grep -q "pid=$$" "$D/owner"; then ok "owner record carries our pid"; else fail "owner record missing/wrong"; fi
if lock_release "$D"; then ok "owner can release"; else fail "owner release"; fi
if [ ! -d "$D" ]; then ok "release removes the lock dir"; else fail "lock dir survived release"; fi

# 2. contention: a lock held by a LIVE process is not re-acquirable (exit 2)
D="$TMP/held.lock.d"
sleep 60 & HOLDER=$!
LOCK_OWNER_PID=$HOLDER lock_acquire "$D" || fail "setup: acquire as holder"
if lock_acquire "$D"; then fail "second acquire succeeded on a live-held lock"; else
    rc=$?
    if [ "$rc" -eq 2 ]; then ok "live-held lock → exit 2 (blocked)"; else fail "live-held lock → exit $rc, want 2"; fi
fi

# 3. live matching owner is NEVER stolen, even when the record is OLD (no TTL steal)
python3 - "$D/owner" <<'EOF'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'created=.*', 'created=2020-01-01T00:00:00Z', s)
open(p,"w").write(s)
EOF
if lock_acquire "$D"; then fail "STOLE a live matching owner's old lock (TTL steal is forbidden)"; else ok "old-but-live owner never stolen"; fi
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null

# 4. dead-pid steal: holder died → acquire steals
if lock_acquire "$D" 2>/dev/null; then ok "dead-pid lock is stolen"; else fail "dead-pid lock not stolen"; fi
lock_release "$D" || true

# 5. PID-reuse steal: pid is alive but start-time mismatches the record
D="$TMP/reuse.lock.d"
sleep 60 & IMPOSTOR=$!
LOCK_OWNER_PID=$IMPOSTOR lock_acquire "$D" || fail "setup: acquire as impostor-pid"
python3 - "$D/owner" <<'EOF'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'start=.*', 'start=Wed Jan  1 00:00:00 2020', s)
open(p,"w").write(s)
EOF
if lock_acquire "$D" 2>/dev/null; then ok "pid-reuse (start-time mismatch) is stolen"; else fail "pid-reuse lock not stolen"; fi
lock_release "$D" || true
kill "$IMPOSTOR" 2>/dev/null; wait "$IMPOSTOR" 2>/dev/null

# 6. release by a non-owner refuses (exit 3), lock survives
D="$TMP/notmine.lock.d"
sleep 60 & OTHER=$!
LOCK_OWNER_PID=$OTHER lock_acquire "$D" || fail "setup: acquire as other"
if lock_release "$D" 2>/dev/null; then fail "non-owner release succeeded"; else
    rc=$?
    if [ "$rc" -eq 3 ] && [ -d "$D" ]; then ok "non-owner release refused (exit 3), lock intact"; else fail "non-owner release rc=$rc dir=$([ -d "$D" ] && echo yes || echo no)"; fi
fi
kill "$OTHER" 2>/dev/null; wait "$OTHER" 2>/dev/null

# 7. atomicity: N parallel acquires on one fresh lock → exactly 1 winner
D="$TMP/race.lock.d"
WINS="$TMP/wins"; : > "$WINS"
for i in $(seq 1 8); do
    ( source "$LIB"; if lock_acquire "$D" 2>/dev/null; then echo "$i" >> "$WINS"; fi ) &
done
wait
WINNERS=$(wc -l < "$WINS" | tr -d ' ')
if [ "$WINNERS" -eq 1 ]; then ok "8 parallel acquires → exactly 1 winner"; else fail "8 parallel acquires → $WINNERS winners"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
