---
branch: fix/issue-1579-epub-svg-cover-images
threadId: 019eabe0-ee1f-7391-859b-a5bd3197fd01
rounds: 1
final_verdict: ship-as-is
date: 2026-06-09
---

# Codex Audit — Bug #332 / GH #1579 (EPUB continuous-scroll SVG cover/title images broken)

## Root cause

`EPUBChapterBodyRewriter.rewriteAttributes` absolutized relative `src` against the
chapter dir but left `xlink:href` fragment-only (only `#frag` namespaced, everything
else untouched). EPUB cover/title pages are commonly `<svg><image xlink:href="cover.jpg"/>`;
in the #71 continuous-scroll stitch N chapters share ONE base URL, so the un-absolutized
relative `xlink:href` resolved against the wrong dir → 404 → broken-image glyph. Paged
loads each chapter as its own `loadFileURL` document, so it resolved there.

## Fix

`xlink:href` now absolutizes a relative non-fragment value against the chapter dir
(same `isAbsoluteOrFragment` gate + `join(dir:relative:)` as `src`), keeping the
`#fragment` namespacing. `href` stays fragment-only (so `<a href>` navigation is never
absolutized).

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| EPUBChapterBodyRewriter.swift (`rewriteAttributes`) | Medium | SVG2 `<image href="cover.jpg">` / `<use href="…">` (no `xlink:`) are resource refs too — WebKit supports SVG2 `href` — but `href` is fragment-only, so modern EPUBs using `href` stay broken (same bug class). | **Fixed** — added an element-scoped `rewriteSVGResourceHref` pass that absolutizes a relative `href` ONLY inside `<image>` / `<use>` opening tags (`(?<=\s)href` keeps it off the tag name and off `xlink:href`), leaving `<a href>` navigation untouched. Tests: `svg2ImageHrefAbsolutized`, `svg2UseHrefAbsolutized`, `svg2ImageHrefAbsoluteUntouched`, `anchorHrefNearImageUntouched`. |

Codex confirmed (no other findings): the new `xlink:href` branch matches `src`
semantics exactly; cross-file fragments (`defs.svg#sym`) are handled correctly (`join`
preserves the `#sym` suffix → `file:///…/defs.svg#sym`); regex ordering is safe
(`href` runs first but `(?<=\s)href` can't match inside `xlink:href`).

## Tests + verification

- `EPUBChapterBodyRewriterTests`: relative xlink:href / SVG2 href absolutized,
  same-dir, absolute-untouched, `<a href>` not absolutized (incl. near an `<image>`).
- Device-verified (v3.59.34, real book 道诡异仙 with an `<svg><image xlink:href>` cover,
  legacy continuous-scroll): the cover `<image>` resolves to `file:///…/OEBPS/Images/cover.jpg`,
  renders at 370×493 (not a 0×0 broken glyph) — screenshot shows the full cover.
  Evidence: `dev-docs/verification/bug-332-20260609.md`.

## Verdict

ship-as-is — the one Medium fixed + tested + device-verified.
