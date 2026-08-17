#!/usr/bin/env bash
# Feature #107 PR-B — exercises the watchdog/RESULT-line CONTRACT of
# scripts/run-android-tests.sh with REAL processes (via ANDROID_CMD stubs), not
# a dry-run of the Android lane. Asserts the four RESULT outcomes + that a wedged
# command is actually killed by the watchdog (rule 49/52/53).
#
# Run: bash scripts/__tests__/run-android-tests.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$HERE/../run-android-tests.sh"
fails=0

# assert_result <expected RESULT substring> <expected exit> <description> -- <env assignments...>
assert_result() {
    local want_result="$1" want_exit="$2" desc="$3"; shift 3
    [ "$1" = "--" ] && shift
    local out rc
    out="$(env "$@" bash "$RUN" 2>&1)"; rc=$?
    if grep -q "$want_result" <<<"$out" && [ "$rc" -eq "$want_exit" ]; then
        echo "ok   — $desc (exit $rc)"
    else
        echo "FAIL — $desc: want '$want_result'/exit $want_exit, got exit $rc:"; echo "$out" | tail -3; fails=$((fails+1))
    fi
}

echo "== run-android-tests.sh watchdog contract =="
assert_result "RUN-ANDROID-TESTS RESULT: SUCCEEDED" 0 "ANDROID_CMD=true → SUCCEEDED" -- ANDROID_CMD="true"
assert_result "RUN-ANDROID-TESTS RESULT: FAILED"    1 "ANDROID_CMD=false → FAILED"   -- ANDROID_CMD="false"

# TIMEOUT: a 30s sleep with a 2s deadline must be killed and report TIMEOUT in ~2s.
echo "   (timing the watchdog kill...)"
start=$(date +%s 2>/dev/null || echo 0)
assert_result "RUN-ANDROID-TESTS RESULT: TIMEOUT"   3 "wedged cmd → TIMEOUT (killed)" -- ANDROID_CMD="sleep 30" TIMEOUT_SECS="2"
end=$(date +%s 2>/dev/null || echo 0)
if [ "$start" != 0 ] && [ $((end - start)) -le 10 ]; then
    echo "ok   — watchdog killed the wedged run promptly ($((end - start))s)"
else
    echo "FAIL — watchdog did not kill promptly ($((end - start))s)"; fails=$((fails+1))
fi

# NO_EMULATOR: the default (spike) command requires an online emulator. When
# none is online (the common CI / dev case here), the runner short-circuits.
if ! command -v adb >/dev/null 2>&1 || [ "$(adb get-state 2>/dev/null)" != "device" ]; then
    assert_result "RUN-ANDROID-TESTS RESULT: NO_EMULATOR" 2 "no emulator + default cmd → NO_EMULATOR" --
else
    echo "skip — NO_EMULATOR case (an emulator is online)"
fi

echo "== ANDROID_SERIAL routing (mocked device source; feature #138 follow-up) =="
ONE='printf "List of devices attached\nemulator-5554\tdevice\n"'
TWO='printf "List of devices attached\nemulator-5554\tdevice\nemulator-5556\tdevice\n"'
NONE='printf "List of devices attached\n"'

# A requested serial that is NOT online → NO_EMULATOR (validation), even for a JVM ANDROID_CMD.
assert_result "RUN-ANDROID-TESTS RESULT: NO_EMULATOR" 2 "ANDROID_SERIAL not online → NO_EMULATOR" \
    -- ANDROID_CMD="true" ANDROID_SERIAL="emulator-9999" ANDROID_DEVICES_CMD="$NONE"

# A requested serial that IS online → routes + runs (the ANDROID_CMD asserts the serial is exported).
assert_result "RUN-ANDROID-TESTS RESULT: SUCCEEDED" 0 "ANDROID_SERIAL online → exported + run" \
    -- ANDROID_CMD='[ "$ANDROID_SERIAL" = emulator-5554 ]' ANDROID_SERIAL="emulator-5554" ANDROID_DEVICES_CMD="$ONE"

# >1 emulator online + no serial + emulator-driving DEFAULT cmd → AMBIGUOUS_SERIAL (hard fail).
assert_result "RUN-ANDROID-TESTS RESULT: AMBIGUOUS_SERIAL" 2 "2 emulators + no serial + default → AMBIGUOUS" \
    -- ANDROID_DEVICES_CMD="$TWO"

# >1 emulator online + no serial + caller-owned ANDROID_CMD (may be JVM) → WARN only, still runs.
assert_result "RUN-ANDROID-TESTS RESULT: SUCCEEDED" 0 "2 emulators + no serial + ANDROID_CMD → warn+run" \
    -- ANDROID_CMD="true" ANDROID_DEVICES_CMD="$TWO"

# 1 emulator + 1 PHYSICAL device + no serial + default cmd → AMBIGUOUS (bare adb is ambiguous with
# ANY 2 devices, not just 2 emulators — Gate-4 High-2).
EMU_PHYS='printf "List of devices attached\nemulator-5554\tdevice\nR58M12345678\tdevice\n"'
assert_result "RUN-ANDROID-TESTS RESULT: AMBIGUOUS_SERIAL" 2 "emulator+physical + no serial + default → AMBIGUOUS" \
    -- ANDROID_DEVICES_CMD="$EMU_PHYS"

# A PHYSICAL device serial is a valid ANDROID_SERIAL target (general adb routing, not emulator-only).
assert_result "RUN-ANDROID-TESTS RESULT: SUCCEEDED" 0 "physical ANDROID_SERIAL online → routes + runs" \
    -- ANDROID_CMD='[ "$ANDROID_SERIAL" = R58M12345678 ]' ANDROID_SERIAL="R58M12345678" ANDROID_DEVICES_CMD="$EMU_PHYS"

# Single emulator online + no serial + caller ANDROID_CMD → NOT ambiguous, no warning, runs (backward
# compat: the common one-AVD case is unchanged). Uses ANDROID_CMD=true so nothing drives the emulator.
out="$(env ANDROID_DEVICES_CMD="$ONE" ANDROID_CMD="true" bash "$RUN" 2>&1)"; rc=$?
if grep -q "RUN-ANDROID-TESTS RESULT: SUCCEEDED" <<<"$out" && ! grep -q "WARNING:" <<<"$out" && [ "$rc" -eq 0 ]; then
    echo "ok   — 1 emulator + no serial → not ambiguous, no warning (backward compat)"
else
    echo "FAIL — 1 emulator + no serial should run cleanly (rc=$rc): $(grep -E 'RESULT|WARNING' <<<"$out")"; fails=$((fails+1))
fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
