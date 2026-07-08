#!/usr/bin/env bash
# Feature #130 WI-1 — contract tests for scripts/reserve-id.sh (atomic tracker
# row-ID allocation; closes the documented cron ID race). Uses fixture tracker
# files + a temp state dir via env overrides — never the real docs/.
#
# Run: bash scripts/__tests__/reserve-id.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESERVE="$HERE/../reserve-id.sh"
fails=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

if [ ! -x "$RESERVE" ] && [ ! -f "$RESERVE" ]; then
    echo "FAIL — $RESERVE does not exist"
    echo "1 FAILURE(S)"; exit 1
fi

mk_tracker() { # $1=path, rows given on stdin
    cat > "$1"
}

ENVV=(RESERVE_STATE_DIR="$TMP/state" RESERVE_LOCK_DIR="$TMP/locks")

echo "== reserve-id.sh contract =="

# 1. seeding from the tracker (no counter yet): max row 41 (mixed spacing incl. 3-digit style)
T="$TMP/bugs.md"
mk_tracker "$T" <<'EOF'
# fixture
| #  | Summary | Area | Severity | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| 7  | old | x | Low | FIXED | n |
| 41 | newer | x | Low | FIXED | n |
EOF
GOT=$(env "${ENVV[@]}" RESERVE_TRACKER_FILE="$T" bash "$RESERVE" bug)
if [ "$GOT" = "42" ]; then ok "seeds from tracker max (41→42)"; else fail "seed: got '$GOT', want 42"; fi

# 2. monotonic on repeat
GOT=$(env "${ENVV[@]}" RESERVE_TRACKER_FILE="$T" bash "$RESERVE" bug)
if [ "$GOT" = "43" ]; then ok "monotonic (→43)"; else fail "monotonic: got '$GOT', want 43"; fi

# 3. manual row beyond the counter wins: tracker gains | 50| (3-digit-style, no space)
printf '| 50| manual | x | Low | TODO | n |\n' >> "$T"
GOT=$(env "${ENVV[@]}" RESERVE_TRACKER_FILE="$T" bash "$RESERVE" bug)
if [ "$GOT" = "51" ]; then ok "manual row beyond counter (50→51)"; else fail "manual-row: got '$GOT', want 51"; fi

# 4. kinds are independent counters
F="$TMP/features.md"
mk_tracker "$F" <<'EOF'
| #  | Summary | Area | Priority | Status | Notes |
| 129| x | y | High | VERIFIED | n |
EOF
GOT=$(env "${ENVV[@]}" RESERVE_TRACKER_FILE="$F" bash "$RESERVE" feature)
if [ "$GOT" = "130" ]; then ok "feature kind independent (129→130)"; else fail "feature kind: got '$GOT', want 130"; fi

# 5. THE RACE: 10 parallel reservations → 10 unique IDs
OUT="$TMP/ids"; : > "$OUT"
for i in $(seq 1 10); do
    ( env "${ENVV[@]}" RESERVE_TRACKER_FILE="$T" bash "$RESERVE" bug >> "$OUT" ) &
done
wait
UNIQ=$(sort -n "$OUT" | uniq | wc -l | tr -d ' ')
TOTAL=$(wc -l < "$OUT" | tr -d ' ')
if [ "$TOTAL" = "10" ] && [ "$UNIQ" = "10" ]; then ok "10 parallel calls → 10 unique IDs"; else fail "race: $TOTAL calls, $UNIQ unique"; fi

# 6. unknown kind → usage error (exit non-zero, no output pollution)
if env "${ENVV[@]}" bash "$RESERVE" gadget >/dev/null 2>&1; then fail "unknown kind accepted"; else ok "unknown kind rejected"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
