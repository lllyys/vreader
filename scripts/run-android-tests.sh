#!/usr/bin/env bash
# Purpose: Watchdog wrapper for Android test / instrumentation runs — the
# Android analog of scripts/run-tests.sh. Feature #107 PR-B.
#
# Guarantees (rule 49 / 52 / 53):
#  - HARD wall-clock timeout: a wedged run is killed (process tree + the Gradle
#    daemon — rule 52 "Cause D", the Android analog of SWBBuildService) after
#    TIMEOUT_SECS instead of ghosting indefinitely.
#  - Waits on the EXACT pid (rule 49 — identity, not likeness). One job, one
#    owner, one completion channel; the watchdog is cancelled the instant the
#    run finishes, so it never outlives this invocation.
#  - Emits ONE unambiguous final line:
#    "RUN-ANDROID-TESTS RESULT: SUCCEEDED|FAILED|TIMEOUT|NO_EMULATOR|AMBIGUOUS_SERIAL".
#  - Targets a SPECIFIC emulator via ANDROID_SERIAL (validated + exported), so
#    two AVDs never race on an ambiguous `adb` (feature #138 follow-up — rule 52
#    Cause D / rule 55 Android tier). Create a 2nd AVD for parallel runs with:
#      avdmanager create avd -n vreader-test-2 -k "system-images;android-35;google_apis;arm64-v8a"
#      emulator -avd vreader-test-2 -no-snapshot-save &   # boots as emulator-5556
#    then pass ANDROID_SERIAL=emulator-5556 to route a run to it.
#
# Target: until feature #106's `android/` app shell exists there is NO root
# `./gradlew` — the only real Android target is the Spike-B harness, so this
# runner drives THAT by default (a small CHAPTERS smoke). Once #106 lands, point
# it at the app's Gradle task via ANDROID_CMD.
#
# Usage:
#   scripts/run-android-tests.sh                          # spike harness smoke
#   ANDROID_CMD="./gradlew :app:testDebugUnitTest" scripts/run-android-tests.sh   # post-#106
#   ANDROID_CMD="true" scripts/run-android-tests.sh       # contract self-test
#   TIMEOUT_SECS=600 scripts/run-android-tests.sh
#   ANDROID_SERIAL=emulator-5556 ANDROID_CMD="cd android && ./gradlew :app:connectedDebugAndroidTest" \
#     scripts/run-android-tests.sh                        # route to a SPECIFIC emulator
#
# IMPORTANT (rule 52): do NOT drive the SAME emulator (adb/am instrument/
# screenshots) while this runs — contention is what wedges Gradle/instrumentation.
set -uo pipefail

TIMEOUT_SECS="${TIMEOUT_SECS:-1200}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Default target = the Spike-B harness (a real emulator instrumentation run); a
# small smoke by default so the runner self-verifies cheaply. When the caller
# overrides ANDROID_CMD they own device readiness, so we only require an online
# emulator for the DEFAULT (spike) command.
if [ -n "${ANDROID_CMD:-}" ]; then
  CMD="$ANDROID_CMD"
  REQUIRE_EMULATOR=0
else
  CMD="CHAPTERS=${CHAPTERS:-6} SCROLLS=${SCROLLS:-1} bash \"$REPO/spikes/android-reader-bench/run-bench.sh\""
  REQUIRE_EMULATOR=1
fi

# The `adb devices` source, overridable for tests (ANDROID_DEVICES_CMD — the
# emulator analog of sim-lease's SIM_LEASE_DISCOVER_CMD). ALWAYS exits 0 (prints
# nothing when adb is absent) so a missing-adb pipe never trips a caller.
android_devices() {
  if [ -n "${ANDROID_DEVICES_CMD:-}" ]; then eval "$ANDROID_DEVICES_CMD" || true
  elif command -v adb >/dev/null 2>&1; then adb devices 2>/dev/null || true
  fi
  return 0
}
# Real "booted emulator" detection (Codex Gate-4): `adb get-state` is not it —
# it passes for a physical device and errors with multiple devices. With $1 = a
# specific serial, check ONLY that serial is online in `device` state (a physical
# device serial is a valid ANDROID_SERIAL target too); without $1, check ANY
# `emulator-NNNN` is online (the spike genuinely needs an emulator).
emulator_online() {
  if [ -n "${1:-}" ]; then
    android_devices | awk -v s="$1" '$1==s && $2=="device" {f=1} END {exit !f}'
  else
    android_devices | awk '/^emulator-[0-9]+[[:space:]]+device$/ {f=1} END {exit !f}'
  fi
}
# ALL online devices in `device` state (emulator + physical) — bare `adb`/Gradle
# is ambiguous ("more than one device") with >1 of EITHER kind, so the ambiguity
# guard counts both, not just emulators (Gate-4: a physical phone counts too).
online_device_count() { android_devices | awk '$2=="device" {n++} END {print n+0}'; }

# ANDROID_SERIAL routing (feature #138 follow-up — parallel-emulator support;
# rule 52 Cause D / rule 55 Android tier). One AVD is the default today, but a
# run MUST be able to TARGET a specific device so two AVDs (once created) don't
# race on an ambiguous `adb`. adb + Gradle's connected task both honor the
# exported ANDROID_SERIAL env var natively, so routing = validate + export.
ANDROID_SERIAL="${ANDROID_SERIAL:-}"
if [ -n "$ANDROID_SERIAL" ]; then
  if ! emulator_online "$ANDROID_SERIAL"; then
    echo "RUN-ANDROID-TESTS RESULT: NO_EMULATOR (ANDROID_SERIAL=$ANDROID_SERIAL not online in 'device' state)"
    exit 2
  fi
  export ANDROID_SERIAL   # every adb/Gradle connected command now targets THIS device
