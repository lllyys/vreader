---
branch: feat/56-wi-4-segmenter-chunker
threadId: 019e4163-a631-77b2-b2cb-d85605b44240
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Audit — feat/56-wi-4-segmenter-chunker

**Feature**: #56 — bilingual reading mode (WI-4, foundational).
**Scope**: three pure utilities — `ChapterSegmenter` (paragraph + CJK-aware
sentence split), `ChapterTranslationChunker` (segment-boundary chunking),
`TranslationChunkContract` (strict JSON-array prompt + decode), plus the
`TranslationStyle` enum.
**Auditor**: Codex (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox.
**Thread**: `019e4163-a631-77b2-b2cb-d85605b44240`. Gate 4 — implementation audit.

## Round 1 — 3 findings (0 Critical, 0 High, 1 Medium, 2 Low)

Codex confirmed `ChapterSegmenter`, `ChapterTranslationChunker`, and
`TranslationStyle` match the plan; the chunker preserves the index-order
invariant; `TranslationStyle` is not on `AIRequest`; the strict decoder
correctly rejects non-array / numeric / nested-array / object / garbage.

1. **Medium — `stripCodeFence` truncated on embedded backticks.** It searched
   *backwards* for any `` ``` `` run, so a legitimate JSON string element
   containing backticks (e.g. `["code: ```x```"]`) was truncated and then
   mis-decoded, forcing unnecessary fallback retries.
   **Fix**: rewrote `stripCodeFence` to split into lines, drop the opening
   fence line, and drop the closing fence ONLY when the last non-blank line is
   exactly `` ``` ``. Embedded backticks are left intact.

2. **Low — decoder failure tests used `#expect(throws: (any Error).self)`** —
   too weak for a strict-contract utility.
   **Fix**: the tests now assert the specific `DecodeError` case —
   `.countMismatch(expected:actual:)` / `.notAStringArray` (`DecodeError` is
   `Equatable`).

3. **Low — undocumented zero-budget coercion.** `chunk(...)` silently coerced
   a non-positive `maxCharsPerChunk` to `1` with no documented contract or test.
   **Fix**: documented the coercion in the `chunk(...)` doc comment; added
   `zeroBudgetIsCoercedToOne_eachNonEmptySegmentOwnsAChunk` and
   `negativeBudgetIsAlsoCoercedSafely` tests.

Added tests: `decode_preservesBackticksInsideAJSONStringElement`,
`decode_openingFenceWithNoClosingFenceStillDecodes`.

## Round 2 — 0 findings

Codex confirmed the round-1 Medium is genuinely resolved (`stripCodeFence` no
longer corrupts an embedded-backtick payload and still strips a real fence),
the Low findings are resolved, and no new Critical/High/Medium was introduced.

## Disposition

Zero Critical/High/Medium after round 2. Final verdict: **ship-as-is**.
