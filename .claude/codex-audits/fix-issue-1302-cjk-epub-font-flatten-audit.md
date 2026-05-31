---
branch: fix/issue-1302-cjk-epub-font-flatten
threadId: codex-exec-readonly
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Bug #294 / GH #1302 (CJK EPUB body font too big)

Read-only `codex exec` audit.

## Fix summary

- Root cause: the EPUB font-size flatten rule
  (`ReaderThemeV2+EPUBCSS.swift`) listed only
  `p, div, span, li, td, th, dd, dt, blockquote, figcaption`. CJK EPUBs
  commonly wrap prose in HTML5 semantic wrappers
  (`section/article/aside/main/header/footer/figure`) or legacy `<font>`
  carrying their own em/% size, which compounds past the 16px base. The
  sibling Foliate path (`FoliateStyleMapper`, Bug #261 FIXED) already widened
  its list.
- Fix: widen the EPUB flatten selector to add
  `section, article, aside, main, header, footer, figure, font`.

## Files

- `vreader/Models/ReaderThemeV2+EPUBCSS.swift` (flatten rule)
- `vreaderTests/Models/ReaderThemeV2EPUBCSSCalibrationTests.swift` (new `bug294` test)

## Findings

None. Codex verdict: safe and correctly targeted.
- Wrappers flatten to the `html, body` base; `<section style="font-size:1.2em">`
  no longer compounds.
- `figure` flattening acceptable (`figcaption` already flattened).
- `<font>` with `color: inherit` acceptable in the EPUB path (EPUB theming
  controls ink; neutralizes legacy `<font color>`).
- No heading overlap (`h1..h6` still `revert`).
- Foliate divergence (color) justified.

## Out of scope (documented)

The bug row's secondary, feature-shaped concern — CJK glyphs fill the em box so
they read larger than Latin at the same px (cross-script perceptual calibration
gap) — is NOT addressed here; it needs a calibration feature, not a flatten-list
fix. Left as a tracked note.

## Verdict

ship-as-is. Tests: `ReaderThemeV2EPUBCSSCalibrationTests` + `ReaderThemeCSSTests`
23/23 green (existing `bug57` substring preserved — change is additive).
CJK-EPUB font size device-verified against a real CJK EPUB at the close gate.
