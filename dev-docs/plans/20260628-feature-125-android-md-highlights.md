# Feature #125 — Android MD highlights & notes (Phase 3, #110 driver)

> Last highlighting feature for checklist item **B**: #123 EPUB ✓ + #124 TXT ✓ +
> **#125 MD (this)**. Reuses #124's whole selection engine; the new problem is the
> MD rendered↔source offset mapping (the markers `MarkdownRenderer` strips).

## Problem

`MarkdownRenderer.render(chunk)` drops markers (`# `, `**…**`, `` `code` ``, `\`, `- ` → `• `),
so a rendered offset ≠ source offset. #124's TXT highlighting assumes render == source and is
gated to `BookFormat.txt`; MD is render-only. This feature builds the per-chunk rendered↔source
map and threads a **format-aware offset mapper** through the engine so MD gets the same
select → highlight/note/copy/share → persist → re-render → tap-edit/remove flow.

## The mapping contract (the load-bearing design — Gate-2 fixes)

### `MarkdownOffsetMap` (per-rendered-char source SPANS — dual-affinity, Gate-2 r2 High)

A single cursor array is insufficient: a rendered cursor can sit at BOTH the end of one visible run
and the start of the next across a stripped marker (`**bold**x`: rendered cursor 4 is the end of
"bold" at source 6 AND the start of "x" at source 8 — one value can't serve both). So
`renderWithMap(chunk): MarkdownRendered(text, srcStart: IntArray, srcEnd: IntArray)` stores, **per
rendered char** `r` (length `text.length`), the SOURCE span `[srcStart[r], srcEnd[r])` of the source
chars that produced it (usually 1; an escaped `\*`→`*` spans 2 source chars `[k, k+2)`; an inserted
`• ` bullet glyph maps to the bullet marker source span `[0, 2)`; a trailing `\n`/`\r\n` maps to its
own source span). Worked example `**bold**x` (rendered "boldx"): `srcStart=[2,3,4,5,8]`,
`srcEnd=[3,4,5,6,9]`.

Conversions:
- `renderedRangeToSource([a, b)): Utf16Range` = `[srcStart[a], srcEnd[b-1])` for `b > a` (start = left
  edge of char `a`; end = right edge of char `b-1`). `**bold**x` rendered `[0,4)` → `[2,6)` ("bold",
  excluding markers); rendered `[4,5)` → `[8,9)` ("x"). Resolves the audit's `**bold**x` / `**bold**\n` case.
- `sourceRangeToRendered([s0, s1)): Utf16Range` (clamped, affinity-correct): rendered start = the
  first `r` with `srcEnd[r] > s0` (first visible char whose source overlaps the range); rendered end =
  one past the last `r` with `srcStart[r] < s1`. A marker-only source range (no rendered char overlaps)
  collapses to EMPTY → the wash draws nothing there.
- `renderedCursorForSourceStart(s0)` / `renderedCursorForSourceEnd(s1)` — the explicit start/end-affinity
  cursors (the end-affinity one positions the popover anchor at the selection end's `getCursorRect`).

### `ChunkTextMapper` (format-aware; threaded through EVERY identity assumption — Gate-2 High)

A real interface (not a nullable map) owning all conversions, so MD's mapping reaches `beginAt`'s
`getWordBoundary` + `selectionEndAnchorWindow` + `hitAt` + the wash, not just `hitAt`:

```
interface ChunkTextMapper {
    fun renderedText(chunkIndex: Int): AnnotatedString                          // TxtBody draws this (shared cache)
    fun renderedRangeToSource(chunkIndex: Int, r: Utf16Range): Utf16Range
    fun sourceRangeToRendered(chunkIndex: Int, s: Utf16Range): Utf16Range       // chunk-local (clamped)
    fun renderedCursorForSourceEnd(chunkIndex: Int, sourceEnd: Int): Int        // popover anchor (end-affinity)
    fun visibleText(chunkIndex: Int, renderedRange: Utf16Range): String         // copy/share/UI
    fun sourceText(chunkIndex: Int, sourceRange: Utf16Range): String            // textQuote/anchor
}
```

`renderedText` makes the mapper the SINGLE per-chunk render+cache owner (Gate-2 r2 Medium): `TxtBody`,
the controller, and the wash all read the same cached `MarkdownRendered` — no recompute, no downcast.

- `IdentityChunkTextMapper` (TXT): every conversion is identity.
- `MarkdownChunkTextMapper` (MD): lazily computes + caches `renderWithMap(chunk)` per chunk and
  delegates to the `MarkdownOffsetMap`. Cached on a small LRU (only visible + highlighted chunks).

## Surface area

### New — `MarkdownRenderer` (WI-1)

- Refactor `parseInline`/`parseCode`/`parseStar`/`parseUnderscore` to parse `content` by **absolute
  index** (signatures `(content, start, end, …)` — no substrings), recording each appended rendered
  char's source index into a parallel builder. Helpers become **range-aware**: `findUnescaped(s, from,
  until, marker)`, `isEscaped(s, pos, lowerBound)` (Gate-2 Medium — don't search past the inline range
  or count backslashes before its lower bound). `renderWithMap(chunk): MarkdownRendered`. `render()`
  delegates to `renderWithMap(chunk).text` (so #112 callers are byte-identical — a regression test guards it).

### New — `MarkdownOffsetMap` + `ChunkTextMapper` (WI-2, pure)

The map + its conversions (above) + the two `ChunkTextMapper` impls. Pure, exhaustively unit-tested.

### Modified — engine integration (`com.vreader.app.reader`) (WI-3)

- `TxtSelectionController` takes a `ChunkTextMapper`; `beginAt` (word boundary is RENDERED → map to
  source), `extendTo`, `hitAt` (tap rendered → source), `selectionEndAnchorWindow` (source → rendered
  cursor → `getCursorRect`) all route through it. `selectedSourceText()` (markdown source, for
  `textQuote`/anchor) + `selectedVisibleText()` (rendered, for copy/share/UI) — Gate-2 High.
- `TxtWashMapper.washesByChunk` projects a highlight's SOURCE range → the chunk's RENDERED range via
  `sourceRangeToRendered` (the wash `getPathForRange` needs rendered indices); marker-only ranges draw nothing.
- `TxtReaderActivity`: build the mapper from `s.book.originalFormat` (Identity for txt, Markdown for md);
  **remove the `BookFormat.txt`-only gate** → controller + gesture + washes for both. The locator uses
  `book.originalFormat.name` (NOT hardcoded `"txt"` — the Gate-2 **Critical**: MD key is `md:…`, else
  `requireSameBook` fails). `TxtBody` for MD renders via `renderWithMap` (the controller/wash reuse the
  same cached map). Persist `selectedText = visible`, `locator.textQuote = source`.
- **Map dataflow** (Gate-2 High): the per-chunk maps are computed **lazily by the `MarkdownChunkTextMapper`
  on demand** (per visible/highlighted chunk, LRU-cached) — NOT precomputed for all 100k chunks. The
  controller + wash mapper share the one `ChunkTextMapper` instance, so a chunk's map is computed once.

### Files OUT of scope

EPUB (#123) / PDF; the review sheet + bookmark creation (item F); live translate (#119); iOS (rule 48);
multi-line markdown (the renderer is single-line by design — selection clamps per chunk, already the model).

## Work-item sequencing (WI-1 split per Gate-2)

| WI | Tier | Scope | PR size |
|---|---|---|---|
| WI-1 | foundational | `MarkdownRenderer.renderWithMap` parity: the absolute-index refactor + range-aware helpers + the raw `renderedToSource`. **`render()` output byte-identical** (regression). Tests: render-unchanged for every construct; the raw map's char origins for plain/heading/bold/italic/code/bullet/escape/nested/unmatched + CJK/emoji + CRLF/EOL. | L |
| WI-2 | foundational | `MarkdownOffsetMap` conversions (renderedRange↔source, `sourceRangeToRendered` clamped/affinity, marker-only→empty) + `ChunkTextMapper` (Identity/Markdown, LRU cache). Tests: golden `**bold**`/`` `code` ``/`# h`/`\*`/bullet rendered↔source; marker-only collapse; round-trips. | M-L |
| WI-3 | behavioral | Thread `ChunkTextMapper` through the controller + wash; remove the TXT gate; `originalFormat.name` locator; visible/source text; MD `renderWithMap` in `TxtBody`. Tests: MD select→source range, MD wash→rendered range (connected); `requireSameBook` passes for MD. | L |
| WI-4 | behavioral (final) | Acceptance on a `.md` fixture: long-press a styled MD line → popover → create (source anchor, visible text) → re-render wash → tap-edit/remove. Evidence. | M |

## Test catalogue

- `MarkdownRenderParityTest` (JVM, WI-1): `render()` identical to the pre-refactor output for the full construct set; the raw map char-origins.
- `MarkdownOffsetMapTest` (JVM, WI-2): golden rendered↔source incl. `**bold**` rendered `[0,4)`→source `[2,6)`, `` `code` ``, heading text, `\*` (2→1), bullet `• `, marker-only source→empty rendered, CRLF/EOL sentinel, CJK/emoji surrogate.
- `ChunkTextMapperTest` (JVM): Identity vs Markdown; LRU caches one map per chunk; conversions round-trip.
- `MdHighlightConnectedTest` (emulator, WI-3): MD select→addHighlight (visible `selectedText`, source `textQuote`)→persist→reload→wash recomputes to RENDERED ranges; `requireSameBook` passes (md key).
- `MdReaderHighlightUiTest` (emulator, WI-4): long-press a styled MD line → popover → create → wash renders; tap → edit/remove. (MD routes through `TxtReaderActivity`; a `.md` fixture asset.)

## Risks + mitigations

- **R1 — the parser refactor** (Gate-2): split into WI-1 (parity + raw map) then WI-2 (conversions);
  exhaustive golden tests; `render()`-unchanged regression guards behavior. Range-aware helpers.
- **R2 — cursor-boundary off-by-one at marker edges**: explicit cursor semantics (above) + golden
  `[0,4)`→`[2,6)` tests; `sourceRangeToRendered` clamps with start/end affinity.
- **R3 — visible-vs-source**: `selectedVisibleText`/`selectedSourceText`; persist visible as
  `selectedText`, source as `textQuote`; tests assert BOTH for a `**bold**` highlight.
- **R4 — locator format** (Gate-2 Critical): `originalFormat.name`; an MD `requireSameBook` test.
- **R5 — map dataflow**: lazy per-chunk LRU in `MarkdownChunkTextMapper`, shared by controller + wash —
  no upfront 100k-chunk cost; a chunk's map computed once.

## Backward compat

Additive: no schema change (reuses #124 tables + `AnnotationAnchor.Text`). `render()` byte-unchanged
(delegates), so #112 is unaffected. MD highlights use the same `text-document:<key>` `sourceUnitId` +
source-offset anchor; `locator.format` becomes the real `originalFormat.name`.

## Revision history

- v1 (2026-06-28) — initial plan.
- v3 (2026-06-28) — **Gate-2 round-2 fixes** (Codex gpt-5.5/high; 1H/3M, no Critical): replaced the
  single `renderedToSource` cursor array with per-rendered-char source SPANS (`srcStart`/`srcEnd`) —
  dual-affinity, resolving the `**bold**x` "one cursor, two meanings" High + the `sourceRangeToRendered`
  affinity Medium (now `srcEnd[r] > s0` / `srcStart[r] < s1`); split `sourceCursorToRendered` into the
  explicit `renderedCursorForSourceEnd` (anchor end-affinity); added `renderedText(chunkIndex)` to
  `ChunkTextMapper` so it's the single render+cache owner (`TxtBody`/controller/wash share it, no
  recompute/downcast); added golden tests for `**bold**x`, `**bold**\n`, `` `code`x ``, escaped-marker-then-text,
  bullet-then-text. **Gate-2 clean** (the 4-WI split is confirmed right).
- v2 (2026-06-28) — **Gate-2 round-1 fixes** (Codex gpt-5.5/high; 1C/5H/3M; verdict fix-then-proceed +
  split WI-1): `book.originalFormat.name` locator (Critical — MD key ≠ "txt"); cursor-boundary map
  semantics with the `**bold**`→`[2,6)` worked example + EOF-sentinel fix (High); `ChunkTextMapper`
  interface threaded through beginAt/word-boundary/anchor/hitAt/wash, not just hitAt (High);
  `sourceRangeToRendered` clamped/affinity + marker-only→empty (High); `selectedVisibleText`/
  `selectedSourceText` split, persist visible/source distinctly (High); lazy per-chunk LRU map dataflow
  shared by controller+wash (High); range-aware helpers + EOL/CRLF mapping (Medium); WI-1 split into
  parity (WI-1) then conversions (WI-2). Pending Gate-2 round-2 re-audit.
