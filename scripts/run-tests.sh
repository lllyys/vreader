#!/usr/bin/env bash
# Purpose: Watchdog wrapper for `xcodebuild test` that PREVENTS the recurring
# ghost/hang failure mode (xcodebuild wedges at 0% CPU with zero output and
# lingers for hours). See .claude/rules/52-test-sim-isolation.md.
#
# Guarantees:
#  - Pins the destination by UDID (TEST_UDID env, else first booted sim).
#  - HARD wall-clock timeout: a wedged run is killed (process tree) after
#    TIMEOUT_SECS (default 900s = 15min) instead of ghosting indefinitely.
#  - Waits on the EXACT pid (rule 49 — identity, not likeness). One job, one
#    owner, one completion channel. The watchdog is cancelled the instant the
#    test finishes first, so it never outlives this invocation.
#  - Emits one unambiguous final line: "RUN-TESTS RESULT: SUCCEEDED|FAILED|TIMEOUT|NO_BOOTED_SIM".
#
# Usage:
#   scripts/run-tests.sh [only-testing-target]      # default: vreaderTests
#   TIMEOUT_SECS=1200 scripts/run-tests.sh vreaderTests/DebugCommandTests
#   TEST_UDID=<udid>   scripts/run-tests.sh
#
# IMPORTANT (rule 52): do NOT drive the SAME simulator (sim-tap / idb / simctl
# openurl eval / verification) while this is running. Sim contention is what
# wedges xcodebuild. Serialize, or point verification at a different UDID.
set -uo pipefail

TIMEOUT_SECS="${TIMEOUT_SECS:-900}"
PROJECT="vreader.xcodeproj"
SCHEME="vreader"

# Accept one or more -only-testing targets (default: the whole vreaderTests
# suite). Prefer passing the TARGETED suites that cover your change — the full
# suite takes >20 min (rule 52, Cause C).
ONLY_ARGS=()
if [ "$#" -eq 0 ]; then
  ONLY_ARGS=(-only-testing:vreaderTests)
else
  for t in "$@"; do ONLY_ARGS+=(-only-testing:"$t"); done
fi

UDID="${TEST_UDID:-$(xcrun simctl list devices booted 2>/dev/null | grep -Eo '[0-9A-Fa-f-]{36}' | head -1)}"
if [ -z "$UDID" ]; then
  echo "RUN-TESTS RESULT: NO_BOOTED_SIM"
  exit 2
fi

LOG="$(mktemp -t run-tests.XXXXXX)"
echo "[run-tests] targets=${ONLY_ARGS[*]} udid=$UDID timeout=${TIMEOUT_SECS}s log=$LOG"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project "$PROJECT" -scheme "$SCHEME" \
  -destination "platform=iOS Simulator,id=$UDID" \
  "${ONLY_ARGS[@]}" >"$LOG" 2>&1 &
pid=$!

# Watchdog: kill the exact test process tree if it exceeds the deadline.
# Tied to THIS pid only — a future xcodebuild run cannot re-arm it (rule 49).
# CRITICAL: a bare `kill -9 xcodebuild` orphans Xcode's build daemon
# (SWBBuildService) in a wedged state, which then HANGS THE NEXT BUILD with the
# sim idle (observed 2026-05-31). So the watchdog also restarts the build
# daemon, leaving a clean environment for the next run.
(
  sleep "$TIMEOUT_SECS"
  if kill -0 "$pid" 2>/dev/null; then
    echo "[run-tests][watchdog] exceeded ${TIMEOUT_SECS}s — killing tree of $pid + build daemon"
    pkill -9 -P "$pid" 2>/dev/null
    kill -9 "$pid" 2>/dev/null
    pkill -9 -x SWBBuildService 2>/dev/null   # clear the wedged build daemon
  fi
) &
wd=$!

wait "$pid"
rc=$?
# Cancel the watchdog if the test finished on its own.
kill "$wd" 2>/dev/null
wait "$wd" 2>/dev/null

echo "----- last log lines -----"
tail -12 "$LOG"
echo "--------------------------"

if grep -q "TEST SUCCEEDED" "$LOG"; then
  echo "RUN-TESTS RESULT: SUCCEEDED"
  exit 0
elif [ "$rc" -eq 137 ] || [ "$rc" -eq 143 ] || [ "$rc" -eq 9 ]; then
  echo "RUN-TESTS RESULT: TIMEOUT (killed after ${TIMEOUT_SECS}s — sim likely contended; do not drive the sim during tests)"
  exit 3
else
  echo "RUN-TESTS RESULT: FAILED (exit $rc)"
  exit 1
fi
