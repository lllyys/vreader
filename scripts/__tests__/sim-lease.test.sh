#!/usr/bin/env bash
# Feature #130 WI-3 — contract tests for scripts/sim-lease.sh. Discovery and
# boot are injected via env (no real simctl, no sim boots); leases in a temp
# root.
#
# Run: bash scripts/__tests__/sim-lease.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$HERE/../sim-lease.sh"
fails=0
TMP="$(mktemp -d)" || { echo "FATAL: mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

if [ ! -f "$CLI" ]; then echo "FAIL — $CLI does not exist"; echo "1 FAILURE(S)"; exit 1; fi

# fake simctl JSON: three available iPhone sims, one booted 17 Pro
DISCOVER="$TMP/discover.sh"
cat > "$DISCOVER" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[
 {"udid":"AAAAAAAA-0000-0000-0000-000000000001","name":"iPhone 17 Pro","state":"Booted","isAvailable":true},
 {"udid":"BBBBBBBB-0000-0000-0000-000000000002","name":"iPhone 17","state":"Shutdown","isAvailable":true},
 {"udid":"CCCCCCCC-0000-0000-0000-000000000003","name":"iPhone 17e","state":"Shutdown","isAvailable":true}
]}}
JSON
EOF
chmod +x "$DISCOVER"
BOOTLOG="$TMP/boots"
BOOT="$TMP/boot.sh"; printf '#!/usr/bin/env bash\necho "$1" >> "%s"\n' "$BOOTLOG" > "$BOOT"; chmod +x "$BOOT"

run() { env LOCK_OWNER_PID=$$ SIM_LEASE_LOCK_ROOT="$TMP/locks" SIM_LEASE_STATE_DIR="$TMP/state" \
        SIM_LEASE_DISCOVER_CMD="$DISCOVER" SIM_LEASE_BOOT_CMD="$BOOT" bash "$CLI" "$@" 2>&1; }

echo "== sim-lease.sh contract =="

# 1. verify lease resolves to the booted iPhone 17 Pro and persists the choice
OUT="$(run acquire verify)"; RC=$?
V_UDID="$(grep -oE '[A-F0-9-]{36}' <<<"$OUT" | head -1)"
if [ "$RC" -eq 0 ] && [ "$V_UDID" = "AAAAAAAA-0000-0000-0000-000000000001" ]; then ok "verify → booted 17 Pro"; else fail "verify acquire (rc=$RC): $OUT"; fi
if grep -q "$V_UDID" "$TMP/state/verify-udid" 2>/dev/null; then ok "verify choice persisted"; else fail "verify-udid not persisted"; fi

# 2. second verify lease while held → exit 2 (only 1 verify)
OUT="$(run acquire verify)"; RC=$?
if [ "$RC" -eq 2 ]; then ok "verify capacity 1 enforced"; else fail "verify cap (rc=$RC): $OUT"; fi

# 3. test leases never get the verify UDID; two allowed, third blocks
T1="$(run acquire test | grep -oE '[A-F0-9-]{36}' | head -1)"
T2="$(run acquire test | grep -oE '[A-F0-9-]{36}' | head -1)"
if [ -n "$T1" ] && [ -n "$T2" ] && [ "$T1" != "$T2" ] && [ "$T1" != "$V_UDID" ] && [ "$T2" != "$V_UDID" ]; then
    ok "two test leases, distinct, never the verify UDID"
else fail "test leases: T1=$T1 T2=$T2 V=$V_UDID"; fi
OUT="$(run acquire test)"; RC=$?
if [ "$RC" -eq 2 ]; then ok "test capacity 2 enforced"; else fail "test cap (rc=$RC): $OUT"; fi

# 4. shutdown sims got boot requests (the two test UDIDs were Shutdown)
BOOTS=$(sort -u "$BOOTLOG" 2>/dev/null | wc -l | tr -d ' ')
if [ "$BOOTS" -ge 2 ]; then ok "shutdown test sims boot-requested ($BOOTS)"; else fail "boots=$BOOTS want ≥2"; fi

# 5. status shows three held; releases bring it to zero
OUT="$(run status)"
HELD=$(grep -c "held" <<<"$OUT" || true)
if [ "$HELD" -eq 3 ]; then ok "status shows 3 held"; else fail "status held=$HELD: $OUT"; fi
run release "$T1" >/dev/null; run release "$T2" >/dev/null; run release "$V_UDID" >/dev/null
OUT="$(run status)"
if ! grep -q "held" <<<"$OUT"; then ok "all released → zero held"; else fail "leases left: $OUT"; fi

# 6. VERIFY_UDID env override wins over discovery
OUT="$(env LOCK_OWNER_PID=$$ VERIFY_UDID="BBBBBBBB-0000-0000-0000-000000000002" SIM_LEASE_LOCK_ROOT="$TMP/locks" SIM_LEASE_STATE_DIR="$TMP/state" SIM_LEASE_DISCOVER_CMD="$DISCOVER" SIM_LEASE_BOOT_CMD="$BOOT" bash "$CLI" acquire verify 2>&1)"
if grep -q "BBBBBBBB-0000-0000-0000-000000000002" <<<"$OUT"; then ok "VERIFY_UDID override wins"; else fail "override: $OUT"; fi
env LOCK_OWNER_PID=$$ SIM_LEASE_LOCK_ROOT="$TMP/locks" SIM_LEASE_STATE_DIR="$TMP/state" SIM_LEASE_DISCOVER_CMD="$DISCOVER" SIM_LEASE_BOOT_CMD="$BOOT" bash "$CLI" release "BBBBBBBB-0000-0000-0000-000000000002" >/dev/null 2>&1

# 7. no available sims → error exit 1 (not a hang)
EMPTY="$TMP/empty.sh"; printf '#!/usr/bin/env bash\necho "{\\"devices\\":{}}"\n' > "$EMPTY"; chmod +x "$EMPTY"
OUT="$(env LOCK_OWNER_PID=$$ SIM_LEASE_LOCK_ROOT="$TMP/locks2" SIM_LEASE_STATE_DIR="$TMP/state2" SIM_LEASE_DISCOVER_CMD="$EMPTY" SIM_LEASE_BOOT_CMD="$BOOT" bash "$CLI" acquire test 2>&1)"; RC=$?
if [ "$RC" -eq 1 ]; then ok "no available sims → exit 1"; else fail "empty pool (rc=$RC): $OUT"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
