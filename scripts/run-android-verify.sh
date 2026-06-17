#!/usr/bin/env bash
# Purpose: Watchdog wrapper for the Android emulator VERIFY lane (Gate-5 Android
# tier) — the Android analog of driving the iOS simulator for verification.
# Feature #107 PR-B.
#
# Thin delegate over scripts/run-android-tests.sh (one watchdog implementation,
# rule 49/52/53). Until feature #106's app exists, the real emulator-verify
# target is the Spike-B instrumentation harness, so this drives a verification
# sweep through it by default; once #106 lands, point it at
# `connectedAndroidTest` / `am instrument` via ANDROID_CMD.
#
# Usage:
#   scripts/run-android-verify.sh                                  # spike emulator sweep
#   ANDROID_CMD="./gradlew :app:connectedDebugAndroidTest" scripts/run-android-verify.sh   # post-#106
#   TIMEOUT_SECS=1800 scripts/run-android-verify.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# A fuller sweep than the test smoke (more chapters) — verification, not a unit
# smoke. Caller can override ANDROID_CMD for the post-#106 connected-test lane.
if [ -z "${ANDROID_CMD:-}" ]; then
  export CHAPTERS="${CHAPTERS:-24}" SCROLLS="${SCROLLS:-2}"
fi
# Verify runs are longer than unit smokes.
export TIMEOUT_SECS="${TIMEOUT_SECS:-1800}"

# Delegate to the single watchdog implementation (preserves live streaming + the
# exact exit code). The RESULT line is RUN-ANDROID-TESTS RESULT: …; the verify
# lane reuses it (the caller knows which script it invoked). exec keeps one
# process / one completion channel (rule 49).
exec bash "$REPO/scripts/run-android-tests.sh"
