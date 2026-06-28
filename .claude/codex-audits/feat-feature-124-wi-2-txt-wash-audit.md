---
branch: feat/feature-124-wi-2-txt-wash
threadId: codex-exec-f124-wi2
rounds: 1
final_verdict: ship-as-is
date: 2026-06-28
---

# Feature #124 WI-2 (behavioral) — TXT highlight wash rendering

`TxtHighlightWash` (`WashSpan` + pure `TxtWashMapper.washesByChunk` + `DrawScope.drawWashes`
via `getPathForRange`). `TxtBody` gains a `washesForChunk` param + per-chunk `onTextLayout`
capture + `Modifier.drawBehind`; the Loaded branch derives `washMap` from
`annotationsRepository.highlights(bookKey)` **only when `BookFormat.txt`** (else `flowOf(emptyMap())`).

## Round 1 — findings

**No reportable issues.** Codex verdict clean: the binding TXT gate is correct (MD gets
`flowOf(emptyMap())` → no annotation washes); `drawBehind` is sound (per-chunk state keyed by
the stable chunk index, `washes` read in the item body so a `washMap` change recomposes visible
items); `drawWashes` clamps ranges + uses exclusive-end `getPathForRange`; `washHex` `#AARRGGBB`
parses to a translucent Compose Color; render-time lookup is O(1) and only visible items draw.
Residual note (not a finding): `TxtReaderActivity` is ~456 lines; moving selection/popover state to
`TxtAnnotationController` in WI-3 is the planned next step.

## Tests
- `TxtWashMapperTest` (4, JVM) — single/multi-chunk split, multiple highlights, no-range skip.
- `TxtHighlightConnectedTest` (emulator) — highlight persists to real Room → wash recomputes to the right chunk.
- `TxtReaderActivityTest.rendersWithSeededHighlight_drawsWash_noCrash` (emulator) — the live `drawBehind`/`getPathForRange` path runs on the real TXT reader with a highlight present.

## Verdict
**ship-as-is.** Stored-highlight wash rendering works on the live reader; recompute is pure + tested; MD is gated out.
