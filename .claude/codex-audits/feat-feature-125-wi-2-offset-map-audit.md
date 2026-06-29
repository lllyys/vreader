---
branch: feat/feature-125-wi-2-offset-map
threadId: 019f1235-d82b-7332-bd7d-eec67db58649
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #125 WI-2 (MarkdownOffsetMap + ChunkTextMapper)

Independent Codex audit (gpt-5.5, high reasoning, read-only sandbox) of WI-2:
`MarkdownOffsetMap` (chunk-local rendered↔source UTF-16 conversions over WI-1's
per-char source spans) + `ChunkTextMapper` (interface + `IdentityChunkTextMapper`
for TXT, `MarkdownChunkTextMapper` for MD with a lazy LRU of per-chunk maps).

## Findings — 2 Low, both fixed

| file | severity | issue | resolution |
|---|---|---|---|
| `MarkdownOffsetMap.kt` | Low | `renderedRangeToSource` clamped `start`/`end-1` AFTER deciding emptiness, so a wholly out-of-range positive range mapped to the last char's span and a negative range to the first char. | **Fixed.** Clamp to rendered-cursor space `0..n` first (`a`, `b`); if `b <= a` collapse empty at cursor `a`'s source edge; else `[srcStart[a], srcEnd[b-1])`. Added `renderedRangeToSource_outOfRange_collapsesAtEnd` test. |
| `ChunkTextMapper.kt` | Low | `IdentityChunkTextMapper.sourceRangeToRendered` / `renderedCursorForSourceEnd` returned out-of-range inputs unchanged — safe from indexing but violated the "clamped" contract for corrupt inputs. | **Fixed.** Identity conversions + the cursor now clamp to the chunk's `0..length` (`clampRange` helper). Added `identity_clampsRangeConversions` test. |

## Clean areas (auditor)

> "Conversions are otherwise affinity-correct for marker boundaries and
> marker-only collapse. Empty chunks are safe. The O(n) scans are acceptable
> given `TxtDocument.DEFAULT_MAX_CHUNK_CHARS == 4000`. The
> `LinkedHashMap(accessOrder=true)` LRU plus `getOrPut` is correct for
> main-thread use. `visibleText` vs `sourceText` behavior is correct."

## Test evidence

- `MarkdownOffsetMapTest` — 17/17 (golden rendered↔source, marker-only collapse,
  surrogate-pair offsets, round-trip, the new out-of-range clamp case).
- `ChunkTextMapperTest` — 11/11 (Identity passthrough + clamp, Markdown
  conversions, visible-vs-source, LRU bound + recompute-evicted).

## Verdict

ship-as-is. WI-2 is foundational (pure conversions, no behavior change);
consumed by WI-3's engine integration.
