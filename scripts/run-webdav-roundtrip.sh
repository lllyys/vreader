#!/usr/bin/env bash
# Purpose: feature #116 WI-6 — the LIVE WebDAV backup/restore round-trip (Gate-5 acceptance).
# Stands up a throwaway `rclone serve webdav` on the Mac host, then runs the connected
# instrumentation test (WebDavRoundTripConnectedTest) on the emulator pointed at the host alias
# 10.0.2.2:$PORT. The server's lifecycle is owned BY THIS SCRIPT and killed by EXACT PID on exit
# (rule 49 — never a pgrep waiter); the instrumentation gate runs through the watchdog
# (run-android-verify.sh → run-android-tests.sh, rule 49/52/53).
#
# Usage:
#   scripts/run-webdav-roundtrip.sh
#   PORT=8099 scripts/run-webdav-roundtrip.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
USER_NAME="${WEBDAV_USER:-vreader}"
PASS="${WEBDAV_PASS:-vreader}"
PORT="${PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')}"
DATADIR="$(mktemp -d -t vreader-webdav)"
RCLONE_PID=""

cleanup() {
  # Kill the server we started, by its exact PID (rule 49). Best-effort; idempotent.
  [ -n "$RCLONE_PID" ] && kill "$RCLONE_PID" 2>/dev/null
  rm -rf "$DATADIR" 2>/dev/null
}
trap cleanup EXIT INT TERM

command -v rclone >/dev/null 2>&1 || { echo "RUN-WEBDAV-ROUNDTRIP RESULT: NO_RCLONE (brew install rclone)"; exit 1; }

echo "[webdav-roundtrip] rclone serve webdav 127.0.0.1:$PORT  data=$DATADIR  user=$USER_NAME"
rclone serve webdav --addr "127.0.0.1:$PORT" --user "$USER_NAME" --pass "$PASS" "$DATADIR" >"$DATADIR/.rclone.log" 2>&1 &
RCLONE_PID=$!

# Wait (bounded) for the server to accept connections — poll the exact port, not a process name.
ready=0
for _ in $(seq 1 40); do
  if curl -s -o /dev/null --max-time 2 -u "$USER_NAME:$PASS" "http://127.0.0.1:$PORT/"; then ready=1; break; fi
  kill -0 "$RCLONE_PID" 2>/dev/null || { echo "RUN-WEBDAV-ROUNDTRIP RESULT: RCLONE_DIED"; cat "$DATADIR/.rclone.log"; exit 1; }
  sleep 0.5
done
[ "$ready" = 1 ] || { echo "RUN-WEBDAV-ROUNDTRIP RESULT: SERVER_NOT_READY"; exit 1; }

# The emulator reaches the host loopback at 10.0.2.2. Run ONLY the round-trip test.
ARGS="-Pandroid.testInstrumentationRunnerArguments.class=com.vreader.app.backup.WebDavRoundTripConnectedTest"
ARGS="$ARGS -Pandroid.testInstrumentationRunnerArguments.webdavBaseUrl=http://10.0.2.2:$PORT/"
ARGS="$ARGS -Pandroid.testInstrumentationRunnerArguments.webdavUser=$USER_NAME"
ARGS="$ARGS -Pandroid.testInstrumentationRunnerArguments.webdavPass=$PASS"

cd "$REPO/android" || exit 1
ANDROID_CMD="./gradlew :app:connectedDebugAndroidTest $ARGS" TIMEOUT_SECS="${TIMEOUT_SECS:-1800}" \
  bash "$REPO/scripts/run-android-verify.sh"
rc=$?

echo "RUN-WEBDAV-ROUNDTRIP RESULT: $([ $rc -eq 0 ] && echo SUCCEEDED || echo FAILED) (exit $rc)"
exit $rc
