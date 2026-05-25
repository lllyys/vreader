---
branch: fix/issue-1152-bilingual-translation-misaligned
threadId: 019e60ca-d085-7c21-87c0-9b7879610d87
rounds: 1
final_verdict: follow-up-recommended
date: 2026-05-26
---

# Codex audit — Bug #266 / GH #1152 (bilingual translation misaligned)

Independent audit (Codex MCP, separate process) of the fix for the bilingual
wrong-pairing defect: the render-side DOM enumerate double-counted nested
blocks (`<blockquote><p>` enumerates both) while the translation-side
`ChapterSegmenter` did not, and the `min(count)` positional zip drifted every
later pairing → paragraph N's translation under the wrong paragraph.

Files audited:
- `vreader/Views/Reader/Bilingual/BilingualPairing.swift` (new — shared 1:1 contract)
- `vreader/Views/Reader/Bilingual/EPUBBilingualPipeline.swift` (delegate)
- `vreader/Views/Reader/Bilingual/FoliateBilingualPipeline.swift` (delegate)
- `vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift` (leaf-only enumerate)
- 3 test files (37 bilingual tests green)

## Fix shape

1. **EPUB enumerate → leaf blocks only**: skip a block element that contains
   another block element (`el.querySelector(BLOCK_SELECTOR)`), so the DOM block
   count matches the plain-text paragraph segmentation for nested structures.
2. **Shared count-safety** (`BilingualPairing.translationsByBid`, both pipelines
   delegate): pair by index ONLY when `blocks.count == segments.count`; any
   mismatch → empty (source-only). Replaces the old `min(count)` partial pairing.

## Round 1 findings

| # | Severity | Finding | Resolution |
|---|---|---|---|
| 1 | Medium | Leaf-fix removes the reported `blockquote>p` double-count but doesn't make the EPUB block model fully equal to `ChapterSegmenter`: a leaf `<pre>` with internal blank lines (1 DOM block vs N text paragraphs) and a mixed-content `<blockquote>lead<p>…</p>tail` (container direct text in plain text but not in the leaf enumerate) still diverge → whole-chapter source-only. | **Accepted + follow-up.** Contract-compliant: residual divergence → source-only (fail-safe, never a wrong pairing — satisfies acceptance criterion 2). The reported repro is correctly paired. The architecturally-complete fix (translate the enumerated block `text[]` directly → 1:1 by construction) is a larger reflow filed as a follow-up (Bug #268), with the Foliate-host enumerate leaf-fix. |
| 2 | Low | Tests prove the `querySelector` guard presence + empty-on-mismatch, but not the real-source-path count-alignment (`<pre>` would still pass). | **Accepted.** The enumerate is a JS DOM walk, not executable in a Swift unit test (no DOM). Coverage split: Swift tests prove mismatch→empty; JS-source pin proves the leaf-skip guard; end-to-end nested-block render is fixture-backed device verification (nested-block EPUB fixture is verification debt, noted in the follow-up — same class as #267). |
| nit | — | `bilingualEnumerateJS` doc mentioned `div`/heading behavior the impl no longer has. | **Fixed** — doc now describes leaf-block enumeration. |

## Codex confirmations (no change needed)

- `el.querySelector(BLOCK_SELECTOR)` semantics correct: descendants-only — keeps a leaf `<p>`, skips a `<blockquote>` containing `<p>`, keeps an inline-only `<li>`; sibling decoration `<div>` nodes are irrelevant (siblings ≠ descendants, `div` ∉ BLOCK_TAGS) → no re-stamp regression.
- Shared `BilingualPairing` is the right home for the 1:1 rule; delegating both EPUB + Foliate is sound. Foliate host can still overcount, but the helper turns that into source-only (fail-safe).
- Whole-chapter drop is coarse but the safe choice under the current data model.
- Empty / nil / CJK / single-block edge cases fine. No Swift 6 / concurrency issue.

## Verdict

**Ship-as-is for Bug #266's scope (follow-up-recommended).** The wrong-pairing
defect + the never-wrong invariant are fixed; the residual-structure correctness
+ Foliate host leaf-fix + nested-structure fixture are tracked as follow-up
(Bug #268). 37 bilingual tests green; full suite green (see PR).
