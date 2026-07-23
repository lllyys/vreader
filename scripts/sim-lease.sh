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
# A third purpose `android` leases an ONLINE Android emulator SERIAL (feature
# #138 follow-up — rule 55 Android tier): capacity = number of online emulators
# (1 today, N once more AVDs boot), exclusive per-serial, no boot-on-demand
# (require the emulator already online). The leased serial is what a lane passes
# as ANDROID_SERIAL to scripts/run-android-tests.sh.
#
# Usage:
#   sim-lease.sh acquire {test|verify}  -> 0 "SIM-LEASE RESULT: ACQUIRED <purpose> <udid>"
#                                          2 BUSY (capacity) | 1 ERROR (no sims)
#   sim-lease.sh acquire android        -> 0 "SIM-LEASE RESULT: ACQUIRED android emulator-NNNN"
#                                          2 BUSY (all online emulators leased) | 1 ERROR (none online)
#   sim-lease.sh release <udid|serial>  -> 0 RELEASED | 3 NOT-OWNER
#   sim-lease.sh status                 -> one "held:" line per lease
# Env: SIM_LEASE_LOCK_ROOT (default <repo>/.claude/locks),
#      SIM_LEASE_STATE_DIR (default <repo>/.claude/state),
#      SIM_LEASE_DISCOVER_CMD (default `xcrun simctl list -j devices available`),
#      SIM_LEASE_BOOT_CMD (default `xcrun simctl boot`),
#      ANDROID_DEVICES_CMD (default `adb devices`; purpose=android discovery),
#      VERIFY_UDID, LOCK_OWNER_PID.

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

# --- Android emulator discovery (purpose=android; feature #138 follow-up) ------
# The `adb devices` source, overridable for tests (ANDROID_DEVICES_CMD — same
# hook name as scripts/run-android-tests.sh so a serial routed to a run matches
# the one leased here). ALWAYS exits 0 (prints nothing when adb is absent) so a
# missing-adb pipe never trips `set -e` in the command-substitution below —
# which would otherwise exit the whole script WITHOUT the "no online emulator"
# RESULT line (Gate-4 Medium).
android_devices() {
    if [ -n "${ANDROID_DEVICES_CMD:-}" ]; then eval "$ANDROID_DEVICES_CMD" || true
    elif command -v adb >/dev/null 2>&1; then adb devices 2>/dev/null || true; fi
    return 0
}
list_emulators() { android_devices | awk '/^emulator-[0-9]+[[:space:]]+device$/ {print $1}'; }

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
        case "$purpose" in test|verify|android) : ;; *)
            echo "usage: sim-lease.sh acquire {test|verify|android}" >&2; exit 64 ;;
        esac
        mkdir -p "$LOCK_ROOT" "$STATE_DIR"
        select_lock_acquire || exit 1
        trap 'select_lock_release' EXIT

        if [ "$purpose" = "android" ]; then
            # Lease an ONLINE emulator SERIAL, exclusive per-serial (rule 55 Android
            # tier / rule 52 Cause D). Capacity = number of online emulators (1 today;
            # N once more AVDs are booted) — enforced by leasing the first UNLEASED
            # online serial and BUSY-ing when all are held. NO boot-on-demand: an AVD
            # boot needs its name + is heavy/async, so require the emulator already
            # online (unlike an iOS sim, which boots on lease). Emulators live in a
            # separate namespace (emulator-NNNN) from iOS UDIDs, so no verify exclusion.
            serials="$(list_emulators || true)"
            if [ -z "$serials" ]; then
                echo "SIM-LEASE RESULT: ERROR no online emulator to lease (boot an AVD: emulator -avd <name>)" >&2
                exit 1
            fi
            acquired=""
            while IFS= read -r serial; do
                [ -n "$serial" ] || continue
                if lock_acquire "$(lease_dir "$serial")" 2>/dev/null; then
                    echo "android" > "$(lease_dir "$serial")/purpose"
                    acquired="$serial"
                    break
                fi
            done <<< "$serials"
            if [ -z "$acquired" ]; then
                echo "SIM-LEASE RESULT: BUSY android (all $(printf '%s\n' "$serials" | grep -c . ) online emulator(s) leased)"
                exit 2
            fi
            echo "SIM-LEASE RESULT: ACQUIRED android $acquired"
            exit 0
        fi

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
        echo "usage: sim-lease.sh {acquire {test|verify|android} | release <udid-or-serial> | status}" >&2
        exit 64
        ;;
esac
