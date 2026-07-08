#!/usr/bin/env bash
# Feature #130 WI-3 — sibling-safety contract of scripts/run-tests.sh's
# timeout path: on watchdog kill, SWBBuildService is pkill'd ONLY when no
# other live `xcodebuild` exists. The sibling CHECK is injected via
# RUN_TESTS_SIBLING_CMD (spawning real xcodebuild-named processes is
# unreliable here: freshly copied binaries wedge in uninterruptible-exit on
# SIGKILL); `pkill` is PATH-stubbed to LOG and swallow any SWBBuildService
# kill so this test can never murder the real build daemon (rule 52 Cause B).
#
# Run: bash scripts/__tests__/run-tests-watchdog.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$HERE/../run-tests.sh"
fails=0
TMP="$(mktemp -d)" || { echo "FATAL: mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

BIN="$TMP/bin"; mkdir -p "$BIN"
PKILL_LOG="$TMP/pkill.log"; : > "$PKILL_LOG"

# stub xcodebuild: ignores args, sleeps (the wedge). A script, not a binary
# copy — its comm is bash, but the sibling check is injected anyway.
cat > "$BIN/xcodebuild" <<'EOF'
#!/usr/bin/env bash
sleep 300
EOF
chmod +x "$BIN/xcodebuild"

# stub pkill: log every call; SWALLOW daemon kills; forward -P tree kills
cat > "$BIN/pkill" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$PKILL_LOG"
case "\$*" in *SWBBuildService*) exit 0 ;; esac
exec /usr/bin/pkill "\$@"
EOF
chmod +x "$BIN/pkill"

# injectable sibling checks
NONE="$TMP/none.sh";  printf '#!/usr/bin/env bash\nexit 1\n' > "$NONE";  chmod +x "$NONE"
SOME="$TMP/some.sh";  printf '#!/usr/bin/env bash\necho 99999991\n' > "$SOME"; chmod +x "$SOME"

run_wedged() { # $1=sibling-cmd
    env PATH="$BIN:$PATH" TEST_UDID="FAKE-UDID-0000" TIMEOUT_SECS=2 \
        RUN_TESTS_SIBLING_CMD="$1" bash "$RUN" vreaderTests/Fake 2>&1
}

echo "== run-tests.sh sibling-safe daemon kill =="

# 1. NO sibling: timeout path MUST clear the daemon (Cause B behavior kept)
OUT="$(run_wedged "$NONE")"; RC=$?
if [ "$RC" -eq 3 ] && grep -q "RUN-TESTS RESULT: TIMEOUT" <<<"$OUT"; then ok "wedge → TIMEOUT (exit 3)"; else fail "timeout path (rc=$RC): $(tail -2 <<<"$OUT")"; fi
if grep -q -- "-x SWBBuildService" "$PKILL_LOG"; then ok "no sibling → daemon cleared"; else fail "no-sibling: daemon NOT cleared: $(cat "$PKILL_LOG")"; fi

# 2. sibling reported: daemon must NOT be pkill'd + the decision is named
: > "$PKILL_LOG"
OUT="$(run_wedged "$SOME")"; RC=$?
if [ "$RC" -eq 3 ]; then ok "wedge with sibling → still TIMEOUT"; else fail "sibling timeout (rc=$RC)"; fi
if ! grep -q -- "-x SWBBuildService" "$PKILL_LOG"; then ok "sibling alive → daemon spared"; else fail "sibling: daemon killed anyway: $(cat "$PKILL_LOG")"; fi
if grep -qi "sibling" <<<"$OUT"; then ok "watchdog names the sibling decision"; else fail "no sibling note in output"; fi

# 3. non-timeout run: sibling cmd never consulted, no daemon kill, no sentinel left
: > "$PKILL_LOG"
cat > "$BIN/xcodebuild" <<'EOF'
#!/usr/bin/env bash
echo "TEST SUCCEEDED"
EOF
chmod +x "$BIN/xcodebuild"
OUT="$(env PATH="$BIN:$PATH" TEST_UDID="FAKE-UDID-0000" TIMEOUT_SECS=30 RUN_TESTS_SIBLING_CMD="$SOME" bash "$RUN" vreaderTests/Fake 2>&1)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q "RUN-TESTS RESULT: SUCCEEDED" <<<"$OUT"; then ok "natural finish → SUCCEEDED"; else fail "natural finish (rc=$RC): $(tail -2 <<<"$OUT")"; fi
if [ ! -s "$PKILL_LOG" ]; then ok "natural finish → no pkill at all"; else fail "natural finish ran pkill: $(cat "$PKILL_LOG")"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