elif [ "$(online_device_count)" -gt 1 ]; then
  # >1 device online + no serial → bare adb is ambiguous ("more than one device").
  # Hard-fail the device-driving default/spike path; only WARN for a caller-owned
  # ANDROID_CMD (which may be a device-less JVM task like testDebugUnitTest —
  # forcing a serial there would be wrong).
  if [ "$REQUIRE_EMULATOR" -eq 1 ]; then
    echo "RUN-ANDROID-TESTS RESULT: AMBIGUOUS_SERIAL ($(online_device_count) devices online — set ANDROID_SERIAL=<serial> to pick one)"
    exit 2
  fi
  echo "[run-android-tests] WARNING: $(online_device_count) devices online + no ANDROID_SERIAL — an adb/connected task may fail ambiguously; set ANDROID_SERIAL=<serial> to target one."
fi

if [ "$REQUIRE_EMULATOR" -eq 1 ] && ! emulator_online "$ANDROID_SERIAL"; then
  echo "RUN-ANDROID-TESTS RESULT: NO_EMULATOR (no emulator-NNNN device online — boot an AVD or pass ANDROID_CMD)"
  exit 2
fi

# Recursively kill a process + ALL descendants (Codex Gate-4: pkill -P is
# direct-children-only; a `bash -c` wrapper can leave deeper orphans). Portable
# (pgrep -P), no setsid (absent on macOS).
kill_tree() {
  local p="$1" c
  for c in $(pgrep -P "$p" 2>/dev/null); do kill_tree "$c"; done
  kill -9 "$p" 2>/dev/null
}
# Snapshot pre-existing Gradle daemons so a timeout kill targets ONLY daemons
# THIS run spawned (Codex Gate-4: a global `pkill -f org.gradle…` could kill an
# unrelated repo's resident daemon). A run that connects to a pre-existing
# daemon leaves it alone — correct, it's resident-by-design.
gradle_daemons() { pgrep -f 'org.gradle.launcher.daemon|GradleDaemon' 2>/dev/null | sort -u; }
PRE_DAEMONS="$(gradle_daemons || true)"

LOG="$(mktemp -t run-android-tests.XXXXXX)"
# Sentinel the watchdog touches BEFORE it starts killing — distinguishes a
# real timeout from normal completion so the parent does not cancel the
# watchdog mid-cleanup (Codex Gate-4 r2: the daemon diff/kill must finish).
FIRED="$(mktemp -u -t run-android-fired.XXXXXX)"
echo "[run-android-tests] cmd=$CMD timeout=${TIMEOUT_SECS}s log=$LOG"

bash -c "$CMD" >"$LOG" 2>&1 &
pid=$!

# Watchdog tied to THIS pid only (rule 49). On timeout: recursive tree kill +
# kill ONLY Gradle daemons spawned during this run (a wedged new daemon would
# hang the NEXT build — rule 52 Cause D — but a pre-existing one is left alone).
# The subshell is redirected to the LOG (not this script's stdout); otherwise
# its backgrounded `sleep` keeps the stdout fd open and a `$(...)` caller blocks
# until TIMEOUT_SECS even after the run finished. On cancel we kill the subshell
# AND its sleep child so nothing lingers (rule 49).
(
  sleep "$TIMEOUT_SECS"
  if kill -0 "$pid" 2>/dev/null; then
    : > "$FIRED"   # mark timeout BEFORE the kill that unblocks the parent's wait
    echo "[run-android-tests][watchdog] exceeded ${TIMEOUT_SECS}s — killing tree of $pid + this run's Gradle daemon(s)"
    kill_tree "$pid"
    post="$(gradle_daemons || true)"
    new="$(comm -13 <(printf '%s\n' "$PRE_DAEMONS") <(printf '%s\n' "$post") 2>/dev/null)"
    [ -n "$new" ] && printf '%s\n' "$new" | xargs kill -9 2>/dev/null
  fi
) >>"$LOG" 2>&1 &
wd=$!

wait "$pid"; rc=$?
if [ -e "$FIRED" ]; then
  # Timeout fired — the sentinel was set BEFORE kill_tree, so it exists by the
  # time `wait $pid` returns. Let the watchdog FINISH its daemon cleanup; do not
  # cancel it mid-flight (Codex Gate-4 r2).
  wait "$wd" 2>/dev/null
else
  # Normal completion — cancel the still-sleeping watchdog + its sleep child.
  pkill -P "$wd" 2>/dev/null
  kill "$wd" 2>/dev/null
  wait "$wd" 2>/dev/null
fi

echo "----- last log lines -----"
tail -12 "$LOG"
echo "--------------------------"

if [ -e "$FIRED" ]; then
  rm -f "$FIRED"
  echo "RUN-ANDROID-TESTS RESULT: TIMEOUT (killed after ${TIMEOUT_SECS}s — emulator likely contended; do not drive it during a run)"
  exit 3
elif [ "$rc" -eq 0 ]; then
  rm -f "$FIRED"
  echo "RUN-ANDROID-TESTS RESULT: SUCCEEDED"
  exit 0
else
  rm -f "$FIRED"
  echo "RUN-ANDROID-TESTS RESULT: FAILED (exit $rc)"
  exit 1
fi
