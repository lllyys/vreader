---
branch: feat/feature-125-wi-3-md-integration
threadId: 019f125e-e6db-7b12-9414-ee49480d11f6
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #125 WI-3 (engine integration: thread ChunkTextMapper)

Independent Codex audit (gpt-5.5, high reasoning, read-only sandbox) of WI-3:
thread the format-aware `ChunkTextMapper` (WI-2) through the #124 TXT-highlighting
engine so MD books get highlighting. `TxtSelectionController` + `TxtWashMapper` +
`TxtReaderActivity` (gate removed, `originalFormat.name` locator, visible-vs-source
text). The chunk `TextLayoutResult` speaks RENDERED coords; the mapper bridges to
the SOURCE coords highlights persist in.

## Findings — none

> "Clean: no Gate-4 findings in the supplied diff. The changed call sites use the
> correct coordinate direction: hit/word selection rendered→source; wash and
> in-progress selection fill source→rendered; popover anchor source-end→rendered
> cursor. TXT behavior remains identity-mapped, `selectedText()` has no remaining
> callers, MD stores visible text while persisting source quote/range, and
> `TxtBody`, wash, and controller all share the same `chunkMapper` instance.
> Marker-only and empty rendered ranges are skipped safely."

## Test evidence

- `MdHighlightWashTest` — 4/4 (JVM): an MD highlight's SOURCE range washes the
  correct RENDERED range (markers excluded); heading prefix stripped; marker-only
  draws nothing; identity unchanged for TXT.
- `MdHighlightConnectedTest` — 1/1 (**emulator**, cold-restarted): an MD highlight
  (md locator) persists to real Room and the wash recompute through a
  `MarkdownChunkTextMapper` projects it onto chunk 1's rendered `[0,4)` ("bold");
  the `md` locator format round-trips (the Gate-2 Critical).
- `TxtWashMapperTest` (JVM) + `TxtHighlightConnectedTest` (emulator) — regression,
  unchanged via the identity mapper.

## Verdict

ship-as-is. WI-3 is behavioral; the slice is verified end-to-end on the emulator.
The full long-press-gesture → popover → create/edit acceptance on a real `.md`
fixture is WI-4 (final).
