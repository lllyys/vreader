---
branch: feat/feature-68-wi-5-foliate-dropcap-css
threadId: 019e3e0b-bb58-7913-840f-9d1ed058fc9e
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

## Scope

Feature #68 (reader chapter-start typography) Gate-4 audit for WI-5 — the
AZW3/MOBI (Foliate) drop-cap CSS rule (mechanical "inject a CSS rule" WI,
the Foliate sibling of WI-4). Changed files:

- `vreader/Services/Foliate/FoliateStyleMapper.swift` — `themeCSS` gains
  an `accentColor: String? = nil` parameter; when non-nil and
  `FoliateJSEscaper.sanitizeCSSColor` accepts it, appends a
  `body > p:first-of-type::first-letter` rule via a new private
  `dropCapRule(accent:)` helper.
- `vreader/Views/Reader/FoliateReaderContainerView.swift` — the
  `themeCSS` call passes `accentColor: Self.cssColor(store.theme.accentColor)`.
- `vreaderTests/Services/Foliate/FoliateStyleMapperChapterStartTests.swift`
  (NEW) — 8 tests.

## Round 1 findings

The **implementation was correct** and **bridge-safe**: sanitization
happens before interpolation, the only production call site passes
app-generated hex, the pinned selector + declarations match plan §4.5,
opt-out (`accentColor: nil`/empty → no rule) works, back-compat holds via
the defaulted parameter, and the UIKit-gate cross-reference
(`ChapterStartTypography.dropCapCSSFontSizeEm`) is not a blocker (iOS app
target). One **Low** test-quality finding:

- **Low** — the tests did not pin the serif font stack or the
  `margin-right` / `margin-top` declarations, so a drift from the EPUB
  WI-4 sibling rule could pass silently.

## Resolution

`FoliateStyleMapperChapterStartTests.dropCapDeclarations` now also
asserts (against the extracted drop-cap rule block) the serif stack
`'Source Serif 4', Georgia, 'Times New Roman', serif !important` and both
margin declarations — pinning full parity with
`ReaderThemeV2+EPUBCSS.dropCapCSSRule`.

## Round 2 verdict

No remaining Critical/High/Medium findings. **ship-as-is.**
