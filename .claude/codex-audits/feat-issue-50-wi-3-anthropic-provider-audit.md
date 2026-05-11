---
branch: feat/issue-50-wi-3-anthropic-provider
threadId: 019e1585-669a-74e0-85e9-b712a919ee83
rounds: 2
final_verdict: ship-as-is
date: 2026-05-11
---

# Codex audit log — feature #50 WI-3 (AnthropicProvider, non-streaming sendRequest)

WI-3 of `dev-docs/plans/20260510-feature-50-multi-provider-ai.md`.
Adds `AnthropicProvider` as a concrete `AIProvider` for the Anthropic
Messages API. Non-streaming `sendRequest` only; `streamRequest` is a
stub that throws `AIError.providerError("...comes in WI-4...")` so
accidental WI-3-stage use surfaces clearly.

## Files in scope

- `vreader/Services/AI/AnthropicProvider.swift` (new, 197 LOC final)
- `vreaderTests/Services/AI/AnthropicProviderTests.swift` (new, 587 LOC final, 21 tests)

## Round 1 — initial audit (2 Medium + 1 Low)

### Medium 1 — `AnthropicProvider.swift:205` — 401/403 collapsed message
> `401` and `403` are collapsed into the same "check the Anthropic API key" message. `401` fits that advice, but `403` can also mean model/workspace permission denial, so the current text can misdirect users.

**Fix applied** — Split 401 and 403 into distinct cases. 401 message
talks about authentication / API-key validity; 403 message talks about
authorization / model / workspace access. Both interpolate
`providerName` so renamed profiles produce accurate errors:

```swift
case 401:
    throw AIError.providerError(
        "Authentication failed (HTTP 401) — check the \(providerName) API key for this profile."
    )
case 403:
    throw AIError.providerError(
        "Authorization failed (HTTP 403) — the \(providerName) API key for this profile lacks access to the configured model or workspace."
    )
```

New tests:
- `sendRequest_403_surfacesAuthorizationFailed_distinctFrom401` —
  asserts 403 message mentions authorization/access/model/workspace
  (not just "key wrong").
- `sendRequest_401_messageInterpolatesProviderName` — constructs
  `AnthropicProvider(providerName: "MyCustomProfile", ...)` and asserts
  the string appears in the error.

Existing test `sendRequest_401_surfacesAuthenticationFailed` updated to
assert the 401 message does NOT contain "workspace" (keeps 401 distinct
from 403).

### Medium 2 — `AnthropicProviderTests.swift:27` — URLProtocol stub race
> `AnthropicStubURLProtocol` uses unsynchronized static mutable state … If Swift Testing runs these tests in parallel, they can race and cross-contaminate. Serialize the suite or move stub state behind synchronization/per-test isolation.

**Fix applied** — Added `.serialized` trait to the suite:

```swift
@Suite("AnthropicProvider — sendRequest (WI-3)", .serialized)
struct AnthropicProviderTests {
    init() { AnthropicStubURLProtocol.reset() }
```

Chose the simplest robust fix over per-test isolation (which would add
wiring noise without measurable speedup on a 21-test suite). Rationale
documented in a comment above the `@Suite` line.

### Low — `AnthropicProvider.swift:58` — `max_tokens` not validated locally
> `max_tokens` is required by Anthropic and must be `>= 1`, but `AnthropicProvider` accepts any `Int` and will send invalid values straight to the API … Validate in the initializer or before request build and throw a local `AIError`. Add a test for `0` and negative values.

**Fix applied** — Validation moved to `buildURLRequest` (before HTTPS
guard) so misconfigured profiles surface as a clean `AIError` to UI
instead of trapping with `precondition`. Initializer remained
non-throwing for ergonomic profile loading:

```swift
guard maxTokens >= 1 else {
    throw AIError.providerError(
        "\(providerName) profile is misconfigured: max_tokens must be >= 1 (got \(maxTokens))."
    )
}
```

New tests:
- `sendRequest_rejectsZeroMaxTokens_beforeNetwork` — throws AND
  asserts `capturedRequests.isEmpty` (no network round trip burned).
- `sendRequest_rejectsNegativeMaxTokens_beforeNetwork` — same for -1.

## Round 2 — verification

Codex re-read both files and the changed lines. Verdict: **ship-as-is**.

> "I re-verified the fixes … No new findings. All three round-1 findings are correctly addressed … The validation ordering is fine. Checking `maxTokens` before the HTTPS guard is acceptable because invalid local profile config should fail before any transport concerns … I did not find any new regressions or anything material missed in round-1."

## Wire-shape correctness (confirmed in both rounds)

- POST `<baseURL>/v1/messages` (endpoint correct)
- `x-api-key: <key>` (NOT `Authorization: Bearer` — that's OpenAI)
- `anthropic-version: 2023-06-01` (GA-stable per plan)
- `Content-Type: application/json`
- Body: `model`, `max_tokens` (required), top-level `system`,
  `messages: [{role, content}]`. `stream` absent for non-streaming.
- Response parsed as `content[0].text` from the first text-type block.
- 429 `retry-after` parsed as seconds (HTTP RFC 7231 §7.1.3, matches
  plan round-1 audit finding [3]).
- HTTPS-only (with localhost HTTP exception for local-LLM proxy use).

## Test results

21 tests, all GREEN:

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:vreaderTests/AnthropicProviderTests
```

→ `Test run with 21 tests in 1 suite passed after 0.052 seconds. ** TEST SUCCEEDED **`

## Summary

WI-3 ships clean. No deferred follow-ups. WI-4 (streaming) will replace
the `streamRequest` stub.
