---
branch: feat/feature-125-wi-1-md-render-map
threadId: 019f122e-1530-72b0-85d4-e786055f979e
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #125 WI-1 (MarkdownRenderer.renderWithMap source-span map)

Independent Codex audit (gpt-5.5, high reasoning, read-only sandbox) of WI-1:
extend the pure-JVM `MarkdownRenderer` with `renderWithMap(chunk): MarkdownRendered`
emitting, per rendered char, the source span `[srcStart[r], srcEnd[r])` of the
markdown-source chars that produced it. `render()` now delegates to
`renderWithMap(chunk).text` and must stay byte-identical.

## Findings — none

> "No findings. The source-span map stays bounded and length-aligned with
> `AnnotatedString.text.length`; bullet insertion maps both glyphs to `[0,2)`;
> escaped markers, empty/unmatched markers, nested emphasis, adjacent markers,
> EOL, CJK, and surrogate-pair UTF-16 indexing look correct."

Audit focus covered: correctness of the source-span mapping across constructs
(plain / heading / bold / italic / code / bullet / escape / nested emphasis /
adjacent markers / surrogate pairs); `render()` byte-identity; the
`srcStart`/`srcEnd` length invariant (== `text.length`, never out of source
bounds); the `appendInserted` bullet glyph `[0,2)` mapping; off-by-one in
`findUnescaped`/`isEscaped`/`parseStar`/`parseUnderscore`/`parseCode` under the
new absolute-index signatures; Kotlin/dead-code/perf.

## Test evidence

- `MarkdownRenderMapTest` — 10/10 (the new source-span map cases).
- `MarkdownRendererTest` — 29/29 (the pre-#125 #112 parity suite, confirming
  `render()` is byte-identical).
- `AiMarkdownRendererTest` — 5/5 (unrelated, unaffected).

## Verdict

ship-as-is. WI-1 is foundational (no user-observable behavior change — `render()`
output unchanged); the map is consumed by WI-2's `MarkdownOffsetMap` /
`ChunkTextMapper`.
