#!/usr/bin/env bash
# sim-lease.sh — purpose-tagged simulator UDID leases (feature #130 WI-3).
#
# Rule 52's test-vs-drive mutual exclusion, mechanized: a UDID lease is
# exclusive and purpose-tagged; `test` (≤2 concurrent, feeds TEST_UDID to
# scripts/run-tests.sh) and `verify` (1, the dedicated verification sim)
# can never share a UDID. Discovery is DYNAMIC (no hardcoded UDIDs/counts);
# a shutdown sim is booted on demand. Release paths per rule 55: every lane
# exit path releases its test lease; the verify flow releases before ENDED;
# `status` must show zero held at batch end.
#
# Usage:
#   sim-lease.sh acquire {test|verify}  -> 0 "SIM-LEASE RESULT: ACQUIRED <purpose> <udid>"
#                                          2 BUSY (capacity) | 1 ERROR (no sims)
#   sim-lease.sh release <udid>         -> 0 RELEASED | 3 NOT-OWNER
#   sim-lease.sh status                 -> one "held:" line per lease
# Env: SIM_LEASE_LOCK_ROOT (default <repo>/.claude/locks),
#      SIM_LEASE_STATE_DIR (default <repo>/.claude/state),
#      SIM_LEASE_DISCOVER_CMD (default `xcrun simctl list -j devices available`),
#      SIM_LEASE_BOOT_CMD (default `xcrun simctl boot`), VERIFY_UDID,
#      LOCK_OWNER_PID.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/lock.sh
source "$HERE/lib/lock.sh"
ROOT="$(cd "$HERE/.." && pwd)"
LOCK_ROOT="${SIM_LEASE_LOCK_ROOT:-$ROOT/.claude/locks}"
STATE_DIR="${SIM_LEASE_STATE_DIR:-$ROOT/.claude/state}"

# The recorded owner defaults to our GRANDPARENT (the long-lived session
# process — see agent-lock.sh for the full rationale); LOCK_OWNER_PID
# overrides for lane-child ownership.
_gp="$(ps -o ppid= -p "$PPID" 2>/dev/null | tr -d ' ' || true)"
if [ -z "${_gp:-}" ] || [ "${_gp:-0}" -le 1 ]; then _gp="$PPID"; fi
export LOCK_OWNER_PID="${LOCK_OWNER_PID:-$_gp}"
DEV_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

discover_json() {
    if [ -n "${SIM_LEASE_DISCOVER_CMD:-}" ]; then
        "$SIM_LEASE_DISCOVER_CMD"
    else
        DEVELOPER_DIR="$DEV_DIR" xcrun simctl list -j devices available
    fi
}

# emits "udid|name|state" per available device
list_devices() {
    discover_json | python3 -c '
import json, sys
d = json.load(sys.stdin)
for rt, devs in d.get("devices", {}).items():
    for dev in devs:
        if dev.get("isAvailable", False):
            print("%s|%s|%s" % (dev["udid"], dev["name"], dev["state"]))'
}

boot_sim() { # $1=udid
    if [ -n "${SIM_LEASE_BOOT_CMD:-}" ]; then
        "$SIM_LEASE_BOOT_CMD" "$1"
    else
        DEVELOPER_DIR="$DEV_DIR" xcrun simctl boot "$1" 2>/dev/null || true
    fi
}

lease_dir() { echo "$LOCK_ROOT/sim-$1.lock.d"; }

lease_purpose() { # $1=udid → recorded purpose ('' if not leased)
    cat "$(lease_dir "$1")/purpose" 2>/dev/null || true
}

# Count only LIVE leases (Gate-4 High: a dead/PID-reused stale lease must not
# occupy capacity — a stale verify lease would BUSY-block verify forever).
# Stale dirs are left for lock_acquire's steal path / sweep-ghosts to clear.
held_count() { # $1=purpose → number of LIVE leases with that purpose
    local n=0 d
    for d in "$LOCK_ROOT"/sim-*.lock.d; do
        [ -e "$d/purpose" ] || continue
        [ "$(cat "$d/purpose" 2>/dev/null)" = "$1" ] || continue
        if _lock_owner_live_matching "$d"; then n=$((n + 1)); fi
    done
    echo "$n"
}

# The capacity check + candidate selection + acquire + purpose write is a
# check-then-act sequence (Gate-4 High: three concurrent acquires can all
# observe <cap). The whole critical section is serialized under a select
# mutex (bounded spin — the section runs milliseconds).
SELECT_LOCK="$LOCK_ROOT/sim-select.lock.d"
select_lock_acquire() {
    local i
    for i in $(seq 1 100); do
        if LOCK_OWNER_PID=$$ lock_acquire "$SELECT_LOCK" 2>/dev/null; then return 0; fi
        sleep 0.05
    done
    echo "SIM-LEASE RESULT: ERROR select mutex busy" >&2
    return 1
}
select_lock_release() { LOCK_OWNER_PID=$$ lock_release "$SELECT_LOCK" 2>/dev/null || true; }

