#!/usr/bin/env bash
# Feature #130 WI-3 — contract tests for scripts/agent-lock.sh (named mutex
# CLI over lib/lock.sh). Temp lock root; never the real .claude/locks.
#
# Run: bash scripts/__tests__/agent-lock.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLI="$HERE/../agent-lock.sh"
fails=0
TMP="$(mktemp -d)" || { echo "FATAL: mktemp failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

if [ ! -f "$CLI" ]; then echo "FAIL — $CLI does not exist"; echo "1 FAILURE(S)"; exit 1; fi

run() { env LOCK_OWNER_PID=$$ AGENT_LOCK_ROOT="$TMP/locks" bash "$CLI" "$@" 2>&1; }

echo "== agent-lock.sh contract =="

# 1. acquire → release round trip; RESULT lines present
OUT="$(run acquire dispatch)"; RC=$?
if [ "$RC" -eq 0 ] && grep -q "AGENT-LOCK RESULT: ACQUIRED dispatch" <<<"$OUT"; then ok "acquire free lock"; else fail "acquire (rc=$RC): $OUT"; fi
OUT="$(run release dispatch)"; RC=$?
if [ "$RC" -eq 0 ]; then ok "owner releases"; else fail "release (rc=$RC): $OUT"; fi

# 2. held by a LIVE other process → exit 2 BLOCKED
sleep 60 & HOLDER=$!
env AGENT_LOCK_ROOT="$TMP/locks" LOCK_OWNER_PID=$HOLDER bash "$CLI" acquire dispatch >/dev/null 2>&1
OUT="$(run acquire dispatch)"; RC=$?
if [ "$RC" -eq 2 ] && grep -q "BLOCKED" <<<"$OUT"; then ok "live-held → exit 2 BLOCKED"; else fail "live-held (rc=$RC): $OUT"; fi

# 3. release by non-owner refused (exit 3), lock intact
OUT="$(run release dispatch)"; RC=$?
if [ "$RC" -eq 3 ] && [ -d "$TMP/locks/dispatch.lock.d" ]; then ok "non-owner release refused"; else fail "non-owner release (rc=$RC)"; fi
kill "$HOLDER" 2>/dev/null; wait "$HOLDER" 2>/dev/null

# 4. dead owner → stolen on next acquire
OUT="$(run acquire dispatch)"; RC=$?
if [ "$RC" -eq 0 ]; then ok "dead-owner lock stolen on acquire"; else fail "steal (rc=$RC): $OUT"; fi
run release dispatch >/dev/null

# 5. status lists held locks; empty after all released
run acquire cron-bugfix >/dev/null
OUT="$(run status)"
if grep -q "cron-bugfix" <<<"$OUT"; then ok "status lists held locks"; else fail "status: $OUT"; fi
run release cron-bugfix >/dev/null
OUT="$(run status)"
if ! grep -q "cron-bugfix" <<<"$OUT"; then ok "status empty after release"; else fail "status not empty: $OUT"; fi

# 6. name validation: path-traversal characters rejected
OUT="$(run acquire '../evil')"; RC=$?
if [ "$RC" -eq 64 ]; then ok "bad name rejected (64)"; else fail "name validation (rc=$RC): $OUT"; fi

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
