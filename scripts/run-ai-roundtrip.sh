#!/usr/bin/env bash
# Purpose: feature #118 WI-5 — the LIVE AI acceptance (Gate-5). Stands up a throwaway
# OpenAI-compatible SSE stub on the Mac host, then runs the connected instrumentation test
# (AiRoundTripConnectedTest) on the emulator pointed at the host alias 10.0.2.2:$PORT. The stub
# answers a one-shot (testConnection) ping AND a streamed chat-completion. The server is owned BY
# THIS SCRIPT and killed by EXACT PID on exit (rule 49 — run the python DIRECTLY, never in a
# `( … ) &` subshell that would orphan the child; see the 2026-06-23 http.server-leak incident).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')}"
STUB="$(mktemp -t vreader-ai-stub-XXXX.py)"
SERVER_PID=""

cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  pkill -f "$STUB" 2>/dev/null   # belt: reap by the unique stub path (never another run's)
  rm -f "$STUB" 2>/dev/null
}
trap cleanup EXIT INT TERM

cat > "$STUB" <<'PY'
import http.server, json, sys
PORT = int(sys.argv[1])
DELTAS = ["Hello ", "from ", "the ", "vreader ", "stub."]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n).decode('utf-8') if n else ''
        streaming = '"stream":true' in body or '"stream": true' in body
        if streaming:
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.end_headers()
            for c in DELTAS:
                self.wfile.write(('data: ' + json.dumps({"choices":[{"delta":{"content":c}}]}) + '\n\n').encode())
                self.wfile.flush()
            self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
        else:
            payload = json.dumps({"choices":[{"message":{"content":"pong"}}]}).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', PORT), H).serve_forever()
PY

python3 "$STUB" "$PORT" &   # run directly → $! is the real server pid
SERVER_PID=$!

ready=0
for _ in $(seq 1 40); do
  if curl -s -o /dev/null --max-time 2 -X POST -d '{"stream":false}' "http://127.0.0.1:$PORT/chat/completions"; then ready=1; break; fi
  kill -0 "$SERVER_PID" 2>/dev/null || { echo "RUN-AI-ROUNDTRIP RESULT: STUB_DIED"; exit 1; }
  sleep 0.5
done
[ "$ready" = 1 ] || { echo "RUN-AI-ROUNDTRIP RESULT: STUB_NOT_READY"; exit 1; }

ARGS="-Pandroid.testInstrumentationRunnerArguments.class=com.vreader.app.ai.AiRoundTripConnectedTest"
ARGS="$ARGS -Pandroid.testInstrumentationRunnerArguments.aiBaseUrl=http://10.0.2.2:$PORT"

cd "$REPO/android" || exit 1
ANDROID_CMD="./gradlew :app:connectedDebugAndroidTest $ARGS" TIMEOUT_SECS="${TIMEOUT_SECS:-1800}" \
  bash "$REPO/scripts/run-android-verify.sh"
rc=$?

echo "RUN-AI-ROUNDTRIP RESULT: $([ $rc -eq 0 ] && echo SUCCEEDED || echo FAILED) (exit $rc)"
exit $rc