# The verify UDID resolution ladder (rule 55): VERIFY_UDID env → persisted
# choice → booted iPhone 17 Pro → any iPhone 17 Pro (booted on lease).
resolve_verify_udid() {
    if [ -n "${VERIFY_UDID:-}" ]; then echo "$VERIFY_UDID"; return 0; fi
    if [ -s "$STATE_DIR/verify-udid" ]; then cat "$STATE_DIR/verify-udid"; return 0; fi
    local devices
    devices="$(list_devices)"
    printf '%s\n' "$devices" | awk -F'|' '$2=="iPhone 17 Pro" && $3=="Booted" {print $1; exit}' | grep . && return 0
    printf '%s\n' "$devices" | awk -F'|' '$2=="iPhone 17 Pro" {print $1; exit}' | grep . && return 0
    return 1
}

cmd="${1:-}"

case "$cmd" in
    acquire)
        purpose="${2:-}"
        case "$purpose" in test|verify) : ;; *)
            echo "usage: sim-lease.sh acquire {test|verify}" >&2; exit 64 ;;
        esac
        mkdir -p "$LOCK_ROOT" "$STATE_DIR"
        select_lock_acquire || exit 1
        trap 'select_lock_release' EXIT

        if [ "$purpose" = "verify" ]; then
            if [ "$(held_count verify)" -ge 1 ]; then
                echo "SIM-LEASE RESULT: BUSY verify (capacity 1)"
                exit 2
            fi
            if ! udid="$(resolve_verify_udid)"; then
                echo "SIM-LEASE RESULT: ERROR no iPhone 17 Pro available for verify" >&2
                exit 1
            fi
            if ! lock_acquire "$(lease_dir "$udid")"; then
                echo "SIM-LEASE RESULT: BUSY verify ($udid already leased)"
                exit 2
            fi
            echo "$purpose" > "$(lease_dir "$udid")/purpose"
            printf '%s' "$udid" > "$STATE_DIR/verify-udid"
            state="$(list_devices | awk -F'|' -v u="$udid" '$1==u {print $3; exit}')"
            [ "$state" = "Booted" ] || boot_sim "$udid"
            echo "SIM-LEASE RESULT: ACQUIRED verify $udid"
            exit 0
        fi

        # purpose=test
        if [ "$(held_count test)" -ge 2 ]; then
            echo "SIM-LEASE RESULT: BUSY test (capacity 2)"
            exit 2
        fi
        verify_udid="$(resolve_verify_udid 2>/dev/null || true)"
        devices="$(list_devices)"
        if [ -z "$devices" ]; then
            echo "SIM-LEASE RESULT: ERROR no available simulators" >&2
            exit 1
        fi
        acquired=""
        while IFS='|' read -r udid name state; do
            [ -n "$udid" ] || continue
            [ "$udid" = "$verify_udid" ] && continue   # never share with verify
            case "$name" in iPhone*) : ;; *) continue ;; esac
            if lock_acquire "$(lease_dir "$udid")" 2>/dev/null; then
                echo "test" > "$(lease_dir "$udid")/purpose"
                [ "$state" = "Booted" ] || boot_sim "$udid"
                acquired="$udid"
                break
            fi
        done <<< "$devices"
        if [ -z "$acquired" ]; then
            echo "SIM-LEASE RESULT: ERROR no leasable test simulator" >&2
            exit 1
        fi
        echo "SIM-LEASE RESULT: ACQUIRED test $acquired"
        exit 0
        ;;
    release)
        udid="${2:-}"
        [ -n "$udid" ] || { echo "usage: sim-lease.sh release <udid>" >&2; exit 64; }
        if lock_release "$(lease_dir "$udid")"; then
            echo "SIM-LEASE RESULT: RELEASED $udid"
            exit 0
        fi
        echo "SIM-LEASE RESULT: NOT-OWNER $udid (lease left intact)" >&2
        exit 3
        ;;
    status)
        found=0
        for d in "$LOCK_ROOT"/sim-*.lock.d; do
            [ -e "$d" ] || continue
            found=1
            u="$(basename "$d" .lock.d)"; u="${u#sim-}"
            p="$(cat "$d/purpose" 2>/dev/null || echo unknown)"
            pid="$(sed -n 's/^pid=//p' "$d/owner" 2>/dev/null || true)"
            echo "held: $u purpose=$p pid=${pid:-unknown}"
        done
        [ "$found" -eq 0 ] && echo "SIM-LEASE STATUS: clean"
        exit 0
        ;;
    *)
        echo "usage: sim-lease.sh {acquire {test|verify} | release <udid> | status}" >&2
        exit 64
        ;;
esac
