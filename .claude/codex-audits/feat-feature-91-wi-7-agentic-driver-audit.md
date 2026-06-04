---
branch: feat/feature-91-wi-7-agentic-driver
threadId: 019e922d-ada6-7022-a695-415ca9ccbc39
rounds: 2
final_verdict: ship-as-is
date: 2026-06-04
---

# Codex Audit — Feature #91 WI-7 (AgenticChatDriver)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

Behavioral WI-7 — the bounded agentic loop:

- `vreader/Services/AI/AgenticChatDriver.swift` (new) — `protocol ToolUseSending`
  (the narrow provider seam) + `struct AgenticResult { finalText, usedTools }` +
  `struct AgenticChatDriver`. `run(...)` drives send → on `.toolUse` run each call
  via the registry, append the assistant turn losslessly + a tool_result-leading
  user turn, re-send → until `.text` or the `maxIterations` cap.
- `vreaderTests/Services/AI/AgenticChatDriverTests.swift` (new).

## Round 1 — findings (threadId 019e922d-ada6-7022-a695-415ca9ccbc39)

**No production-code defects.** The auditor confirmed the loop is hard-capped by
sends, appends assistant `.toolUse` blocks losslessly, emits a tool_result-leading
user turn in call order, snapshots `registry.definitions()` once (never re-resolves
— Gate-2 Medium), propagates a provider throw while feeding tool failures back as
`isError`, and that the `ToolUseSending` narrowing is sound for WI-8 (bridged via a
small Sendable adapter / concrete conformance). All three findings were
test-coverage gaps:

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| AgenticChatDriverTests.swift | **Medium** | No test exercised TWO completed tool rounds, so multi-resend ordering + validator-safety across >1 resend was unproven. | **Fixed.** `twoToolRoundsThenText` scripts `.toolUse(a) → .toolUse(b) → .text(done)`, asserts the 3rd request's role sequence `[user, assistant, user, assistant, user]`, and runs the real `ToolHistoryValidator.validate(...)` on the recorded multi-round history. |
| AgenticChatDriverTests.swift | Low | The cap test only asserted `finalText` non-empty — wouldn't catch a regression in the last-text-vs-fallback path. | **Fixed.** Split into `capStopsAtMaxFallback` (no-text loop → exact fallback string + send count == cap) and `capReturnsLastText` (loop with text → that last assistant text). |
| AgenticChatDriverTests.swift | Low | No test for `maxIterations` floor-to-1. | **Fixed.** `maxIterationsFloor` — `AgenticChatDriver(maxIterations: 0)` → exactly one send. |

## Round 2 — verification (threadId 019e9243-20db-7f33-8a4d-41c625d1d8d1)

All three **RESOLVED**, no new issues. The two-round test runs the real
`ToolHistoryValidator` on the multi-round history; the cap path is split into
fallback-text + last-text; the floor-to-1 guard is pinned.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2. `AgenticChatDriverTests`
green (10 tests: text-immediately/no-tools, one tool round with lossless assistant
re-append + rebound tool_result, two completed rounds + validator-safety, tool
error fed back continues the loop, multiple calls in one turn, cap fallback +
cap-last-text, `maxIterations` floor, provider-throw propagation).
