---
branch: feat/feature-118-wi-5-ai-acceptance
threadId: 019eecd0-f118wi5
rounds: 1
final_verdict: ship-as-is
date: 2026-06-22
---

# Codex audit — feature #118 WI-5 (live AI acceptance harness)

Scope: `scripts/run-ai-roundtrip.sh` (an OpenAI-compatible SSE stub + the connected-test
invocation) and `AiRoundTripConnectedTest.kt`. Test-only verification infra — no production code.

## Round 1 — no findings (clean)

Codex confirmed:

- The stub correctly distinguishes `stream=true` (text/event-stream SSE deltas + `[DONE]`) from
  `stream=false` (one-shot `choices[0].message.content` for `testConnection`).
- Cleanup is leak-safe (the 2026-06-23 http.server-orphan lesson applied): the python stub runs
  DIRECTLY (`python3 "$STUB" "$PORT" &`, so `$!` is the real server PID), the EXIT trap kills the
  exact PID, plus a path-scoped `pkill -f "$STUB"` belt. No subshell-orphan / pgrep-waiter hazard.
- The connected test asserts the real end-to-end behavior: `testConnection()` succeeds through the
  one-shot path and `streamChat()` assembles the streamed answer through the real `HttpURLConnection`
  + bounded SSE framer over a real socket.

Verdict: **ship-as-is.** The live round-trip (`scripts/run-ai-roundtrip.sh`) passed on emulator-5554;
no leaked stub afterward (`sweep-ghosts.sh` CLEAN).
