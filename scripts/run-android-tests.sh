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
#    "RUN-ANDROID-TESTS RESULT: SUCCEEDED|FAILED|TIMEOUT|NO_EMULATOR".
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

# Real "booted emulator" detection (Codex Gate-4): `adb get-state` is not it —
# it passes for a physical device and errors with multiple devices. Require an
# `emulator-NNNN` serial in `device` state.
emulator_online() {
  command -v adb >/dev/null 2>&1 || return 1
  adb devices 2>/dev/null | awk '/^emulator-[0-9]+[[:space:]]+device$/ {f=1} END {exit !f}'
}
if [ "$REQUIRE_EMULATOR" -eq 1 ] && ! emulator_online; then
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
