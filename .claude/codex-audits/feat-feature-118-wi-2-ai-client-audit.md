---
branch: feat/feature-118-wi-2-ai-client
threadId: 019eebcc-f118wi2
rounds: 2
final_verdict: ship-as-is
date: 2026-06-22
---

# Codex audit — feature #118 WI-2 (AiClient + SSE providers)

Scope: `android/app/.../ai/{AiTypes,AiClient,SseEventReader,OpenAiCompatibleProvider,
AnthropicProvider,AiProviderFactory}.kt` + tests. The AI client over `HttpURLConnection` with
bounded SSE streaming, mirroring iOS `AIProvider`.

## Round 1 — 7 findings (2 High / 4 Medium / 1 Low)

| file:line | severity | issue | resolution |
|---|---|---|---|
| AiClient (streamChat) | High | EOF before the terminal sentinel (`[DONE]` / `message_stop`) was treated as a clean finish → a dropped/truncated stream returned a silent partial. | FIXED — track `sawTerminal`; if not seen, `ensureActive()` (so a legit cancel isn't misreported) then throw `AiError.Stream("stream ended before its terminal event")`. |
| AiClient (openPost) | High | No scheme preflight — an `http://` base sent the API key in cleartext. | FIXED — `requireSafeScheme`: `https` always; `http` only for loopback/`localhost`/`::1`/`10.0.2.2` (tests + emulator host), else `AiError.InsecureUrl`. |
| AiClient (streamChat) | Medium | Cancellation only checked between events — a blocking `reader.read()` could hang to `readTimeout` (60s). | FIXED — `coroutineContext.job.invokeOnCompletion { conn.disconnect() }` registered after open, disposed in `finally`; closing the socket unwinds the blocked read. Applied to `chat()` too (round 2). |
| AiClient (openPost) | Medium | `instanceFollowRedirects = true` on an authed POST could re-POST / forward the key on a 3xx. | FIXED — `false`; a 3xx falls to `checkStatus` → `Http(code)`. |
| AiClient (openPost) | Medium | `base + endpointPath` doubled the path when a user pastes the full endpoint (Bug #185). | FIXED — if `base.endsWith(endpointPath)` use as-is. |
| AiClient (readBoundedText) | Medium | Per-chunk `String(buf, …)` corrupts a multibyte (CJK) char split across the buffer. | FIXED — accumulate bytes into `ByteArrayOutputStream`, decode UTF-8 once. |
| AiClient (checkStatus) | Low | Reading the error body could block/throw and mask the status. | FIXED — don't read it; disconnect in finally. |

`SseEventReader` framing (blank-line boundaries, `:` comments, multi-`data:` join, `event:`,
final-event-without-trailing-blank, no-newline line bound) had no findings.

## Round 2 — verify pass

All seven confirmed fixed; the double `disconnect()` is idempotent (handler disposed in finally);
the test/emulator host allowance covers `127.0.0.1` + `10.0.2.2`; the `sawTerminal` throw doesn't
fire on a legit cancel (`ensureActive` guards). Codex's one residual note — extend the prompt-cancel
guard to `chat()` — was applied. **No open findings.**

Verdict: **ship-as-is.** 25 JVM AI tests (OpenAI 7 + Anthropic 4 + SSE 5 + Store 6 + Kind 3) + full
`:app` suite green.
