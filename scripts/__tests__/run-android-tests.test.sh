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

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
