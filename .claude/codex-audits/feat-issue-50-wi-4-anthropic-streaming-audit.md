---
branch: feat/issue-50-wi-4-anthropic-streaming
threadId: 019e1612-4d44-7693-9b6f-ee20fecd3eed
rounds: 2
final_verdict: ship-as-is
date: 2026-05-11
---

# Codex audit log — feature #50 WI-4 (AnthropicProvider streaming)

WI-4 of `dev-docs/plans/20260510-feature-50-multi-provider-ai.md`.
Adds the SSE-streaming `streamRequest` for the Anthropic Messages API.
Splits the streaming implementation into a dedicated extension file to
keep both source files under the ~300-line convention.

## Files in scope

- `vreader/Services/AI/AnthropicProvider.swift` (229 LOC after split)
- `vreader/Services/AI/AnthropicProvider+Streaming.swift` (new, 130 LOC)
- `vreaderTests/Services/AI/AnthropicProviderStreamingTests.swift` (new, 539 LOC, 16 tests)
- `vreaderTests/Services/AI/AnthropicProviderTests.swift` (modified — retired the obsolete WI-3 stub-assertion test)

## Round 1 — initial audit (1 High + 1 Medium + 3 Low)

### High — premature transport EOF silently reported as success
> The stream finishes cleanly on transport EOF even if Anthropic never sent `message_stop`. That turns a truncated/broken stream into silent success.

**Fix applied** — Track `sawMessageStop` flag inside the streaming
`Task`. Set true in the `message_stop` case; after the
`for try await line in bytes.lines` loop, if
`!sawMessageStop && !Task.isCancelled`, throw
`AIError.providerError("\(providerName) stream ended before message_stop — connection likely dropped mid-response.")`.

New test `streamRequest_eofBeforeMessageStop_throwsProviderError`
exercises this path — pre-EOF deltas still delivered AND error
surfaces after.

### Medium — streaming HTTP-error body excerpt dropped
> `session.bytes(for:)` is followed by `validateHTTPResponse(response, data: nil)`, so 4xx/5xx paths degrade to `"HTTP <code>: No body"` instead of the required `"HTTP <code>: <body excerpt>"`.

**Fix applied** — New `validateStreamingHTTPResponse(_:bytes:)` async
helper. On 2xx returns immediately leaving the bytes stream for the SSE
loop. On non-2xx, drains up to 1024 bytes into a buffer, then calls
`validateHTTPResponse(response, data: buf)` so the existing
`"HTTP <code>: <excerpt>"` path produces the right message. Cap at
1024 because error bodies are typically small JSON; reading more
risks blocking on a slow server. Body-read failure during the drain
is swallowed — the HTTP code still surfaces.

New test `streamRequest_5xx_includesBodyExcerpt` asserts that a 503
with body `{"type":"error","error":{"type":"api_error","message":"upstream timeout"}}`
produces an error message containing both `503` AND
`upstream timeout` / `api_error`.

### Low — malformed `data:` lines not logged
> The WI-4 audit target was "log-and-skip", and today this path fails silently.

**Fix applied** — Added
`private let streamingLog = Logger(subsystem: "com.vreader.app", category: "AnthropicProviderStreaming")`
at file scope. Malformed-data-line path now emits
`streamingLog.warning("\(providerName, privacy: .public) stream: skipping malformed data line (len=\(payload.count))")`
before `continue`.

### Low — missing tests for 403 streaming + `capturedRequests` assertion
> One 403 streaming test asserting the profile-scoped authorization message, and `capturedRequests.isEmpty` on the non-HTTPS preflight test.

**Fix applied** —
- New `streamRequest_403_throwsAuthorizationFailed_distinctFrom401`
  uses `providerName: "MyCustomProfile"`; asserts message contains
  `403`, mentions authorization/access/model/workspace,
  AND interpolates `MyCustomProfile`.
- `streamRequest_rejectsNonHTTPSNonLocalhost` now also asserts
  `AnthropicStreamingStubURLProtocol.capturedRequests.isEmpty`.
- `streamRequest_401_throwsAuthenticationFailed` now also asserts
  the message does NOT contain `workspace` (keeps 401 distinct from
  403).

### Low — file size over 300-line convention (311 LOC)
> Split streaming parsing / HTTP validation into a helper or extension.

**Fix applied** — Split `AnthropicProvider.swift` into:
- `vreader/Services/AI/AnthropicProvider.swift` (229 LOC) — struct,
  init, `sendRequest`, `buildURLRequest`, `buildSystemPrompt`,
  `buildUserMessage`, `validateHTTPResponse`.
- `vreader/Services/AI/AnthropicProvider+Streaming.swift` (130 LOC) —
  extension with `streamRequest` + `validateStreamingHTTPResponse`.

Visibility of `session`, `buildURLRequest(for:stream:)`, and
`validateHTTPResponse(_:data:)` changed from `private` to default
(internal) so the same-module extension can use them.

## Round 2 — verification

Codex re-read both source files and the updated test suite. Verdict:
**ship-as-is**.

> "All 5 round-1 findings are addressed in the current code. … I don't see a new concurrency or contract issue from the fixes. `sawMessageStop` is task-local, `URLSession.AsyncBytes` use is fine under Swift 6 strict concurrency, and the drain-then-throw helper is a reasonable shape for this scope. Default visibility here is already `internal`; making it explicit is optional, not necessary. The 1024-byte cap is reasonable for error excerpts."

Round-2 minor note (does NOT change verdict): the round-2 reply
summary said the new 403 test "asserts `permission_error` from the
body" — the test actually asserts the distinct 403/providerName/access
wording, not the body token itself. This is informational only;
Codex explicitly stated it doesn't gate the verdict.

## Wire-format check

Verified against Anthropic streaming docs (read 2026-05-11):
- `event: <name>\ndata: <json>\n\n` event delimiting — handled by
  `URLSession.AsyncBytes.lines`.
- Dispatch on the `type` field of each `data:` line's JSON.
- `content_block_delta` with `{delta: {type: "text_delta", text}}`
  yields the text chunk.
- `message_stop` is the terminal event — sets `sawMessageStop` flag,
  yields `isComplete=true`, finishes the stream.
- `error` event raises through `AIError.providerError`.
- `message_start`, `content_block_start`, `content_block_stop`,
  `message_delta`, `ping`, and any unknown event types are silently
  skipped (forward-compat for future SSE event additions).
- Premature transport EOF surfaces as a truncation error (NOT silent
  success).

## Test results

36/36 GREEN under
`xcodebuild test -only-testing:vreaderTests/AnthropicProviderStreamingTests -only-testing:vreaderTests/AnthropicProviderTests`:

- WI-3 sendRequest suite: **20/20** GREEN (was 21; retired
  `streamRequest_inWI3_returnsNotImplementedError` — purpose obsolete
  since WI-4 ships real streaming, replaced with a one-line cross-ref
  comment pointing at `AnthropicProviderStreamingTests`).
- WI-4 streamRequest suite: **16/16** GREEN.

## Summary

WI-4 ships clean. The next WI is WI-5 (AIService dispatches by
provider kind) — needs WI-2 + WI-3 + WI-4 done. WI-5 will plug
`AnthropicProvider` into the AIService factory so production callers
finally exercise the path covered by WI-3 + WI-4.
