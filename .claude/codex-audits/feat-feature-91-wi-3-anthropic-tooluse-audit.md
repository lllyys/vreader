---
branch: feat/feature-91-wi-3-anthropic-tooluse
threadId: 019e90ba-cfd5-7b60-b6a9-1ef9330e025c
rounds: 3
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex Audit — Feature #91 WI-3 (Anthropic tool-use)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48).

## Scope

Behavioral WI-3 — the first provider tool-use impl:

- `AnthropicProvider+ToolUse.swift` (new) — `supportsToolUse=true` + `sendToolRequest`; `buildToolURLRequest` (tools body + multi-turn messages); static encoders (tool/message/block → Anthropic JSON); `parseToolResponse`/`parseToolTurn`; `validateToolHistory`.
- `AnthropicProvider.swift` — extracted `makeMessagesURLRequest(validatingMaxTokens:)` (shared scaffolding).
- `AnthropicProviderToolUseTests.swift` (new).

## Round 1 — findings (threadId 019e90ba-cfd5-7b60-b6a9-1ef9330e025c)

The audit **confirmed the wire format is correct** per the Anthropic Messages API
docs (`input_schema`, `tool_use {id,name,input}`, `tool_result {tool_use_id,content,is_error}`
in a user-role message, `max_tokens` required). The findings were robustness gaps:

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| AnthropicProvider+ToolUse.swift `sendToolRequest` | **High** | `stop_reason` ignored — a `max_tokens` truncation could silently downgrade a partial trailing `tool_use`. | **Fixed.** Extracted `parseToolResponse(_ json:)`; rejects `stop_reason == "max_tokens"` with a clean retriable `AIError.providerError`; normal stop reasons parse through. (Round-2 RESOLVED.) |
| AnthropicProvider+ToolUse.swift `buildToolURLRequest` | **Medium** | No history validation — Anthropic requires `tool_result` to immediately follow the `tool_use` turn, tool_result-blocks-first, AND every `tool_use` id answered. A malformed caller 400s on the wire. | **Fixed (2 iterations).** `validateToolHistory` enforces adjacency + tool_result-first (round 1), THEN every assistant `tool_use` id has a matching `tool_result` in the next user turn (round-3 — the round-2 gap). RESOLVED round 3. |
| AnthropicProvider+ToolUse.swift / AnthropicProvider.swift | Low | `makeMessagesURLRequest` validated the PROFILE `maxTokens`, not the effective per-request budget — the documented override was ineffective if the profile value was bad. | **Fixed.** `makeMessagesURLRequest(validatingMaxTokens:)` validates the EFFECTIVE budget the caller emits. (Round-2 RESOLVED.) |

## Rounds 2 (threadId 019e90ce) / 3 (threadId 019e90de)

- R2: High + Low RESOLVED; Medium partially (adjacency/ordering done, but missing the tool_use-id-coverage check) → NOT.
- R3: `validateToolHistory` now requires `toolUseIDs.isSubset(of: resultIDs)` (every tool_use answered) — **RESOLVED**, consistent with Anthropic's "one tool_result per tool_use" rule. No new findings.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 3. `AnthropicProviderToolUseTests`
green (body shape, encoders, `parseToolResponse` stop_reason handling, history
validation incl. missing-id, effective-budget) + `AnthropicProviderTests` regression
green (the `makeMessagesURLRequest` extraction is behavior-preserving for plain chat).
Slice device-verification against a real Anthropic provider is planned at the
feature's final-WI acceptance.
