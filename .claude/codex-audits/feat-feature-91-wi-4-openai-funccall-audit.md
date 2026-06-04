---
branch: feat/feature-91-wi-4-openai-funccall
threadId: 019e90f3-57df-7543-b694-e41171092ef5
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex Audit — Feature #91 WI-4 (OpenAI function-calling)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48).

## Scope

Behavioral WI-4 — OpenAI-style function-calling for `OpenAICompatibleProvider`
(sibling to the merged Anthropic WI-3):

- `AIProvider.swift` — extracted `makeChatCompletionsURLRequest()` shared scaffolding; widened `session`/`validateHTTPResponse` to internal.
- `OpenAICompatibleProvider+ToolUse.swift` (new) — `supportsToolUse`/`sendToolRequest`; `buildToolURLRequest` maps the shared `ToolTurnMessage` model to OpenAI shape (tools as function objects, a user tool_result turn → separate `role:"tool"` messages, `arguments` as a JSON STRING, assistant `content:null` when only tool_calls); `parseToolResponse` (tool_calls → `.toolUse`, else `.text`; `finish_reason:"length"` truncation → throw).
- `AITool.swift` — `ToolHistoryValidator` (extracted shared validator).
- `AnthropicProvider+ToolUse.swift` — `validateToolHistory` → thin forwarder to the shared validator.
- `OpenAICompatibleProviderToolUseTests.swift` (new).

## Round 1 — findings (threadId 019e90f3-57df-7543-b694-e41171092ef5)

The audit **confirmed the OpenAI wire format is correct** per the OpenAI docs
(`tools[].function.parameters`, `arguments` as a JSON string, `role:"tool"` +
`tool_call_id`, `content:null` for tool-call turns; the `makeChatCompletionsURLRequest`
extraction is behavior-preserving). Both findings were robustness:

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| OpenAICompatibleProvider+ToolUse.swift `buildToolURLRequest` | **Medium** | No history validation (unlike the Anthropic sibling) — a malformed shared history serializes to an invalid OpenAI sequence (unanswered tool_call → 400). | **Fixed.** Extracted the Anthropic validator to a shared `ToolHistoryValidator.validate(_:)` in `AITool.swift`; both providers call it (Anthropic via a forwarder; OpenAI in `buildToolURLRequest`). |
| OpenAICompatibleProvider+ToolUse.swift `parseToolResponse` | **Medium** | Returned `.toolUse` on raw `tool_calls` presence, not successfully-parsed calls — an all-malformed `tool_calls` array yields a `.toolUse` with zero executable calls (would wedge WI-7's loop). (Anthropic's parse doesn't have this — it keys off successfully-parsed blocks.) | **Fixed.** Counts valid parsed calls; returns `.toolUse` only if ≥1 survives; else falls back to assistant text, else throws `AIError.invalidResponse`. |

## Round 2 — verification (threadId 019e9107-5d18-77d0-a17f-a9fb957d585d)

- **FIX 1: RESOLVED** — shared `ToolHistoryValidator` enforces the provider-agnostic invariants; Anthropic forwards (behavior-preserving); OpenAI validates on build; coverage on both sides.
- **FIX 2: RESOLVED** — `.toolUse` only when ≥1 valid call survives; the three cases (mixed→valid, all-malformed+text→text, all-malformed+no-text→throws) are covered.
- **NEW Critical/High/Medium: none.**

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2.
`OpenAICompatibleProviderToolUseTests` + `AnthropicProviderToolUseTests` green (the
shared-validator extraction is behavior-preserving for the Anthropic path). Slice
device-verification against a live OpenAI-compatible provider at the feature's
final-WI acceptance.
