#!/usr/bin/env bash
# Purpose: feature #117 WI-2 — the LIVE OPDS round-trip (Gate-5 acceptance). Serves a throwaway
# static OPDS feed + an EPUB over a local HTTP server on the Mac host, then runs the connected
# instrumentation test (OpdsRoundTripConnectedTest) on the emulator pointed at the host alias
# 10.0.2.2:$PORT. The server's lifecycle is owned BY THIS SCRIPT and killed by EXACT PID on exit
# (rule 49 — never a pgrep waiter); the instrumentation gate runs through the watchdog
# (run-android-verify.sh → run-android-tests.sh).
#
# Real-books-first: serves a real EPUB from test-books/books/epub/ when present, else generates a
# minimal valid EPUB (the import only needs ZIP magic + the .epub extension).
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PORT:-$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')}"
SERVEDIR="$(mktemp -d -t vreader-opds)"
SERVER_PID=""

cleanup() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$SERVEDIR" 2>/dev/null; }
trap cleanup EXIT INT TERM

# Stage the EPUB.
real_epub="$(ls "$REPO"/test-books/books/epub/*.epub 2>/dev/null | head -1 || true)"
if [ -n "$real_epub" ]; then
  cp "$real_epub" "$SERVEDIR/book.epub"
  echo "[opds-roundtrip] serving real EPUB: $(basename "$real_epub")"
else
  python3 - "$SERVEDIR/book.epub" <<'PY'
import sys, zipfile
p = sys.argv[1]
with zipfile.ZipFile(p, "w") as z:
    z.writestr("mimetype", "application/epub+zip")
    z.writestr("META-INF/container.xml",
               '<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
               '<rootfiles><rootfile full-path="content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>')
    z.writestr("content.opf", '<?xml version="1.0"?><package version="3.0" xmlns="http://www.idpf.org/2007/opf"></package>')
PY
  echo "[opds-roundtrip] serving generated minimal EPUB"
fi

# Static OPDS acquisition feed referencing the EPUB (relative href, open-access acquisition).
cat > "$SERVEDIR/feed.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
  <title>vreader OPDS round-trip</title><id>urn:vreader:opds:test</id>
  <entry>
    <title>Round-Trip Book</title><id>urn:vreader:book:1</id>
    <link rel="http://opds-spec.org/acquisition/open-access" href="book.epub" type="application/epub+zip"/>
  </entry>
</feed>
EOF

# NOT `( cd … && python3 … ) &` — that captures the SUBSHELL pid in $!, so the trap's
# `kill $SERVER_PID` reaps the subshell but ORPHANS the python child (it survives as a ghost
# http.server). `--directory` runs python directly so $! is the real server pid (rule 49).
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$SERVEDIR" >/dev/null 2>&1 &
SERVER_PID=$!

# Wait (bounded) for the server to accept connections.
ready=0
for _ in $(seq 1 40); do
  if curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/feed.xml"; then ready=1; break; fi
  kill -0 "$SERVER_PID" 2>/dev/null || { echo "RUN-OPDS-ROUNDTRIP RESULT: SERVER_DIED"; exit 1; }
  sleep 0.5
done
[ "$ready" = 1 ] || { echo "RUN-OPDS-ROUNDTRIP RESULT: SERVER_NOT_READY"; exit 1; }

ARGS="-Pandroid.testInstrumentationRunnerArguments.class=com.vreader.app.opds.OpdsRoundTripConnectedTest"
ARGS="$ARGS -Pandroid.testInstrumentationRunnerArguments.opdsFeedUrl=http://10.0.2.2:$PORT/feed.xml"

cd "$REPO/android" || exit 1
ANDROID_CMD="./gradlew :app:connectedDebugAndroidTest $ARGS" TIMEOUT_SECS="${TIMEOUT_SECS:-1800}" \
  bash "$REPO/scripts/run-android-verify.sh"
rc=$?

echo "RUN-OPDS-ROUNDTRIP RESULT: $([ $rc -eq 0 ] && echo SUCCEEDED || echo FAILED) (exit $rc)"
exit $rc
