---
branch: feat/feature-91-wi-1-tool-dtos
threadId: 019e9051-4864-7a90-91f7-b58da0326b41
rounds: 3
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex Audit — Feature #91 WI-1 (agentic tool-calling DTOs)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48).

## Scope

Foundational WI-1 — the pure `Sendable` tool-calling DTOs (no provider/registry/
loop yet): `vreader/Services/AI/AITool.swift` (`JSONValue` + Codable + Foundation
bridge; `ToolDefinition`/`ToolCall`/`ToolResult`; `AITool` protocol;
`ToolTurnMessage`/`ToolContentBlock`; `AIToolRequest`; `AIToolTurn`) +
`vreaderTests/Services/AI/AIToolDTOTests.swift`.

## Round 1 — findings (threadId 019e9051-4864-7a90-91f7-b58da0326b41)

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| AITool.swift `AIToolTurn` | **Medium** | `.text` vs `.toolCalls([ToolCall])` couldn't represent "text + tool_use in one turn" (Anthropic interleaves them) — WI-3/7 would drop assistant text. | **Fixed (2 iterations).** First attempt `case toolCalls(text: String?, calls:)` preserved only one preamble (round-2 still NOT). Final: `case toolUse(blocks: [ToolContentBlock])` preserves the FULL ordered blocks (any multiplicity/order) + `toolCalls`/`assistantText` extractors. Round-3 RESOLVED. |
| AITool.swift:84 `JSONValue.number` | **Medium** | `.number(Double)` accepted non-finite (NaN/±Inf) → broke `Equatable` reflexivity + would crash `JSONSerialization` at the provider boundary. | **Fixed.** Added recursive `isWellFormed`; `encode(to:)` + `toFoundation()` null-coerce non-finite before any `JSONSerialization` boundary. Round-2 RESOLVED. |
| AIToolDTOTests.swift:38 | Low | The integer-emission test exercised `JSONEncoder`, not the load-bearing `toFoundation()` path. | **Fixed.** Test now asserts `JSONValue.number(8).toFoundation() is Int` + a `JSONSerialization` round-trip (`"n":8`, not `8.0`). Round-2 RESOLVED. |

### Round-1 "non-findings" confirmed
- `JSONValue.init(from:)` decode order (Bool-before-Double) is **sound** — `JSONDecoder` does not coerce `1`/`0` to `Bool` or `true`/`false` to `Double`.
- `ToolResult.toolUseID` alone is sufficient — both Anthropic and OpenAI key tool replies by call id, not tool name.
- `ToolContentBlock` synthesized `Codable` round-trips for internal use (WI-3/4 keep custom wire serialization).

## Round 2 (threadId 019e9063) / Round 3 (threadId 019e9074)

- R2: non-finite + test-strengthen fixes RESOLVED; `AIToolTurn` first attempt still lossy (NOT).
- R3: `AIToolTurn` redesigned to `case toolUse(blocks: [ToolContentBlock])` — **RESOLVED**, no new findings.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 3. `AIToolDTOTests` green
(JSONValue Codable + Foundation-bridge round-trips, non-finite rejection, lossless
tool-use turn, DTO value semantics).
