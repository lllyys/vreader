---
branch: feat/feature-91-wi-5-tool-registry
threadId: 019e911a-6746-7502-bca3-9aebe3081261
rounds: 2
final_verdict: ship-as-is
date: 2026-06-03
---

# Codex Audit — Feature #91 WI-5 (AIToolRegistry)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48).

## Scope

Foundational WI-5 — the tool registry + `JSONValue` input accessors:

- `vreader/Services/AI/AIToolRegistry.swift` (new) — `struct AIToolRegistry: Sendable`; `run(_ call:)` dispatches + rebinds the call id; unknown tool → `isError` result (never throws); `definitions()`; `isEmpty`. Plus `JSONValue` accessors (`subscript[key]`, `stringValue`/`intValue`/`doubleValue`/`boolValue`).
- `vreaderTests/Services/AI/AIToolRegistryTests.swift` (new).

## Round 1 — findings (threadId 019e911a-6746-7502-bca3-9aebe3081261)

Call-id rebinding, fail-closed, and `Sendable` on `[String: any AITool]` all
confirmed sound. Findings:

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| AIToolRegistry.swift `definitions()` | **Medium** | Re-read each tool's LIVE `definition` instead of an init-time snapshot — a conformer with a mutable-state definition could advertise name/schema B while dispatch keyed on init-time name A. | **Fixed.** Init snapshots each `definition` once into `definitionsByName` alongside `toolsByName`; `definitions()` returns the frozen snapshot, dispatch keys on the same init-time name. No drift possible. |
| AIToolRegistry.swift init | Low | Duplicate names silently shadowed. | **Fixed.** A `Logger.warning` flags a collision (non-trapping — the "never traps" contract is load-bearing for the loop, so NOT an `assert`; last-wins retained). |
| AIToolRegistryTests.swift | Low | `intValue` large-integral boundary untested/undocumented. | **Fixed.** `intValue` documents the precision-safe `\|n\| < 2^53` range (named constant); `intValuePrecisionBoundary` pins 2^53-1 → Int, 2^53 / -2^53 / ∞ → nil. |

## Round 2 — verification (threadId 019e912c-defc-7f21-aef3-93a73d41a752)

All three **RESOLVED**, no new findings. The snapshot guarantees advertised ==
dispatched; the dup signal is a non-trapping `Logger.warning`; the boundary test
+ doc pin the precision-safe semantics.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2. `AIToolRegistryTests`
green (dispatch + id-rebinding, fail-closed unknown tool, last-wins dup, definitions
order, JSONValue accessors incl. the 2^53 boundary).
