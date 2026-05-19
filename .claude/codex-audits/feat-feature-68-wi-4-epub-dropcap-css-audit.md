---
branch: feat/feature-68-wi-4-epub-dropcap-css
threadId: 019e3e00-1875-7053-890c-1fa9642f4651
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Feature #68 (reader chapter-start typography) Gate-4 audit for WI-4 — the
EPUB drop-cap CSS rule (mechanical "inject a CSS rule" WI). Changed files:

- `vreader/Models/ReaderThemeV2+EPUBCSS.swift` — `epubOverrideCSS`
  appends a `body > p:first-of-type::first-letter` drop-cap rule via a
  new private `dropCapCSSRule(accent:)` helper.
- `vreaderTests/Models/ReaderThemeV2EPUBCSSChapterStartTests.swift` (NEW).

## Round 1 findings

The **implementation was correct** (pinned `body > p:first-of-type::
first-letter` child-combinator selector, design declarations, existing
`h1..h6` rule untouched, accent path is internal-`UIColor`-only with no
injection surface). Three **test-quality** findings:

- **Medium** — selector / declaration assertions used loose substring
  matching of the whole stylesheet, not the extracted drop-cap rule
  block; a stray loose `p:first-of-type` rule would not fail the test.
- **Medium** — no `!important`-on-every-declaration assertion; per-theme
  accent verified only for Paper/Dark and matchable off the existing
  link/selection accent rules.
- **Low** — weak font-stack assertion (`contains("serif")` could match
  unrelated rules).

## Resolution

`ReaderThemeV2EPUBCSSChapterStartTests.swift` rewritten with a
`dropCapBlock(_:)` helper that extracts the rule body. `emitsPinnedSelector`
now asserts every `p:first-of-type::first-letter` occurrence is preceded
by `"body > "`; `singleFirstLetterRule` asserts exactly one
`::first-letter` rule; `everyDeclarationImportant` splits the extracted
block and asserts `!important` on each declaration; `perThemeAccentColor`
iterates all 5 themes; `dropCapSerifFontStack` pins the exact
`ReaderTypography.cssFontStack(for: .sourceSerif4)` string.

## Round 2 verdict

No remaining Critical/High/Medium findings. **ship-as-is.**
