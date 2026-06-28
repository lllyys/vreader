---
branch: feat/feature-124-wi-1-txt-selection-core
threadId: codex-exec-f124-wi1
rounds: 1
final_verdict: ship-as-is
date: 2026-06-28
---

# Feature #124 WI-1 (foundational) — TXT highlight pure-logic core

`TxtSelection` (half-open `Utf16Range` + `isValid` — bounds / non-empty / non-negative
/ mid-surrogate), `TxtSourceOffsets` (`sourceOffset` + `chunkRanges` source→per-chunk
split), `TxtHighlightHitTester` (tapped offset → newest containing highlight).

Files: `reader/TxtSelection.kt`, `reader/TxtSourceOffsets.kt`, `reader/TxtHighlightHitTester.kt`
+ `test/.../reader/{TxtSelectionValidateTest,TxtSourceOffsetsTest,TxtHighlightHitTesterTest}.kt`.

## Round 1 — findings

**No findings.** Codex verdict clean: half-open semantics consistent; surrogate-boundary
validation correct (low surrogate preceded by high; `offset == length` allowed);
`chunkRanges` handles empty docs / chunk boundaries / EOF clamping with no off-by-one or
loop risk; hit-test is start-inclusive/end-exclusive with newest-`createdAt` precedence.

## Tests
- `TxtSelectionValidateTest` (3), `TxtSourceOffsetsTest` (4), `TxtHighlightHitTesterTest` (4) — **SUCCEEDED** (JVM).

## Verdict
**ship-as-is.** Pure logic, fully unit-tested incl. surrogate/CJK + chunk-boundary edges.
